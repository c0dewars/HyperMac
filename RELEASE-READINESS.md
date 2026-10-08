# Release readiness — 8 October 2026

**Decision: publish a test prerelease; hold the stable release.** HyperMac 0.7.0 build 28 includes the screen-first editor and corrected display assignments. The owner explicitly authorized pushing the current source, GIF and README and sharing a DMG for another Mac. This supersedes the earlier conditional hold on pushing; it does not resolve the stability blockers. The actionable backlog is in [remaining fixes](docs/KNOWN-ISSUES.md).

The latest [seven-app test on both displays](docs/VALIDATION-2026-10-08.md) reproduced an Odyssey sizing failure: Firefox/Ghostty requested at 2,490 points wide reported 1,303, leaving 5/7 verified after roughly 1.2 seconds. A later navigation took 703 ms. Screen isolation and tested lifecycle cases passed, but continuous transitions remain disabled on this topology. These are measured release blockers, not only pending visual feedback.

## Release blockers

1. **Scrolling visual acceptance failed.** The user still sees wrong-side arrivals and inconsistent motion with the laptop and Odyssey connected beside one another. The current live-window backend parks overflow on a free outer edge and switches instantly when another display blocks an edge. It cannot provide the requested clipped horizontal viewport on this topology. [Upstream design review](docs/SCROLLING-DESIGN-REVIEW.md).
2. **Real-input acceptance is incomplete.** Build 26 fixes repeated gesture steps and defers focus until after placement. Regression tests pass, and installed editor navigation verified eight window positions and destination focus, but real trackpad/mouse momentum and rapid physical Hyper+H/L still need acceptance. Geometry verification alone is not visual proof.
3. **Compatibility validation is incomplete.** macOS 14+ and Apple Silicon are declared requirements; only the development Mac on macOS 26.6.2 has been exercised locally. A clean second-Mac install, upgrade, first-run Accessibility grant and uninstall have not been validated for this build. Intel support is intentionally removed.
4. **Lifecycle coverage remains partial.** Native Spaces/fullscreen, sleep/wake, sustained performance/energy, and app-specific resize/modal behavior require more testing. Some earlier docking and lifecycle tests passed; see the dated evidence in TEST-RESULTS.md rather than assuming full coverage.
5. **Final-commit CI must pass before publishing the test DMG.** Both standalone core suites and an arm64 release build pass locally. Full XCTest requires full Xcode, unavailable in the local CLT-only setup. CI runs XCTest, both standalone suites, build verification and DMG packaging. The prerelease notes link its exact build result.

## Chosen distribution path

The owner chose not to purchase Apple Developer membership. Use an **ad-hoc-signed DMG**, with Apple's per-app **Open Anyway** instructions and Accessibility setup. This route can be shared without a paid account; it does not imply application stability or notarization. [Installation and sharing guide](docs/DISTRIBUTION.md).

The packaging script re-signs a temporary copy ad hoc, preserving the development bundle's pinned local certificate. It includes Applications and a first-launch READ ME, verifies the DMG, and writes a SHA-256 checksum. No local private key is included. The installed copy continues using its existing certificate to preserve Accessibility permission.

An unidentified-developer warning is expected on downloaded previews. It is separate from a crash or unsupported architecture. Developer ID/notarization would remove the need for that exception, but is not required by the chosen no-cost release policy.

## Checks needed before a stable tag

- Resolve or explicitly narrow the scrolling behavior promised to users; pass visual and physical-input acceptance.
- Green arm64 CI, XCTest, lifecycle/scrolling suites, strict bundle verification and DMG verification on the final commit.
- Test clean install/update on another Apple Silicon Mac, including the documented per-app Gatekeeper exception and first Accessibility grant.
- Exercise one and two screens, open/close/minimize/restore, focused-window closure, native resize/grouping, undo/redo, quit recovery, docking and Spaces.
- Record a meaningful sustained performance run; ensure no repeated correction loops on idle windows.

## GitHub status

Read-only CLI check on 8 October 2026: the rulesets API still returns HTTP 403 with “Upgrade to GitHub Pro or make this repository public.” Existing policy templates and CODEOWNERS are not proof of server-side enforcement. The owner's instruction to keep the repository private remains in force.

The 0.7.0 test prerelease is built from the `codex/horizontal-scroll` branch. Its release notes identify the exact commit and checks. Main remains separate for pull-request review; publication does not certify stable-release readiness.
