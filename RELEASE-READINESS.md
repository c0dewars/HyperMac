# Release readiness — 3 October 2026

**Decision: NO-GO for general production distribution.** Version 0.6.0 remains a development preview.

## Confirmed blockers

1. The installed build has only a local self-signed code-signing identity. `spctl --assess --type execute /Applications/HyperMac.app` rejects it. No Developer ID identity is available. Public distribution needs Developer ID signing, secure timestamping, Apple notarization, a stapled ticket, and clean-Mac Gatekeeper validation. Do not distribute or export the local private key.
2. The installed binary is arm64 only. The new universal build successfully compiled arm64 + x86_64 and passed strict ad-hoc signature verification; architecture compilation is not proof of runtime compatibility.
3. No clean-machine install, upgrade, first-run Accessibility flow or clean uninstall has been validated. The local installer requires a certificate pinned on the destination Mac. It is a developer installer, not an end-user distribution installer.
4. Physical docking/undocking, sleep/wake, Spaces/fullscreen, native mouse resizing and the latest redo behavior remain incompletely validated. The computer-use transport failed during 0.6.0 testing. See TEST-RESULTS.md for exact coverage.
5. No long-running performance/energy test or full supported-macOS matrix. Declared deployment target is macOS 14; a single development Mac running macOS 26.6.2 is insufficient evidence for that whole range. An existing Swift concurrency warning remains.

## Other-Mac installation today

For a consenting developer/tester: obtain source, install Xcode Command Line Tools, run `bash scripts/setup-local-signing.sh` once on that Mac, then `bash scripts/build.sh`. Grant Accessibility to that installed copy. The default now builds the host architecture. This creates a different local identity on each Mac; it is not a consumer-ready signed release.

`bash scripts/build.sh --universal --build-only --ad-hoc` creates a universal test bundle. The normal installer intentionally refuses ad-hoc bundles. It does not replace the installed local signed app.

## Release gates

At source commit `0586ca1`, [PR #1 CI](https://github.com/c0dewars/HyperMac/actions/runs/37139980822) passed on both `macos-15` (Apple Silicon) and `macos-15-intel`: 15 XCTest tests, standalone lifecycle/geometry regressions, native release builds and bundle verification. The initial CI compiler timeout was fixed by splitting diagnostic report construction into explicitly typed steps. A clean local universal build also passed. These automated checks do not exercise the native window-management permission and UI flows on a clean Mac.

- Green XCTest and standalone regression CI on Intel and Apple Silicon.
- Native integration tests on minimum-supported and current macOS versions, both CPU families, and single/multiple displays.
- Verify open/close/minimize/restore, native drag, recorder cancellation/hotkey restoration, redo after closing a window, profile selection and docking races.
- Developer ID-signed, timestamped, notarized/stapled package; clean-Mac install/upgrade/uninstall with Gatekeeper enabled.
- Document permissions, configuration privacy, known constraints and an explicit supported-version policy.

## Repository controls

Policy templates in `.github/policies` mirror Wardogs_calculator's two main-branch rulesets: mandatory PRs without bypass, no deletion or force pushes, and owner-controlled updates with owner bypass only through PRs. HyperMac additionally requires both architecture CI jobs. CODEOWNERS names @c0dewars. GitHub plan support and server-side enforcement must be verified separately; files alone do not enforce policies.

## Policy enforcement limitation observed

GitHub returned HTTP 403 for ruleset creation on the private repository: GitHub Pro or public visibility is required. The owner chose to keep HyperMac private and upgrade GitHub. The policy templates are prepared but are not enforced. After the upgrade, apply both templates with `gh api --method POST repos/c0dewars/HyperMac/rulesets --input <template-path>` and verify the returned active rulesets before relying on branch restrictions.
