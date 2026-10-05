#!/bin/bash
# Package an already-built Apple Silicon preview. This does not notarize it.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/HyperMac.app"
[[ -d "$app" ]] || { echo "Build HyperMac first." >&2; exit 1; }
codesign --verify --strict "$app"
[[ "$(xcrun lipo -archs "$app/Contents/MacOS/HyperMac")" == "arm64" ]] || {
    echo "Only Apple Silicon bundles can be packaged." >&2; exit 1;
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid bundle version." >&2; exit 1; }
staging="$(mktemp -d "${TMPDIR:-/tmp}/hypermac-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/HyperMac.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/READ ME.txt" <<'NOTICE'
HyperMac development preview — Apple Silicon, macOS 14+

Drag HyperMac into Applications before opening it. Quit an existing copy first.
Grant Accessibility in System Settings to allow window management.

This preview is ad-hoc signed, not Apple-notarized. Gatekeeper may block it.
It is for development testing, not a trusted production installer. A local
certificate-signed installation may require Accessibility permission to be
refreshed if replaced by this preview. Prefer the README's source build process
for a stable local signing identity across updates.

Source and instructions: https://github.com/c0dewars/HyperMac
NOTICE
mkdir -p dist
output="dist/HyperMac-$version-apple-silicon-preview.dmg"
hdiutil create -volname "HyperMac Preview" -srcfolder "$staging" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
echo "Preview package: $output (not notarized)"
