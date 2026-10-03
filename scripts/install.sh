#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

allow_identity_change=false
if [[ "${1:-}" == "--allow-identity-change" ]]; then allow_identity_change=true; shift; fi
app_source="${1:-$PWD/dist/HyperMac.app}"
if [[ "$(uname -s)" != "Darwin" || ! -f "$app_source/Contents/MacOS/HyperMac" ]]; then
    echo "Build the macOS app first: bash scripts/build.sh" >&2
    exit 1
fi
if pgrep -x HyperMac >/dev/null 2>&1; then
    echo "Quit HyperMac from its menu-bar icon, then run: bash scripts/install.sh" >&2
    exit 1
fi
codesign --verify --strict "$app_source"

# Keep an existing user installation at its original path for Accessibility identity.
if [[ -d "$HOME/Applications/HyperMac.app" && ! -d /Applications/HyperMac.app ]]; then
    install_dir="$HOME/Applications"
elif [[ -w /Applications ]]; then
    install_dir="/Applications"
elif [[ -e /Applications/HyperMac.app ]]; then
    echo "HyperMac already exists in /Applications, which is not writable by this account." >&2
    echo "Use Finder to replace it with: $app_source" >&2
    open -R "$app_source"
    exit 1
else
    install_dir="$HOME/Applications"
fi

app_destination="$install_dir/HyperMac.app"
identity_file="$HOME/.config/hypermac/signing-identity"
identity="${HYPERMAC_SIGNING_IDENTITY:-}"
if [[ -z "$identity" && -f "$identity_file" ]]; then identity="$(cat "$identity_file")"; fi
[[ "$identity" =~ ^[[:xdigit:]]{40}$ ]] || { echo "Pinned signing identity missing." >&2; exit 1; }
codesign --verify --strict -R "=identifier \"local.hypermac.app\" and certificate leaf = H\"$identity\"" "$app_source"
source_requirement="$(codesign -d -r- "$app_source" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$source_requirement" || "$source_requirement" == *cdhash* ]]; then
    echo "Refusing to install an ad-hoc build. Configure stable signing first." >&2
    exit 1
fi
if [[ -d "$app_destination" && "$app_source" != "$app_destination" ]]; then
    old_requirement="$(codesign -d -r- "$app_destination" 2>&1 | sed -n 's/^designated => //p')"
    if [[ -z "$old_requirement" ]] || ! codesign --verify --strict -R "=$old_requirement" "$app_source" 2>/dev/null; then
        if [[ "$allow_identity_change" != true ]]; then
            echo "Signing identity changed. Existing Accessibility permission may not carry over." >&2
            echo "For the one-time migration, run: bash scripts/install.sh --allow-identity-change" >&2
            exit 1
        fi
        echo "Performing explicitly requested signing-identity migration."
    fi
fi
mkdir -p "$install_dir"
if [[ "$app_source" != "$app_destination" ]]; then
    ditto "$app_source" "$app_destination"
fi
codesign --verify --strict "$app_destination"

echo "Installed: $app_destination"
if [[ "$allow_identity_change" == true ]]; then
    echo "One-time migration: refresh Accessibility for the installed app if macOS requires it."
else
    echo "Signing identity verified. Existing permission should remain valid."
fi
open -R "$app_destination"
open "$app_destination"
