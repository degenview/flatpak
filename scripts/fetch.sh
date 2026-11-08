#!/usr/bin/env bash
# Chooses which releases of the app to publish, and downloads and verifies their Flatpak bundles.
# Runs in the `fetch` job, which has no secrets.
#
#   SOURCE_REPO   owner/name of the app repository (degenview/degenview)
#   SITE_URL      where this repo is served (https://flatpak.degenview.app)
#   GH_TOKEN      the workflow's own token; the releases are public
#   FORCE         "true" publishes even when the live site already lists the same releases
#   OUT           output directory (default out)
#
# Writes $OUT/selected.json, $OUT/state.json and $OUT/bundles/*.flatpak, and `changed=true|false`
# to $GITHUB_OUTPUT.
set -euo pipefail

: "${SOURCE_REPO:?}" "${SITE_URL:?}" "${GITHUB_OUTPUT:?}"
FORCE="${FORCE:-false}"
OUT="${OUT:-out}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
. "$here/../config.env"
: "${SINCE_PUBLISHED_AT:?}"

mkdir -p "$OUT/bundles"

# Releases the app's own release workflow made. Anything else (a draft, a release somebody made by
# hand, an odd tag name) is not published.
gh api "repos/${SOURCE_REPO}/releases?per_page=50" > "$OUT/releases.json"

jq --arg since "$SINCE_PUBLISHED_AT" '
  # Order by version, never by upload time: a patch release for an old line must not outrank a
  # candidate of a newer line. A final is newer than its own candidates.
  def version_key:
    capture("^v(?<a>[0-9]+)\\.(?<b>[0-9]+)\\.(?<c>[0-9]+)(-rc\\.(?<n>[0-9]+))?$")
    | [(.a | tonumber), (.b | tonumber), (.c | tonumber),
       (if .n then 0 else 1 end),
       ((.n // "0") | tonumber)];

  [ .[]
    | select(.draft | not)
    | select(.author.login == "github-actions[bot]")
    | select(.published_at >= $since)
    # Only finals and `-rc.N`: the updater of the app offers an alpha or beta tag to no channel, so
    # neither does this repo (release.yml builds those on the `dev` branch).
    | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+(-rc\\.[0-9]+)?$"))
    | {tag: .tag_name, prerelease: .prerelease, assets: [.assets[].name]}
    | select(
        . as $r
        | ($r.assets | index("DegenView-" + $r.tag + "-linux-x64.flatpak")) != null
          and ($r.assets | index("DegenView-" + $r.tag + "-linux-arm64.flatpak")) != null)
    | {tag, prerelease}
  ] as $all
  | ($all | sort_by(.tag | version_key) | reverse) as $newest_first
  # `stable` is the newest final. `beta` is the newest release of any kind: a Flatpak follows its own
  # branch and never switches, and the Release Candidate channel of the app accepts finals, so a
  # final has to reach `beta` too.
  | ($newest_first | map(select(.prerelease | not)) | first) as $stable
  | ($newest_first | first) as $beta
  | if $beta == null then []
    else
      (if $stable == null then []
       else [{tag: $stable.tag,
              branches: (["stable"] + (if $stable.tag == $beta.tag then ["beta"] else [] end))}]
       end)
      + (if $stable != null and $stable.tag == $beta.tag then []
         else [{tag: $beta.tag, branches: ["beta"]}]
         end)
    end
' "$OUT/releases.json" > "$OUT/selected.json"

jq -c 'sort_by(.tag)' "$OUT/selected.json" > "$OUT/state.json"

if [ "$(jq 'length' "$OUT/selected.json")" -eq 0 ]; then
  echo "No release to publish yet (none published since ${SINCE_PUBLISHED_AT} with both bundles)."
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Nothing to do when the live site already lists exactly these releases.
live="$(curl -fsS --max-time 20 "${SITE_URL}/state.json" 2>/dev/null | jq -c . 2>/dev/null || true)"
if [ "$FORCE" != "true" ] && [ "$live" = "$(cat "$OUT/state.json")" ]; then
  echo "The site already lists $(cat "$OUT/state.json"); nothing to publish."
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Download and check every bundle. The release must be immutable, the asset must be the one the
# release recorded, and the build provenance must name the app's release workflow.
while read -r tag; do
  gh release verify "$tag" --repo "$SOURCE_REPO"
  for cpu in x64 arm64; do
    name="DegenView-${tag}-linux-${cpu}.flatpak"
    gh release download "$tag" --repo "$SOURCE_REPO" --pattern "$name" --dir "$OUT/bundles"
    gh release verify-asset "$tag" "$OUT/bundles/$name" --repo "$SOURCE_REPO"
    gh attestation verify "$OUT/bundles/$name" --repo "$SOURCE_REPO" \
      --signer-workflow "${SOURCE_REPO}/.github/workflows/release.yml"
  done
done < <(jq -r '.[].tag' "$OUT/selected.json")

echo "changed=true" >> "$GITHUB_OUTPUT"
