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
if [ "${found:-false}" != true ]; then
  echo "::error::Neither ${APP_ID}//stable nor //beta can be installed from the repo."
  exit 1
fi
