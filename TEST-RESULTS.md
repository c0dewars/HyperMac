# HyperMac 0.3.0 verification — 3 October 2026

Tested the installed `/Applications/HyperMac.app` on the built-in Retina display (1800 × 1130 usable logical points). Refreshed Accessibility permission with user approval and authentication, then restarted the app. No rebuild was installed after granting permission.

## Verified

- Accessibility is granted according to the running app's diagnostic report.
- Adaptive grid: Finder, Ghostty and ChatGPT/Codex all matched requested positions and sizes (3/3).
- Equal columns: all three windows matched 588 × 1118 requested frames (3/3).
- Pause button enters paused mode; Tile now resumes automatic tiling.
- User visually confirmed light-green borders on Ghostty and ChatGPT/Codex. Direct UI inspection of those apps was unavailable due to computer-use restrictions.
- System Settings is present in Floating apps and omitted from placement requests.
- Shortcut search filters the list. A duplicate keybinding is rejected without saving; Reload active settings restores the original binding.
- Applications pickers and app-name/icon updates were verified during the preceding 0.3.0 UI check.
- Installed binary matched the built artifact and passed strict signature verification at the start of testing.
- Standalone Swift checks passed: configuration migration/validation, shortcut presets, directional navigation, resizing, and 240 tiling scenarios covering all algorithms, 1–20 windows, ultrawide/portrait dimensions and negative origins.

## Limitations and outstanding checks

- Main window + stack: 2/3 verified. ChatGPT/Codex accepted the requested location and width but constrained height to 600 points instead of 553. This is reported as a size constraint by HyperMac.
- Synthetic global shortcut presses did not establish that Carbon hotkeys fired. Physical keyboard/Karabiner verification remains outstanding.
- `swift test` cannot execute here: `no such module 'XCTest'` with the installed Command Line Tools. Full Xcode is required for the XCTest suite.
- Multi-monitor hardware transitions, sleep/wake, native Spaces/fullscreen transitions, and performance profiling have not been verified in this session.

## Final state

Adaptive grid restored and active, 3/3 positions verified, light-green borders enabled, System Settings ignored. Temporary draft edits were discarded and existing shortcuts/layouts preserved.

## Layout feature tests and 0.3.1 repair

- Captured the three existing windows into a temporary layout; capture paused automatic tiling and disabled extra gaps. Saving and applying verified 3/3 positions.
- Removed Finder from the temporary layout, set Ghostty to left half and ChatGPT/Codex to right half, enabled gaps and renamed the layout. Saved JSON matched the edited geometry; application verified 2/2 positions.
- Targeted an unavailable `external-2`: application skipped that placement and verified 1/1 remaining target. Enabling fallback to primary verified 2/2 targets.
- Created an empty layout and confirmed saving was rejected. App-library search and adding Ghostty worked; its full-screen-area preset verified 1/1 position.
- Deleting the selected last layout crashed 0.3.0. The crash report identified an out-of-range array read in the inspector's name binding. Version 0.3.1 uses guarded bindings for outgoing layout/placement inspectors and updates selection before removal.
- Installed 0.3.1 and reproduced the deletion sequence with the advanced inspector open: no crash. Consecutive removal of both temporary layouts succeeded. Saved configuration was compared with the pre-test backup and was exactly equal.
- Canvas drag/corner-resize gestures were not confirmed through automation; cross-monitor dragging requires additional hardware. Placement presets and saved geometry were verified separately.
- Refreshed Accessibility for 0.3.1 after user authentication; System Settings shows HyperMac enabled, and the app was restarted. Final runtime placement verification awaits opening Settings & capture because automation cannot reach the menu-bar item.

## Automatic reflow repair — 0.3.2

- Added a one-second automatic reconciliation fallback for missed window events. It compares visible window identities and frames and avoids geometry writes when unchanged; paused/saved-layout modes do not poll.
- Added constrained tiling that keeps the requested algorithm where possible, otherwise redistributes columns/rows to accommodate minimum sizes observed after AX placement. Impossible arrangements produce a space constraint message.
- Added app reopen handling so launching HyperMac again exposes Settings & capture.
- Standalone regression checks passed for 1→4→1 window-count transitions with minimum sizes across all three algorithms, no overlaps, display bounds and impossible-fit detection. Existing 240 geometry scenarios and shortcut/configuration checks passed.
- Release build and strict ad-hoc signature verification passed; 0.3.2 installed. The existing Swift Sendable warning remains. User configuration matches the pre-layout-test backup exactly, including automatic tiling enabled.
- Refreshed Accessibility and restarted 0.3.2. Live reports verified 3/3 initial windows, 5/5 after additional Finder/Monosnap windows appeared, and 3/3 then 2/2 as windows closed, without Tile now. The four-window intermediate report showed a Finder constraint before subsequent reflow; isolated timing was not established because other windows changed during testing.

## Border occlusion repair — 0.3.3

- User screenshot confirmed borders crossed foreground HyperMac settings because panels used orderFrontRegardless.
- Borders now use the owning WindowServer ID for relative ordering and subtract the regions covered by windows above their owner from the stroke. Overlapping occluders are subtracted individually to prevent accidental exposed intersections.
- A 300 ms window-stack signature check catches ordering/movement of floating and ignored windows; unchanged stacks avoid AX refresh. Border panels are excluded from the signature/occlusion set.
- Release build and signature verification passed. Installed 0.3.3, refreshed Accessibility after completed user authentication, and restarted. Runtime status reports automatic tiling with 3/3 positions verified. HyperMac settings screenshot shows no crossing green lines with borders enabled; whole-desktop occlusion across other apps remains user-visible verification.


## Complete exterior borders — 0.3.4

- Replaced rectangle-based foreground clipping after the user reported partial outlines in 0.3.3. Transparent foreground surfaces can have bounding rectangles much larger than their opaque content.
- Borders now use fresh WindowServer bounds, expand the panel by stroke width plus antialias padding, draw all four edges outside the owner, and order below the owner. Native stacking handles overlap.
- Independent AppKit implementation; reviewed JankyBorders' exterior geometry/relative ordering design without importing its code or requiring a separate installation.
- Standalone checks passed for all four exterior edges, widths 1/3/6/12, padding and negative display coordinates, plus the existing tiling/shortcut regressions. Native visual verification remains pending installation/access refresh; per-window screenshots alone cannot establish whole-desktop stacking correctness.


## BSP tiling — 0.4.0

- Added session-local per-display split trees, largest-region insertion, sibling promotion after removal, and tree-preserving keyboard swap/split resizing in automatic BSP mode.
- Dynamic splits (BSP) is selectable in General; previous algorithms remain available. New configurations default to BSP. Existing user data is preserved.
- Independent native implementation informed by yabai documentation. Persistent per-Space trees, mouse split editing and cross-display swaps are not implemented; maximize retains its previous pause behavior.
- Standalone checks passed: insert/remove restores the original pair, unchanged branch survives insertion, swap and resize persist, discovery order does not reorder leaves, 39 grow/shrink transitions, config round-trip, 320 generic tiling scenarios, minimum-size checks and exterior-border geometry.
- Installed 0.4.0 and refreshed Accessibility using the already-authorized grant; restarted successfully. General shows Dynamic splits (BSP). Live native open/close test passed without Tile now: 4/4 initial windows → 5/5 after opening a temporary Finder window → 4/4 after closing it. Only algorithm changed in the user configuration; all other settings were preserved. Keyboard split operations are core-tested; physical Hyper shortcut delivery remains unverified. Whole-desktop exterior-border appearance awaits user confirmation. Full XCTest remains unavailable with this Command Line Tools setup.


## Settings design — 0.4.1

- Replaced titlebar-integrated TabView with explicit content navigation, compact brand header and fixed footer, addressing the user screenshot's clipped logo/header.
- Layout toolbar now has two rows; app library is a separate panel; canvas/inspector scroll together and advanced controls remain reachable. Increased monitor-label clearance and friendly Safari/Terminal fallback names.
- Added unsaved-change feedback, disabled Save when unchanged, and expandable runtime details; moved configuration/diagnostics utilities to More.
- Release build and strict signature verification passed. Installed and visually inspected Layouts and Shortcuts at the current 820-point-wide window. Header/navigation and footer remain visible; selected ChatGPT inspector is reachable by scrolling. Changing a layout name showed Unsaved changes and enabled Save; Reload restored Office without persisting the test edit.
- Refreshed Accessibility after user authentication and restarted 0.4.1. Final runtime status: automatic BSP, 4/4 positions verified. Left the Layouts view open. No tiling-engine code changed in this UI release.

## Persistent local signing — 0.4.2 → 0.4.3

- Created a reusable local code-signing identity in the login Keychain, trusted only for code signing, with its public fingerprint pinned outside the repository. User approved codesign Keychain access. Temporary private-key material was removed by the setup script.
- Release builds and strict signature verification passed. Signing continuity check changed bundle contents, confirmed a different CDHash with the same certificate-based designated requirement, accepted the certificate-signed update, and rejected an ad-hoc replacement.
- Installer rejected the initial identity change without the explicit migration flag. Installed 0.4.2 using that flag and refreshed only HyperMac's existing Accessibility entry. Runtime reported automatic BSP with 4/4 positions verified.
- Built and installed 0.4.3 using the ordinary installer, without another Accessibility refresh or authentication. Reopened Settings: version 0.4.3, automatic BSP, 4 windows, 4/4 positions verified. This verifies permission retention for an actual signed update on this Mac.
- Shell syntax checks pass. CI explicitly uses ad-hoc build-only output because it has no local signing key; that output cannot be installed by the normal installer. CI itself and XCTest were not run here. No tiling or border code changed in this signing release.
- This is local signing, not Developer ID signing or notarization. Retention depends on keeping the signing identity and installation location consistent; the check does not guarantee every future macOS permission decision.

## Lifecycle validation and transitions — 0.4.4 / 0.4.5

- On 0.4.3, reproduced a Finder failure after closing the sixth window: requested full-height expansion, actual half-height frame with displaced origin. Fixed redundant pre-resizing and delayed origin correction until after AXSize settles. Added up to three fallback passes for unchanged failed placements instead of treating them as settled.
- 0.4.4 live open/close sequence: 5 → 6 → 5, all positions verified. Installed certificate identity retained Accessibility without another grant.
- 0.4.5 adds configurable 180 ms cubic ease-out transitions, honors Reduce Motion, tracks existing border geometry at up to 60 Hz during placement, and suppresses repeat animation for unchanged verification targets. Actual frame delivery depends on AX client responsiveness; compositor-equivalent smoothness is not established by these checks.
- 0.4.5 live sequence: baseline 5/5 → open temporary Finder 6/6 → minimize 5/5 → restore 6/6 → close 5/5. Final diagnostic report had no issues, no rectangle overlaps, and maximum one-point difference between requested and actual coordinates. Temporary Finder window was closed; user's existing Applications and Downloads windows retained.
- Calculator was tested on 0.4.3: correctly omitted because AX reports non-resizable; it was quit afterward. System Settings stays excluded. Initial checks while the user was changing windows were not treated as isolated lifecycle evidence.
- Office on 0.4.3 applied 2/2 connected-display placements; Safari and Terminal targeting external-1 were explicitly skipped with fallback off. Saved layout rules are fixed placements, not automatic gap-filling.
- Standalone checks pass for monotonic easing/exact endpoints/no overshoot, duration validation, configuration round-trip, 39 BSP growth/removal transitions, minimum sizes, 320 tiling scenarios, border geometry and shortcut presets. Release build and certificate verification pass; existing Sendable warning remains.
- Not fully validated: perceptual animation quality across the whole desktop, native fullscreen/Spaces, monitor hotplug, sleep/wake, app-specific modal dialogs, physical hotkeys and long-running performance. Full XCTest remains unavailable with Command Line Tools alone.
- Office was rechecked on installed 0.4.5: 2/2 positions verified. Returned to automatic BSP afterward; user layouts and shortcuts retained, animationDuration saved as 0.18 seconds.

## Combined layout tools — 0.5.0

- Added backward-compatible opt-in adaptive saved layouts, redistributing matching visible windows per display, with learned minimum-size support and a one-second fallback for missed events. Minimized windows remain minimized; unrelated apps are not included.
- Added explicit missing-display text, a one-click primary-display assignment and a connected-display menu. Live test reassigned Safari in the Office draft: warning disappeared and rectangle appeared on the connected monitor. Reload discarded that test edit.
- Added a read-only current-window preview before settings-editor application, including skipped-display/window warnings. Visually inspected the preview sheet. Office preview showed two windows and both unavailable external placements; applying reported 2/2 positions verified.
- Added one-level session undo: captures visible window frames before layout application, restores surviving windows and pauses tiling. Live Office undo restored 5/5 positions. Temporary adaptive layout undo also restored 5/5. Undo does not restore app lifecycle or minimized/hidden state; no claim of full workspace restoration.
- Captured a temporary five-window layout, enabled Adaptive and gaps, previewed and applied: 5/5 verified. Minimizing Finder reflowed to 4/4; restoring reflowed to 5/5. Temporary layout deleted and saved. Full configuration comparison confirms all pre-test settings and layout rules preserved, except newly serialized adaptive=false defaults. Returned to automatic BSP.
- Standalone regression suite passed adaptive 2→1→2→0→1 transitions, fixed-mode empty-slot preservation, unavailable-display skip/fallback, duplicate-rule handling and impossible-fit detection, plus all prior animation/BSP/geometry/configuration checks. Live close/reopen with title-matched adaptive rules was not separately verified; pure-planner membership transitions were tested.
- Release build, local signature and retained Accessibility passed. XCTest and physical multi-display transitions remain unverified; existing Accessibility Sendable warning remains.

## Workspace controls — 0.6.0

- Added one-level redo of arrangement geometry, independent layout duplication, shortcut recording, exact-display monitor profiles, and native edge/corner resizing of automatic BSP splits.
- Release build and strict certificate verification passed. Installed app initially reported automatic BSP with 5/5 positions verified and retained Accessibility.
- Live recorder test: Control–Option–Command–Y populated key y and the three expected modifiers; Escape cancelled subsequent recording. Reload discarded the temporary binding. Live duplication created Office copy with its copied placements.
- Computer-use transport then failed with “Sky Computer Use native pipe closed before response”, including after session reset. No new HyperMac crash report was present. Consequently live redo, monitor-profile UI/docking, and native mouse drag tests were not completed. These are limitations, not passing integration checks.
- Standalone checks passed mouse split/neighbor geometry, exact unordered monitor matching and disabled profiles, profile encoding/decoding, duplicate enabled topology rejection, missing-layout rejection, and all earlier tiling/animation/configuration checks.
- Saved configuration compared byte-for-byte with the pre-test backup and was unchanged. Restarted the signed installed app to discard any remaining unsaved test duplicate; process confirmed running. No monitor profiles were automatically added. Final runtime placement status after restart could not be read because the UI transport remained unavailable.
- Mouse support currently applies to native edge/corner resizing in automatic BSP mode, adjusting neighbors on release. It is not modifier-drag-anywhere. Undo/redo stores one in-memory geometry step and keeps tiling paused after restoration. Physical docking, non-US keyboard legends and app-specific native resize behavior still require live validation.
