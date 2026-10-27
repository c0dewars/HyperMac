#!/bin/bash
# Package an ad-hoc-signed Apple Silicon development preview.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 0 ]] || { echo "Usage: package-dmg.sh" >&2; exit 2; }
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
codesign --force --sign - --identifier local.hypermac.app "$staging/HyperMac.app"
codesign --verify --strict "$staging/HyperMac.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/READ ME.txt" <<'NOTICE'
HyperMac development preview — Apple Silicon, macOS 14+

Drag HyperMac into Applications before opening it. Quit an existing copy first.
Grant Accessibility in System Settings to allow window management. HyperMac
runs in the menu bar; click its icon to open Settings.

If macOS cannot verify the developer, first try opening the installed app,
then use System Settings > Privacy & Security > Open Anyway for HyperMac.
This is Apple's per-app exception for a preview you choose to trust; it does
not disable Gatekeeper. The preview is not equivalent to a notarized release.

This preview is ad-hoc signed, not Apple-notarized. Gatekeeper may block it.
It is for development testing, not a trusted production installer. Each update
may require Accessibility permission to be refreshed.

Homebrew users can install and update with:
  brew install --cask c0dewars/tap/hypermac

Source and instructions: https://github.com/c0dewars/HyperMac
NOTICE
mkdir -p dist
output="dist/HyperMac-$version-apple-silicon-preview.dmg"
volume="HyperMac Preview"
hdiutil create -volname "$volume" -srcfolder "$staging" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
echo "Packaged: $output"
