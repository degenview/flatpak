#!/usr/bin/env bash
# Installs the app from the repo that was just built, the way a user would from the published one,
# but over file://. It proves the signature, the summary and the ref are good before anything is
# deployed. No secrets here: the key is long gone by now. The runtime is not needed (--no-deps).
#
#   SITE   the directory build-repo.sh made (default site)
set -euo pipefail

SITE="${SITE:-site}"
APP_ID="es.nico.degenview"
site_path="$(cd "$SITE" && pwd)"

# A private Flatpak installation, so nothing of the runner's is touched.
export XDG_DATA_HOME
XDG_DATA_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_DATA_HOME"' EXIT

# The same file users get, with the URL pointed at the local copy.
sed "s#^Url=.*#Url=file://${site_path}/repo/#" "$SITE/degenview.flatpakrepo" > "$XDG_DATA_HOME/smoke.flatpakrepo"
flatpak --user remote-add --if-not-exists smoke "$XDG_DATA_HOME/smoke.flatpakrepo"
flatpak --user remote-ls smoke --app --columns=application,branch,arch

for branch in stable beta; do
  if flatpak --user remote-info smoke "${APP_ID}//${branch}" > /dev/null 2>&1; then
    flatpak --user install --noninteractive --no-deps smoke "${APP_ID}//${branch}"
    flatpak --user info "${APP_ID}//${branch}"
    flatpak --user uninstall --noninteractive "${APP_ID}//${branch}"
    found=true
  fi
done

# When a final release feeds both branches, both must be there and name the same version.
if [ -f "$SITE/state.json" ] && jq -e 'any(.[]; (.branches | index("stable")) and (.branches | index("beta")))' "$SITE/state.json" > /dev/null; then
  versions=()
  for branch in stable beta; do
    if ! info="$(flatpak --user remote-info smoke "${APP_ID}//${branch}" 2>&1)"; then
      echo "::error::${APP_ID}//${branch} is missing, but a final release should feed both branches."
      exit 1
    fi
    versions+=("$(printf '%s\n' "$info" | sed -n 's/^ *Version: *//p' | head -n 1)")
  done
  if [ -n "${versions[0]}" ] && [ -n "${versions[1]}" ] && [ "${versions[0]}" != "${versions[1]}" ]; then
    echo "::error::stable is ${versions[0]} but beta is ${versions[1]}; beta should follow the final release."
    exit 1
  fi
  echo "stable and beta both at '${versions[0]:-unknown}'."
fi
if [ "${found:-false}" != true ]; then
  echo "::error::Neither ${APP_ID}//stable nor //beta can be installed from the repo."
  exit 1
fi
