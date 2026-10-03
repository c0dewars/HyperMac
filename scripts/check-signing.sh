#!/bin/bash
# Checks stable identity with different signed contents without touching installation.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="${1:-$PWD/dist/HyperMac.app}"
signing_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/hypermac-signing-test.XXXXXX")"
trap 'rm -rf "$signing_test_dir"' EXIT
codesign --verify --strict "$source_app"
requirement="$(codesign -d -r- "$source_app" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$requirement" && "$requirement" != *cdhash* ]] || { echo "Certificate signing required." >&2; exit 1; }
ditto "$source_app" "$signing_test_dir/Update.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999999' "$signing_test_dir/Update.app/Contents/Info.plist"
bash scripts/sign.sh "$signing_test_dir/Update.app"
codesign --verify --strict -R "=$requirement" "$signing_test_dir/Update.app"
updated_requirement="$(codesign -d -r- "$signing_test_dir/Update.app" 2>&1 | sed -n 's/^designated => //p')"
[[ "$requirement" == "$updated_requirement" ]]
old_hash="$(codesign -d -v "$source_app" 2>&1 | sed -n 's/^CDHash=//p')"
new_hash="$(codesign -d -v "$signing_test_dir/Update.app" 2>&1 | sed -n 's/^CDHash=//p')"
[[ -n "$old_hash" && -n "$new_hash" && "$old_hash" != "$new_hash" ]]
bash scripts/sign.sh "$signing_test_dir/Update.app" --ad-hoc
if codesign --verify --strict -R "=$requirement" "$signing_test_dir/Update.app" 2>/dev/null; then
    echo "FAIL: ad-hoc signature unexpectedly satisfied certificate identity." >&2; exit 1
fi
echo "PASS: different build hashes, same designated requirement, certificate update accepted, ad-hoc replacement rejected."
