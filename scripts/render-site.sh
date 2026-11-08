#!/usr/bin/env bash
# Copies the static landing page (web/) into the site directory and fills in its placeholders.
# Called by build-repo.sh, and by hand to look at the page (tools/preview-site.sh).
#
#   SITE         the directory to write into (must exist)
#   SITE_URL     where the site is served (https://flatpak.degenview.app)
#   APP_ID       the Flatpak application id
#   FINGERPRINT  the signing key's fingerprint, 40 hex digits
#   STATE        the fetch job's state.json: [{"tag": "v1.2.3", "branches": ["stable", "beta"]}, ...]
set -euo pipefail

: "${SITE:?}" "${SITE_URL:?}" "${APP_ID:?}" "${FINGERPRINT:?}" "${STATE:?}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
web="$here/../web"

cp -R "$web"/. "$SITE"/

stable="$(jq -r 'map(select(.branches | index("stable"))) | first | .tag // ""' "$STATE")"
beta="$(jq -r 'map(select(.branches | index("beta"))) | first | .tag // ""' "$STATE")"

if [ -n "$stable" ]; then
  stable_text="$stable"
  stable_class=""
  stable_note="the newest final release, $stable"
  default_channel="stable"
  stable_btn_hidden=""
  default_ref="${APP_ID}.flatpakref"
else
  stable_text="No final release yet"
  stable_class="none"
  stable_note="no final release yet, use beta for now"
  default_channel="beta"
  stable_btn_hidden=" hidden"
  default_ref="${APP_ID}.beta.flatpakref"
fi
if [ -n "$beta" ]; then
  beta_text="$beta"
  beta_class=""
  beta_note="the newest release candidate or final, $beta"
else
  beta_text="Nothing published yet"
  beta_class="none"
  beta_note="nothing published yet"
fi

# Four hex digits at a time, easier to compare by eye.
fingerprint_spaced="$(printf '%s' "$FINGERPRINT" | sed 's/.\{4\}/& /g; s/ $//')"

# Everything substituted is a URL, an id, a version tag, hex or fixed text: none contains `|` or `&`.
sed -i.bak \
  -e "s|{{SITE_URL}}|${SITE_URL}|g" \
  -e "s|{{APP_ID}}|${APP_ID}|g" \
  -e "s|{{FINGERPRINT_SPACED}}|${fingerprint_spaced}|g" \
  -e "s|{{STABLE_NOTE}}|${stable_note}|g" \
  -e "s|{{BETA_NOTE}}|${beta_note}|g" \
  -e "s|{{STABLE_CLASS}}|${stable_class}|g" \
  -e "s|{{BETA_CLASS}}|${beta_class}|g" \
  -e "s|{{STABLE_BTN_HIDDEN}}|${stable_btn_hidden}|g" \
  -e "s|{{STABLE}}|${stable_text}|g" \
  -e "s|{{BETA}}|${beta_text}|g" \
  -e "s|{{DEFAULT_CHANNEL}}|${default_channel}|g" \
  -e "s|{{DEFAULT_REF_FILE}}|${default_ref}|g" \
  "$SITE/index.html"
rm -f "$SITE/index.html.bak"

if grep -n '{{' "$SITE/index.html"; then
  echo "::error::index.html has a placeholder that render-site.sh does not fill."
  exit 1
fi
