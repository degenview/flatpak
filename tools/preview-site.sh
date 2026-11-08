#!/usr/bin/env bash
# Renders the landing page with sample data and serves it, to look at a change to web/ without
# running the workflow. Needs jq and python3.
#
#   tools/preview-site.sh [stable+beta|beta-only] [port]
set -euo pipefail

mode="${1:-stable+beta}"
port="${2:-8099}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

case "$mode" in
  stable+beta) state='[{"tag":"v0.6.0","branches":["stable"]},{"tag":"v0.7.0-rc.2","branches":["beta"]}]' ;;
  beta-only) state='[{"tag":"v0.6.0-rc.16","branches":["beta"]}]' ;;
  *) echo "usage: $0 [stable+beta|beta-only] [port]" >&2; exit 2 ;;
esac
printf '%s\n' "$state" > "$out/state.json"
mkdir "$out/site"

SITE="$out/site" SITE_URL="http://localhost:${port}" APP_ID="es.nico.degenview" \
  FINGERPRINT="0123456789ABCDEF0123456789ABCDEF01234567" STATE="$out/state.json" \
  "$here/../scripts/render-site.sh"

echo "http://localhost:${port}/ (Ctrl-C to stop)"
cd "$out/site"
python3 -m http.server "$port" --bind 127.0.0.1
