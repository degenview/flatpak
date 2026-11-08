#!/usr/bin/env bash
# Makes the key that signs the repo. Run it once, on your own machine.
#
#   tools/generate-signing-key.sh <private-key-file>
#
# The private key goes to the file you name (mode 0600), never to the terminal. Put its contents in
# the `FLATPAK_GPG_KEY` secret of the `publish` environment, then delete the file; keep a copy in
# your password manager. The key has no passphrase, because the workflow cannot answer a prompt, and
# no expiry: users add the repo once with this key's public half, and a different key means every
# one of them has to add it again.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <private-key-file>" >&2
  exit 2
fi
out="$1"
if [ -e "$out" ]; then
  echo "$out exists; not overwriting it." >&2
  exit 1
fi

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT

gpg --batch --quiet --passphrase '' \
  --quick-generate-key "DegenView Flatpak repository <flatpak@degenview.app>" rsa4096 sign never
fingerprint="$(gpg --batch --list-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')"

umask 077
gpg --batch --armor --export-secret-keys "$fingerprint" > "$out"

echo "Signing key fingerprint: $fingerprint"
echo "Private key written to $out (delete it after you have stored it)."
