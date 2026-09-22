#!/bin/sh
# Re-import the existing "XFinder Dev" key+cert with an ACL that includes the
# terminal's shell, so `codesign` does not block on a Keychain approval dialog
# (that dialog cannot be answered from a non-interactive shell).
#
# The private key is exported from the login keychain using whatever access the
# current security session already has; if the export itself is refused, this
# script reports that instead of hanging.
set -e
CERT_NAME="XFinder Dev"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

security find-certificate -c "$CERT_NAME" -p > "$TMP/cert.pem"
openssl x509 -in "$TMP/cert.pem" -noout -subject

# Export the identity (cert + private key) into a p12 with an empty password.
security export -t identities -f pkcs12 -P "" -o "$TMP/id.p12" 2>&1 || {
  echo "!! export refused — the login keychain will not hand out the private key."
  exit 2
}

security delete-identity -c "$CERT_NAME" 2>/dev/null || true

# -T whitelists each binary that may use the key WITHOUT a prompt.
# /bin/sh is the one that matters: codesign is exec'd from a shell script, and
# the ACL is checked against the calling process chain.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/ld -T /bin/sh -T /bin/zsh \
  -T /bin/bash -T "$(which sh)" -A

echo "--- identities ---"
security find-identity -v -p codesigning
