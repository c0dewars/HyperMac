#!/bin/bash
set -euo pipefail
app_path="${1:?Usage: sign.sh APP [--ad-hoc]}"
identity_file="$HOME/.config/hypermac/signing-identity"
if [[ "${2:-}" == "--ad-hoc" ]]; then
    codesign --force --sign - --identifier local.hypermac.app "$app_path"
else
    identity="${HYPERMAC_SIGNING_IDENTITY:-}"
    if [[ -z "$identity" && -f "$identity_file" ]]; then identity="$(cat "$identity_file")"; fi
    if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
        echo "No pinned signing identity. Run bash scripts/setup-local-signing.sh once." >&2
        echo "For a disposable build only, use --ad-hoc --build-only." >&2
        exit 1
    fi
    codesign --force --sign "$identity" --options runtime --timestamp=none \
        --identifier local.hypermac.app "$app_path"
    codesign --verify --strict -R "=identifier \"local.hypermac.app\" and certificate leaf = H\"$identity\"" "$app_path"
fi
codesign --verify --strict "$app_path"
codesign -d -r- "$app_path" 2>&1
