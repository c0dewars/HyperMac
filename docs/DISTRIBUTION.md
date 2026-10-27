# Sharing HyperMac without a paid Apple account

HyperMac can be distributed as an ad-hoc-signed DMG. Recipients must explicitly allow the app because it is not signed with Developer ID or notarized by Apple. This does not require them to buy a developer membership.

## Install with Homebrew

```sh
brew install --cask c0dewars/tap/hypermac
```

The cask lives in the public [c0dewars/homebrew-tap](https://github.com/c0dewars/homebrew-tap) repository and downloads the DMG from this repository's GitHub Releases, so release assets must be publicly downloadable. Then follow steps 4–6 below. Update with `brew upgrade --cask hypermac`.

## Install a trusted preview manually

1. Use an Apple Silicon Mac running macOS 14 or later. Intel Macs are unsupported.
2. Download the DMG from HyperMac's GitHub Releases. This repository is private, so downloads require repository access; an authorized owner can also share the downloaded DMG directly.
3. Quit an older HyperMac, open the DMG and drag HyperMac to Applications. Eject the DMG.
4. Try opening the installed app. If macOS says it cannot verify the developer, follow [Apple's per-app Open Anyway instructions](https://support.apple.com/102445) in System Settings → Privacy & Security, provided you trust the download.
5. Enable HyperMac under System Settings → Privacy & Security → Accessibility. Each Mac grants its own permission.
6. HyperMac runs in the menu bar. Open Settings from its menu-bar icon, or open HyperMac from Applications again.

Do not disable Gatekeeper globally. “Cannot verify the developer” and “app is damaged” are different errors; report the exact message, release filename, Mac model and macOS version if installation still fails.

## Build the shareable DMG

```sh
bash scripts/build.sh
bash scripts/package-dmg.sh
```

The output includes an Apple Silicon preview DMG and a SHA-256 checksum. Verify a download with `shasum -a 256 -c <filename>.sha256` from the download folder. The GitHub **Apple Silicon preview DMG** workflow builds/tests the same package; its optional publication step is restricted to `main` and creates a prerelease.

All builds are ad-hoc signed. An update can require the recipient to refresh the app's Accessibility entry.

## Publish a Homebrew update

After the **Apple Silicon preview DMG** workflow publishes a release, update `Casks/hypermac.rb` in `c0dewars/homebrew-tap`: set `version` to `<app version>,<release tag>` and `sha256` to the value in the release's `.sha256` file. Run `brew audit --cask c0dewars/tap/hypermac` and `brew install --cask c0dewars/tap/hypermac` before pushing.

A paid Apple Developer Program membership is needed for the normal Developer ID signing/notarization route that avoids this unidentified-developer exception. It is optional for the chosen distribution path. See [Apple's Developer ID documentation](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

## Release quality

Signing status and application stability are separate. The 0.7.0 scrolling implementation remains experimental and has not passed the requested visual acceptance. No clean second-Mac install has been verified for this build. See [release readiness](../RELEASE-READINESS.md).
