# Normal layouts — 0.8.0 build 34 (8 October 2026)

- Horizontal runtime/UI, column actions and shipped preset removed. Legacy configurations migrate to ordinary per-display tiling; actual user data round-tripped with all four named layouts and 30 customized shortcuts retained.
- Apple Silicon optimized build passed locally with Command Line Tools.
- `scripts/check-layouts.swift`: 464 geometry/lifecycle/topology scenarios (one to five displays, up to 70 synthetic windows); local-first assignments for same-app windows; explicit cross-screen transfer; disconnected/fallback behavior; physical-ID precedence; arbitrary external-N roles; per-screen exclusions; new-display defaults; impossible fits; rotation and migration checks passed.
- `scripts/check-shortcuts.swift`: passed shortcut persistence/directions, default/legacy config, adaptive lifecycle reflow, fixed slots, constrained sizes, monitor profiles, blur configuration, mouse split geometry, 39 BSP insertion/removal transitions, 320 algorithm/display/window-count scenarios and border geometry.
- Native settings UI: button-padding activation, toolbar navigation, app rules, diagram resize/move, duplicate/delete, recorder cancellation and autosave checked. A hosting-related default-size regression was found and corrected. Test-created layouts removed.
- Final installed bundle: `/Applications/HyperMac.app`, 0.8.0 (34), ad-hoc signature verified; Accessibility refreshed and read-only preview detected four open laptop windows. Confirmed Command-W closes Settings and Command-comma reopens it. In-place and atomic config reloads both reached the active model. All original app rules, four layout names, 30 shortcuts and appearance preferences were compared with the pre-test backup; startup preference restored. HyperMac was left closed to preserve the live-test pause.
- Existing live-window testing remains paused. No 100% claim for real apps or future hardware; multi-monitor docking, actual mouse resize, shortcuts under load, overlays and second-Mac distribution still need acceptance. Full XCTest requires Xcode; the standalone suites run with Command Line Tools. No release was published during validation. The follow-up source/media update is prepared on `codex/normal-layouts-ui`.

Earlier history below describes the removed scrolling feature and previous builds.

---

## Follow-up fixes — 8 October 2026

Installed and visually checked Layout 4: both Odyssey G95C and built-in display diagrams are visible even with no template apps. General shows focus-only borders enabled by default and optional experimental blur disabled. Existing user layouts were preserved.

Release build, standalone scrolling regression checks and existing shortcut/tiling checks pass. New geometry coverage includes full-width stacked windows despite stale template monitor selectors, app-wide width fallback, lower-third drop grouping and same-column ordering. Scrolling uses its own 220 ms default; translation-only animation skips AX resize writes, and repeated navigation has a bounded queue.

Native drag-drop behavior, perceptual smoothness and blur appearance/occlusion still need live user acceptance; automated geometry tests do not establish these. The installed build includes native AppKit blur, focused-window border filtering and app-color overrides, but blur remains off by default.

# Horizontal scrolling preview — 8 October 2026

Local branch `codex/horizontal-scroll`, version 0.7.0. Built for arm64 with Command Line Tools and installed with the existing local signing identity.

- Live test: Odyssey G95C (5120 × 1440 logical points), built-in Retina display also connected. Four blank private Brave windows reported 4/4 placements verified. Closing one reported 3/3; opening a replacement reported 4/4. Closing all temporary windows reached 0/0 without leaving the regular Brave window in the strip.
- Removed the temporary layout and test bindings. Preserved existing settings and added configurable Hyper+H / Hyper+L focus navigation.
- Standalone scrolling checks passed: stable widths, insertion, removal, vertical groups, navigation and wrap, reordering, keyboard/mouse resize geometry, constraints, 1–100 windows, configuration round-trip, and safe multi-monitor overflow.
- Existing standalone shortcut/tiling checks passed, including 320 tiling scenarios. The example configuration matches the new default shortcut preset.
- Release build and strict signature verification passed. Full XCTest was not run locally because full Xcode is unavailable.
- Physical global shortcut activation, native grouped-window resizing, animation quality, Spaces/fullscreen, display reconnect, and undo/quit restoration remain live acceptance items. Synthetic app-targeted keys did not provide conclusive evidence of global shortcut activation. This is an experimental preview, not a production readiness claim.

See [scrolling controls and limitations](docs/SCROLLING.md).

---

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

## Horizontal scrolling follow-up — 0.7.0 development, 2026-10-08

- Release build, local signing, installation, and both standalone regression suites passed. Full XCTest was not run with the local Command Line Tools setup.
- Live checks verified Normal 3/3 placements, undo and redo 6/6, Horizontal 3/3, and a full-width two-app template group 3/3. Previous/next-column controls produced verified placements; these checks do not establish perceptual smoothness.
- User confirmed blur and focus-only borders both work. Added persisted 0–100% blur intensity; configuration round-trip and invalid-value checks pass. Installed UI responded to 100% → 95% → 100%; subsequent user-selected 80% was observed and preserved.
- Latest navigation changes retain intended focus while delayed Accessibility notifications settle and place parked windows directly rather than animating them across the viewport. Added a draggable column-width handle. Physical Hyper+H/L smoothness and native drag stacking remain acceptance checks, not established passes. Live minimize/restore attempts were inconclusive.
- UI checking was interrupted by concurrent user interaction. Current user layout edits were preserved. No commits or pushes were made.

### Direct horizontal monitor editing — 2026-10-08

- Removed the read-only hit-testing restriction from the horizontal monitor diagram. Diagram selection maps back to original placement indices, including grouped and interleaved rules.
- Added core template editing for column-wide resize, reorder, detach, and lower-third stacking. New regression assertions and both standalone suites passed; release build/sign/install passed.
- Verified in the installed UI: dragged Code out of its Brave group into a separate column, dragged it back below Brave (draft matched the original again), and resized the shared column from 33% to 50% with its diagram handle. Reload restored the saved 33% arrangement; Save changes was disabled afterward. No test edits were saved.

## Settings usability and scrolling overlap — 2026-10-08

- Settings now debounce valid edits for 400 ms and save automatically. Appearance-only changes and shortcut edits do not reset the tiling engine. Inactive layout edits do not reset the active scrolling session. Invalid configurations remain drafts with an error; external changes still require reload.
- Live UI and on-disk checks passed: blur Off persisted immediately; intensity 80% → 75% persisted without Save; restored 80%. Shortcut filtering and Escape cancellation worked. An intentionally duplicated Hyper+L was rejected without replacing the saved H/L bindings; Reload discarded that test draft.
- Redesigned shortcuts as compact searchable/filterable rows, with current key combinations as recorder buttons and expandable action editors. Layout target selection now uses saved layout names.
- Removed Brave from a temporary copy of Horizontal using the visible minus control. The app disappeared from placements and persisted in that layout's exclusions despite include-all being enabled. Deleted the test copy; original Normal/Horizontal layout contents and all shortcuts compared equal to the pre-test backup.
- Initial logical-strip interpolation and pre-animation activation still failed the user's visual acceptance: the user reported windows in front of each other and supplied a screenshot of Ghostty's parked edge covering partly visible Finder. This was not treated as a pass.
- Follow-up reserves parking margins and raises visible/partly visible neighbors above fully parked windows before/after navigation. Core checks now cover full-width tile separation from parked edges, partial-neighbor classification, coherent translation, app exclusions, and existing scrolling regressions. Updated expected full-width geometry to account for the reserved margins. Release build/sign/install passed. Whole-desktop visual acceptance of this final ordering correction remains pending.
- Blur was temporarily disabled to isolate overlap. No GitHub push or commit was made. Full XCTest and compositor-equivalent animation quality remain unverified.


## Repeated horizontal navigation — 0.7.0 build 22, 2026-10-08

- User reported continuing overlap and prolonged shuffling on later Hyper+H/L steps, especially Finder. The previous ordering correction did not pass visual acceptance.
- Captured diagnostics showed Codex's normal window omitted from discovery because its AX frame did not match the earlier WindowServer geometry. Added optional runtime-resolved window-number matching (and identity retention by number), preserving the public geometry fallback and on-screen visibility guard.
- Replaced the queued navigation FIFO with one replaceable pending intent. Superseded commands stop animation and correction retries; the next animation starts from the last emitted logical frame. Reconciliation now uses the same logical-strip interpolation, including after minimum-size corrections.
- Found staggered-monitor projection could park the top and bottom rows of a group on opposite edges. Both rows now use the full column's safe edge. Regression tests exercise 121 positions across the laptop/Odyssey topology, plus interrupted-animation reversal continuity.
- Live eight-window traversal retained columns `[Code | Teams | Brave | Codex | Firefox, Ghostty | Finder | TextEdit]`; all eight retained recent navigation reports verified every target, with 323–410 ms command time (including 220 ms animation), Finder 344 ms. No normal-window discovery omissions occurred in these reports. Rapid direction changes produced a stable verified result; requests superseded before geometry changes were coalesced.
- Saved the temporary diagnostic document to `/tmp/hypermac-navigation-qa.rtf` and closed the test-only TextEdit session. Final signed build 22 retested both strip directions with the remaining seven windows and reported 7/7 verified placements. The automated input tool did not establish delivery of physical Hyper key chords; the native Previous/Next controls exercise the same engine actions.
- Both standalone suites, final release build, strict signing verification and `git diff --check` passed. XCTest was not run under the local CLT-only setup. Existing Sendable warning remains. Whole-desktop perceptual acceptance is pending; stable final frames are not proof of compositor-quality motion, and parked edges remain a macOS limitation.
- Valid pending settings edits now flush on close; invalid edits keep the window open with the existing validation message. Layout selection survives switching settings tabs. Configuration equality check confirmed all original layouts, shortcuts and appearance settings preserved (allowing the backward-compatible empty per-layout exclusion field). Blur remains on at the user's 80% setting. No commit or push made.

## Independent scrolling displays — builds 23–25, 2026-10-08

- Added per-display Horizontal/Normal/Floating modes, local template matching/exclusions, separate widths/groups/order/focus, and configurable neighbor space. The editor's Previous/Next commands now explicitly target its selected display.
- Live build 25 test with a temporary All-displays layout: seven laptop windows and two disposable Finder windows on Odyssey reported 9/9 placements. Six external navigation commands verified 2/2 positions and keyboard focus, 81–192 ms. Closing the focused external Finder window produced 8/8, centered the survivor and left all seven laptop rectangles unchanged.
- Current side-by-side topology has blocked horizontal edges; these tests used instant placement, not continuous animation. The user subsequently reported wrong-side arrivals and missing animation on the laptop as well. This is failed visual acceptance, not overridden by geometry results.
- Pure tests cover per-screen app widths, groups, local indices/exclusions, mixed display modes, full-width margins and composed motion. Full XCTest remains unavailable locally.

## Gesture handling, focus timing and documentation — build 26, 2026-10-08

- Replaced the 180 ms repeated wheel trigger with a phased gesture gate: one step per gesture, no momentum-triggered steps, and a 250 ms quiet interval for unphased wheel bursts. Added regressions for long gestures, momentum, new/cancelled gestures, wheel bursts, malformed deltas and interrupted monotonic navigation with different widths/stacked rows.
- Removed pre-placement activation/raising of the destination. Focus transfer occurs after the strip moves, avoiding an app trying to reveal its parked window before animation. Delayed focus ownership logic remains in place.
- Audited Accessibility identity state confinement to its serial queue and declared that queue-backed class Sendable. The release build has no Swift source warnings; sandboxed SwiftPM cache warnings remain environmental.
- Both standalone suites passed, including 320 tiling scenarios and 39 BSP transitions. Arm64 release build, strict local certificate verification, installation, shell syntax, plist validation and diff whitespace checks passed.
- Installed navigation on the laptop with Odyssey connected: three Next commands and one Previous each verified 8/8 final positions and destination keyboard focus (107–179 ms). This used the editor controls and instant fallback; it does not establish physical Hyper delivery or smooth animation. Real wheel/trackpad acceptance remains pending.
- Live direct × removal from the temporary Horizontal copy removed Firefox's rule and showed the screen-specific exclusion/Add back control. No crash occurred. Recorder Escape cancellation preserved shortcuts.
- Removed the temporary copy and both remaining disposable Finder windows. Restored the original Horizontal preset, reporting 6/6 positions. Config comparison preserved Normal, all app placements, shortcuts and appearance settings. Horizontal retains the user's full-width fallback/100 ms preference and now has the explicitly requested 10-point neighbor space; new empty per-screen dictionaries are backward-compatible serialization fields.
- Captured eleven fresh app screenshots and regenerated the 14-slide/70-second GIF, poster and gallery. The images show UI features, not animation quality. No desktop documents or account pages were captured for repository media. The native computer-use transport failed after capture and still failed after reset; no further live-input tests were claimed.
- Reviewed Niri, Hyprland, PaperWM/GNOME and PaperWM.spoon source. Findings and revision links are in docs/SCROLLING-DESIGN-REVIEW.md. Native shared-edge projection remains an unresolved experience limitation; a language change alone cannot provide compositor clipping.
- No stable release, GitHub push, tag or commit: the user's conditional production gate has not passed. Free DMG instructions now document Apple's Open Anyway path rather than requiring paid notarization.
- Packaged the local Apple Silicon preview DMG with an ad-hoc-signed staging copy. Disk-image checksum verification passed and a SHA-256 file was generated. This validates packaging, not first launch on a clean Mac or smooth scrolling.

## Seven-app laptop and Odyssey validation — build 26, 2026-10-08

- Tested the same seven apps sequentially on the laptop and Odyssey with both displays connected. Laptop full traversal verified 7/7 and destination focus for all twelve navigation steps (119–203 ms).
- Reproduced an Odyssey failure: Firefox and Ghostty requested at x=5617, width=2490 each reported width=1303. Two settled reports remained 5/7, taking 1198/1216 ms. Later traversal verified all windows, but one navigation took 703 ms. Both screens use instant fallback, so smooth transitions fail the requested behavior.
- Firefox close/reopen/minimize/restore reflowed 7→6→7 correctly; navigation continued after close. Full-width separation and half-width regrouping verified final geometry.
- Nine-window isolation test passed: seven Odyssey app windows plus two laptop TextEdit windows; navigation on either display left every frame on the other unchanged.
- Physical Hyper+H/L, Hyper-scroll and native mouse resize remain unverified/inconclusive with the input automation. Whole-desktop animation/overlay acceptance was not established. Both standalone suites and installed signature verification passed.
- Removed all temporary windows/layouts. Original six frames restored exactly, original config restored byte for byte, and Automatic mode reports 6/6. No code/binary changes or GitHub push. Detailed pass/fail matrix: [validation report](docs/VALIDATION-2026-10-08.md).

## 2026-10-08 — screen-first Layouts editor (0.7.0 build 27)

- Release arm64 build and both standalone Swift validation suites passed. New regressions cover explicitly selecting an external display without primary fallback, independent screen mode edits, legacy rules/width preservation, disconnected display roles, persistence, and local fixed/adaptive matching.
- Installed with the existing local signing certificate; strict signature/identity checks passed and Accessibility remained available.
- Live UI checks used disposable copies: per-screen mode changes, full-width sizing, two-app grouping, removal/exclusion, app-rule transfer between screens, adding an app to the selected Odyssey, autosave, and deletion of the test layouts passed. Selecting screen cards alone preserved configuration.
- Verified the compact page at 820 logical points wide, including visible screen cards, sidebar app rows, column cards, expandable monitor diagram, and per-screen preview summary. Screenshot: `docs/media/screenshots/22-screen-first-layouts-070.png`.
- The full configuration matched the pre-test backup after cleanup. Normal, Horizontal, and Layout 3 were preserved. Layout 3 was re-applied and reported 6/6 verified placements.
- This is editor and screen-selection validation, not renewed animation acceptance. All six current windows were on the laptop; the Odyssey had no live scrolling windows. Preview now states that explicitly. Moving a saved app rule does not move its live window. Previous transition/release blockers remain open.


## 2026-10-08 — Preview/Apply screen assignment fix (0.7.0 build 28)

Build 27 changed the editor but incorrectly treated saved screen destinations as local sizing rules in mixed layouts. Build 28 resolves matching open windows to their saved displays before planning either the preview or the actual arrangement. This supersedes build 27's limitation that app rules cannot move live windows.

- Arm64 release build, stable local signing/strict verification, scrolling regression suite, shortcut/tiling suite, and whitespace checks passed.
- Added regressions with seven simulated apps starting on the laptop: five explicitly assigned to the Odyssey and two unlisted windows remain on the laptop. Covered same-app rules on two screens, nonzero window indices, title matching, duplicate rules, missing displays, exclusions, fixed/adaptive routing, and manual screen moves during normal reflow.
- Installed locally with Accessibility retained. With the user's current Layout 3 (laptop Leave unchanged; Odyssey Horizontal), preview showed four scrolling windows on Odyssey and none arranged on the laptop. Firefox and Helium had no matching open windows and were reported.
- Apply moved Brave, Codex, VS Code, and Ghostty from laptop coordinates to Odyssey coordinates. All four requested/actual frames matched, 4/4 verified. Finder and Teams were absent from the move list. The user's latest screen modes and app rules were preserved.
- Three Next-column steps and one Previous-column step remained on Odyssey with the same four members. Each reported 4/4 positions verified and keyboard focus=true (264, 129, 116, 113 ms). These were editor navigation controls, not physical shortcut injection.
- Live reports: `/tmp/hypermac-assignment-before.txt`, `/tmp/hypermac-assignment-applied.txt`, `/tmp/hypermac-assignment-navigation.txt`. Configuration backup: `/tmp/hypermac-before-screen-assignment-1791481652135794000.json`.
- Shared-edge instant navigation and previously documented animation issues remain; this change fixes display assignment, not compositor clipping or animation acceptance. Nothing was pushed or released to GitHub.

## 2026-10-08 — build 28 test-release preparation

- Rebuilt the Apple Silicon release and reran both standalone suites successfully, including screen assignment, gesture/focus models, scrolling geometry, 320 tiling scenarios and 39 BSP transitions. Plist, shell syntax and diff whitespace checks passed.
- Refreshed the feature GIF to 16 slides / 80 seconds with current screen-first Layouts, destination preview, Shortcuts and recorder captures. Visually reviewed the poster and gallery. The GIF remains a screenshot walkthrough, not a claim of smooth live motion.
- Added `docs/KNOWN-ISSUES.md` with reproduced failures and unverified acceptance checks. The owner's latest instruction authorizes pushing the branch and publishing a test DMG; the earlier stable-release hold still applies to production claims, not this test prerelease.
- GitHub CI and the preview packaging workflow validate the pushed source separately. Release notes identify their runs and exact source commit. No additional live animation acceptance is claimed by this documentation update.
- The first full-Xcode CI run caught an obsolete XCTest assumption that every directional binding's key equals its target. Hyper+H/L intentionally map letter keys to left/right. Updated the test to preserve both bindings while removing a launcher, assert the serialized shortcut list is unchanged, and check both letter mappings explicitly. No runtime code changed for this correction.

## 2026-10-08 — native application shortcuts (0.7.0 build 29)

- Added the native HyperMac application menu ahead of Edit, with Command-comma for Settings and Command-Q for Quit. The status menu displays the same bindings; global window shortcuts are unchanged.
- Arm64 release build, plist validation, diff whitespace and strict ad-hoc bundle verification passed. Installed build 29 at the user's request.
- Command-Q terminated the running process (confirmed absent with pgrep). Relaunched, closed Settings, sent Command-comma and observed a newly opened Settings window. Existing Edit commands remain in a separate menu.
- Installing the changed ad-hoc binary required refreshing its Accessibility identity, as documented for preview updates. This menu-only change does not resolve the horizontal-scrolling backlog.
- Refreshed only HyperMac's Accessibility entry after macOS authentication. The installed app resumed automatic tiling and verified 2/2 current window placements.

## 2026-10-08 — laptop scrolling transport (local builds 30–33)

Scope: the user selected sizing/correction, per-display movement ownership and off-screen presentation as the first three fixes, tested only on the built-in display. Live windows remain the chosen backend. No monitor arrangement or resolution changed.

- Added a per-display rendered-viewport revision. Destinations are committed only after transport; interrupted movement resumes from its last submitted logical frame, and stale completions cannot overwrite a newer transition.
- Horizontal transport negotiates size on-screen, accepts bounded native grid rounding for the requested slot, writes positions only during animation, and makes at most one final position correction. App minimums inferred in another arrangement are cleared on mode changes. Delayed own events do not restart an unchanged strip.
- Edge order follows logical column distance throughout animation and is restored after activation. Native positions now use whole points to address cumulative AppKit width growth observed with fractional AXPosition writes.
- Arm64 release compilation, standalone scrolling regressions and the shortcut/tiling suite passed. New cases cover seven mixed-width windows with a stack, both directions, interrupted retargeting, stale results, close recovery, both-edge order, safe size preparation, grid rounding and integral origins. The suites include the existing 320 tiling cases and 39 BSP transitions. Strict ad-hoc signature and plist verification passed. Full XCTest was not run locally with this Command Line Tools setup; these changes are not pushed to CI.
- Build 30's first seven-app attempt exposed an infeasible learned-size plan and misleading 0/0 status. The failure now says No windows arranged, with constraint details in diagnostics. Build 31 identified Terminal's accepted 832 × 1099 size for an 830 × 1106 slot; retaining that accepted size stopped repeated resizing.
- Build 32 exercised Brave, Firefox Developer Edition, Safari, Finder, TextEdit, Terminal and VS Code on the built-in 1800 × 1130-point usable area. Firefox/Safari shared a column; widths were 50%, 75% and 100%. Sequential editor navigation traversed both directions. The eight saved transitions all transferred keyboard focus and used zero size writes and zero position-correction passes. Five verified 7/7; three verified 6/7 as Finder/TextEdit widths drifted by 5–6 points. End-to-end times were 383–1042 ms, including discovery, a configured 220 ms animation and focus verification. This is not a smoothness or latency acceptance pass.
- Build 33 adds integral native origins to address that drift. It is installed in /Applications/HyperMac.app with Accessibility enabled. Its initial run verified the three remaining open test apps; four windows had closed before the full repeat. The user explicitly paused live testing before the seven-app rerun, rapid reversals, close/reopen and visual acceptance. Do not mark those checks passed.
- Computer use denied Ghostty, so Safari replaced its test slot. Helium exposed no usable window and its inspection stalled. Neither is claimed as visually validated here. No direct computer-use access to Codex was attempted.
- Temporary Laptop validation remains in the local configuration because testing was paused. Existing layouts were preserved. Fresh backup: /tmp/hypermac-before-laptop-validation.json. Local reports: /tmp/hypermac-build31-initial.txt, /tmp/hypermac-build32-navigation.txt and /tmp/hypermac-build33-initial.txt. Resume from build 33, then remove only the temporary layout and close only disposable test windows.
- **Stable release remains on hold.** No commit, push or release was made for these changes.

## 0.8.0 documentation refresh

- Replaced the old scrolling GIF with a nine-scene, 49.5-second walkthrough of actual build-34 settings captures, including normal per-display layouts, custom positions, app removal controls, preview, blur, shortcuts and recording. No live transition claim.
- The temporary Workspace demo layout was deleted; the saved configuration matches the pre-capture backup byte for byte. The recorder was cancelled without changing bindings. Tiling was paused for capture.
- Computer-use capture stopped when its helper service crashed while opening Displays; HyperMac had no corresponding crash report. No Displays capture is included.
