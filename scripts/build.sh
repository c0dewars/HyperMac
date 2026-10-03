#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

run_tests=false
install_app=true
ad_hoc=false
universal=false
for argument in "$@"; do
    case "$argument" in
        --universal) universal=true ;;
        --ad-hoc) ad_hoc=true ;;
        --test) run_tests=true ;;
        --build-only) install_app=false ;;
        --help|-h)
            echo "Usage: bash scripts/build.sh [--test] [--build-only] [--ad-hoc] [--universal]"
            echo "Builds, installs into Applications and opens HyperMac."
            echo "--test runs XCTest first using full Xcode. --build-only skips installation."
            exit 0 ;;
        *) echo "Unknown argument: $argument" >&2; exit 2 ;;
    esac
done

if [[ "$ad_hoc" == true && "$install_app" == true ]]; then
    echo "--ad-hoc requires --build-only; installed builds must keep a stable signing identity." >&2
    exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build HyperMac on macOS 14 or later, with Xcode Command Line Tools installed." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install developer tools first: xcode-select --install" >&2
    exit 1
fi

project_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
echo "HyperMac $project_version — source: $PWD"
case "$PWD/" in
    */.Trash/*)
        echo "This source folder is in Trash. Open Terminal in the newly extracted project and build there." >&2
        exit 1 ;;
esac

if [[ "$run_tests" == true ]]; then
    if ! xcrun xcodebuild -version >/dev/null 2>&1; then
        echo "Tests require full Xcode selected; this toolchain cannot provide the XCTest setup." >&2
        echo "After installing/opening Xcode, run:" >&2
        echo "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build.sh --test" >&2
        echo "To build only, run bash scripts/build.sh without --test." >&2
        exit 1
    fi
    xcrun swift test
else
    echo "Building app only. Tests are not run; use --test with full Xcode to run them."
fi
app_dir="$PWD/dist/HyperMac.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
architectures=("$(uname -m)")
if [[ "$universal" == true ]]; then architectures=(arm64 x86_64); fi
binaries=()
for architecture in "${architectures[@]}"; do
    xcrun swift build --configuration release --arch "$architecture" --product HyperMac
    bin_dir="$(xcrun swift build --configuration release --arch "$architecture" --show-bin-path)"
    binaries+=("$bin_dir/HyperMac")
done
if [[ "$universal" == true ]]; then
    xcrun lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/HyperMac"
else
    cp "${binaries[0]}" "$app_dir/Contents/MacOS/HyperMac"
fi
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
if [[ "$ad_hoc" == true ]]; then
    bash scripts/sign.sh "$app_dir" --ad-hoc
else
    bash scripts/sign.sh "$app_dir"
fi
echo "Built $app_dir"
if [[ "$install_app" == true ]]; then
    bash scripts/install.sh "$app_dir"
else
    echo "Install later with: bash scripts/install.sh"
fi
