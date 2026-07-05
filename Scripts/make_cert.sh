#!/usr/bin/env bash
# One-time setup: creates a STABLE self-signed code-signing certificate in the
# login keychain. Signing every release with it means macOS keys granted TCC
# permissions (Accessibility, Automation) to this identity — not to the per-build
# cdhash — so they SURVIVE auto-updates. Run once; `make app` picks it up.
#
# The signature stays "untrusted by Gatekeeper" (like ad-hoc), so first launch
# still needs right-click → Open. That's expected without an Apple Developer ID.
set -euo pipefail

CERT_NAME="Prism Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Certificate “$CERT_NAME” already present — nothing to do."
    exit 0
fi

echo "▸ Generating self-signed code-signing certificate “$CERT_NAME”…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -passout pass:prism 2>/dev/null

echo "▸ Importing into the login keychain (you may be asked to allow codesign)…"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P prism -T /usr/bin/codesign -A

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Done. Re-run 'make app' — releases will now sign with a stable identity."
else
    echo "✗ Certificate not found after import. Check Keychain Access and retry."
    exit 1
fi
