#!/usr/bin/env bash
# Builds the signed OSTree repo and the files around it from the verified bundles. Runs in the
# `sign` job, the only place the signing key exists.
#
#   FLATPAK_GPG_KEY   the armored private signing key (no passphrase), from the `publish` environment
#   SITE_URL          where the site is served (https://flatpak.degenview.app)
#   IN                the fetch job's output (default in)
#   SITE              the directory to build (default site)
#
# The key is imported into a throwaway GNUPGHOME that is removed when the script ends.
set -euo pipefail

: "${FLATPAK_GPG_KEY:?}" "${SITE_URL:?}"
IN="${IN:-in}"
SITE="${SITE:-site}"
APP_ID="es.nico.degenview"
MAX_MEGABYTES=500

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT

printf '%s\n' "$FLATPAK_GPG_KEY" | gpg --batch --quiet --import
KEYID="$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ -z "$KEYID" ]; then
  echo "::error::FLATPAK_GPG_KEY holds no secret key."
  exit 1
fi
gpg --batch --export "$KEYID" > "$GNUPGHOME/public.gpg"

rm -rf "$SITE"
mkdir -p "$SITE"
ostree init --repo="$SITE/repo" --mode=archive-z2

shopt -s nullglob
bundles=("$IN"/bundles/*.flatpak)
if [ "${#bundles[@]}" -eq 0 ]; then
  echo "::error::No bundle to import."
  exit 1
fi
for bundle in "${bundles[@]}"; do
  flatpak build-import-bundle --no-update-summary \
    --gpg-sign="$KEYID" --gpg-homedir="$GNUPGHOME" "$SITE/repo" "$bundle"
done

# A final release is built once, on `stable`. An installed app follows its own branch and never
# switches, and the Release Candidate channel accepts finals, so when the release `beta` serves (the
# newest final or `-rc.N`) is a final, it has to be on `beta` too. `build-commit-from` makes a new commit for the other branch from
# the same files (it rewrites the ref binding that Flatpak checks on install) and signs it.
while read -r tag; do
  for arch in x86_64 aarch64; do
    stable_ref="app/${APP_ID}/${arch}/stable"
    # Read into a variable first: `grep -q` can end a pipe early, which pipefail turns into a failure.
    refs="$(ostree refs --repo="$SITE/repo")"
    if ! grep -qx "$stable_ref" <<< "$refs"; then
      echo "::error::${tag} should also be on beta, but ${stable_ref} was not imported."
      exit 1
    fi
    flatpak build-commit-from --no-update-summary \
      --gpg-sign="$KEYID" --gpg-homedir="$GNUPGHOME" \
      --src-ref="$stable_ref" "$SITE/repo" "app/${APP_ID}/${arch}/beta"
  done
done < <(jq -r '.[] | select((.branches | index("beta")) and (.branches | index("stable"))) | .tag' "$IN/selected.json")

# Only the two channel branches are served. A bundle still on `master` (built before channels) is
# dropped here even if it got past the date in config.env.
kept=0
while read -r ref; do
  case "$ref" in
    "app/${APP_ID}/x86_64/stable" | "app/${APP_ID}/aarch64/stable" | \
      "app/${APP_ID}/x86_64/beta" | "app/${APP_ID}/aarch64/beta")
      kept=$((kept + 1))
      ;;
    *)
      echo "::warning::Dropping ref ${ref}: not a stable or beta branch."
      ostree refs --repo="$SITE/repo" --delete "$ref"
      ;;
  esac
done < <(ostree refs --repo="$SITE/repo")
if [ "$kept" -eq 0 ]; then
  echo "::error::No bundle is on a stable or beta branch. Set SINCE_PUBLISHED_AT in config.env to the first release built with channels."
  exit 1
fi

flatpak build-update-repo --prune \
  --title=DegenView --default-branch=stable \
  --gpg-import="$GNUPGHOME/public.gpg" \
  --gpg-sign="$KEYID" --gpg-homedir="$GNUPGHOME" "$SITE/repo"
rm -rf "$SITE/repo/tmp" "$SITE/repo/.lock"

# The site around the repo.
fingerprint="$KEYID"
key_base64="$(base64 < "$GNUPGHOME/public.gpg" | tr -d '\n')"
repo_url="${SITE_URL}/repo/"
host="${SITE_URL#https://}"

cat > "$SITE/degenview.flatpakrepo" <<EOF
[Flatpak Repo]
Title=DegenView
Comment=DegenView, an open source market dashboard
Homepage=https://degenview.app
Url=${repo_url}
DefaultBranch=stable
GPGKey=${key_base64}
EOF

for channel in stable beta; do
  if [ "$channel" = stable ]; then file="${APP_ID}.flatpakref"; else file="${APP_ID}.beta.flatpakref"; fi
  cat > "$SITE/$file" <<EOF
[Flatpak Ref]
Title=DegenView
Name=${APP_ID}
Branch=${channel}
IsRuntime=false
Url=${repo_url}
SuggestRemoteName=degenview
Homepage=https://degenview.app
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
GPGKey=${key_base64}
EOF
done

cp "$IN/state.json" "$SITE/state.json"
printf '%s\n' "$host" > "$SITE/CNAME"

# The landing page is a real file (web/index.html); this fills in the versions and the key.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE="$SITE" SITE_URL="$SITE_URL" APP_ID="$APP_ID" FINGERPRINT="$fingerprint" STATE="$IN/state.json" \
  "$here/render-site.sh"

size="$(du -sm "$SITE" | cut -f1)"
echo "Site is ${size} MB."
if [ "$size" -gt "$MAX_MEGABYTES" ]; then
  echo "::error::The site is ${size} MB, over the ${MAX_MEGABYTES} MB this workflow allows (GitHub Pages sites are limited to 1 GB)."
  exit 1
fi
