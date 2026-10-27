#!/bin/bash
# Builds an ad-hoc-signed Apple Silicon app bundle for development, CI and packaging.
# End users install with Homebrew: brew install --cask c0dewars/tap/hypermac
set -euo pipefail
cd "$(dirname "$0")/.."

run_tests=false
for argument in "$@"; do
    case "$argument" in
        --test) run_tests=true ;;
        --help|-h)
            echo "Usage: bash scripts/build.sh [--test]"
            echo "Builds dist/HyperMac.app (ad-hoc signed). --test runs XCTest first using full Xcode."
            exit 0 ;;
        *) echo "Unknown argument: $argument" >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build HyperMac on macOS 14 or later, with Xcode installed." >&2
    exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "HyperMac requires Apple Silicon. Run Terminal natively, outside Rosetta." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install developer tools first: xcode-select --install" >&2
    exit 1
fi

project_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
echo "HyperMac $project_version — source: $PWD"

if [[ "$run_tests" == true ]]; then
    if ! xcrun xcodebuild -version >/dev/null 2>&1; then
        echo "Tests require full Xcode selected; this toolchain cannot provide the XCTest setup." >&2
        echo "After installing/opening Xcode, run:" >&2
        echo "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build.sh --test" >&2
        exit 1
    fi
    xcrun swift test
fi
app_dir="$PWD/dist/HyperMac.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swift build --configuration release --arch arm64 --product HyperMac
bin_dir="$(xcrun swift build --configuration release --arch arm64 --show-bin-path)"
cp "$bin_dir/HyperMac" "$app_dir/Contents/MacOS/HyperMac"
[[ "$(xcrun lipo -archs "$app_dir/Contents/MacOS/HyperMac")" == "arm64" ]] || {
    echo "Expected an Apple Silicon binary." >&2; exit 1;
}
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.hypermac.app "$app_dir"
codesign --verify --strict "$app_dir"
echo "Built $app_dir"
