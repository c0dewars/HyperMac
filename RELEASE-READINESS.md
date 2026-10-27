# Release readiness

**0.8.0 build 34 is a downloadable test prerelease, not a certified production release.** Horizontal scrolling has been removed. Normal per-display tiling is the supported direction.

The release build and standalone geometry, lifecycle, migration and shortcut suites pass locally. These include five-display arrangements, negative coordinates, portrait/ultrawide geometry, app minimums, local-first app matching and missing-display handling. Settings UI checks cover native navigation, padding click targets, creation, duplication, removal, diagram dragging/resizing and autosave.

Before calling this stable:

1. Resume the paused live window tests and verify open/close/minimize/restore, keyboard commands and native mouse resizing.
2. Repeat preview/apply on laptop + Odyssey and other physical display arrangements, including docking and sleep/wake.
3. Pass arm64 CI and XCTest on the final commit; verify the packaged DMG and install/upgrade it on a second Mac.
4. Record supported app/macOS combinations and sustained idle/active resource use.

See [remaining acceptance checks](docs/KNOWN-ISSUES.md) and [test evidence](TEST-RESULTS.md). [The 0.8.0 prerelease](https://github.com/c0dewars/HyperMac/releases/tag/preview-0.8.0-8538581) provides the normal-only Apple Silicon DMG and SHA-256 checksum. GitHub Actions builds the package from merged commit `8538581` after tests and packaging verification. Earlier prereleases retain the removed scrolling implementation.

## Distribution

The user chose distribution without a paid Apple Developer account. Preview DMGs are ad-hoc signed and unnotarized. Gatekeeper's per-app Open Anyway flow and Accessibility permission are expected. Do not disable global macOS security protections. The Homebrew cask in `c0dewars/homebrew-tap` installs the same DMG. See [Distribution](docs/DISTRIBUTION.md).
