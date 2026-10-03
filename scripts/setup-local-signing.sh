#!/bin/bash
# Creates a reusable, user-local signing identity. Never regenerate it per build.
set -euo pipefail
identity_dir="$HOME/.config/hypermac"
identity_file="$identity_dir/signing-identity"
if [[ -f "$identity_file" ]]; then
    echo "A signing identity is already pinned at $identity_file. Leaving it unchanged."
    exit 0
fi
keychain_path="$HOME/Library/Keychains/login.keychain-db"
[[ -f "$keychain_path" ]] || { echo "Login keychain not found." >&2; exit 1; }
umask 077
signing_tmp="$(mktemp -d "${TMPDIR:-/tmp}/hypermac-signing.XXXXXX")"
trap 'rm -rf "$signing_tmp"' EXIT
cat > "$signing_tmp/certificate.cnf" <<'CERT'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = HyperMac Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
CERT
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -config "$signing_tmp/certificate.cnf" -keyout "$signing_tmp/private.pem" \
    -out "$signing_tmp/certificate.pem" 2> "$signing_tmp/keygen.log"
/usr/bin/openssl rand -base64 32 > "$signing_tmp/password"
/usr/bin/openssl pkcs12 -export -inkey "$signing_tmp/private.pem" \
    -in "$signing_tmp/certificate.pem" -name "HyperMac Local Development" \
    -out "$signing_tmp/identity.p12" -passout "file:$signing_tmp/password"
# Allow only Apple's codesign tool, not all applications, to use this private key.
security import "$signing_tmp/identity.p12" -k "$keychain_path" \
    -P "$(cat "$signing_tmp/password")" -T /usr/bin/codesign
# User trust is limited to the code-signing policy; no TLS/root trust is added.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain_path" "$signing_tmp/certificate.pem"
identity="$(/usr/bin/openssl x509 -in "$signing_tmp/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')"
security find-identity -v -p codesigning "$keychain_path" | grep -Fq "$identity" || {
    echo "Certificate imported but not available for signing. Check Keychain Access before retrying." >&2; exit 1;
}
mkdir -p "$identity_dir"
printf '%s\n' "$identity" > "$identity_file"
chmod 600 "$identity_file"
echo "Local signing identity created and pinned. Private key stays in your login Keychain."
echo "Keep this certificate/key for future builds; deleting it requires a new permission migration."
