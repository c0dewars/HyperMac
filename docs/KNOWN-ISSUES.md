# Remaining fixes and acceptance checks

Status: **0.7.0 build 28 test prerelease, 8 October 2026**. This list separates reproduced failures from checks that have not yet passed. The preview is intended for testing on another Mac, not a stable-production claim.

| Priority | Status | Work remaining | Acceptance criterion |
| --- | --- | --- | --- |
| P1 | Reproduced limitation | Horizontal motion on displays beside one another uses instant navigation. The live-window backend cannot clip a window at a shared display edge; parked windows can appear from the wrong side or overlap at the edge. | Consistent directional behavior without visible overlap on laptop-only and laptop + Odyssey, or an explicitly limited interaction that users accept. |
| P1 | Reproduced failure | Partly off-screen Firefox/Ghostty columns can shrink to the visible screen edge. The seven-app Odyssey test requested 2,490-point widths but received 1,303, leaving 5/7 placements verified and taking about 1.2 seconds. Review sizing order and correction limits. | Seven apps maintain requested widths/groups through both navigation directions, without repeated corrections or long stalls. |
| P1 | Acceptance incomplete | Rapid physical Hyper+H/L and Hyper+wheel/trackpad need hardware testing. Model tests pass, but editor buttons do not prove shortcut delivery, momentum handling or one step per gesture. | Rapid/reversed inputs, focus while typing, focused-app closure and reopen keep navigation responsive and the correct screen active. |
| P1 | Untested distribution path | Clean installation and upgrade on a second Apple Silicon Mac, including Gatekeeper's per-app Open Anyway flow and Accessibility grant. | Downloaded DMG opens, installs, launches from Applications and tiles after permission; upgrade preserves settings. Test macOS 14+ versions separately. |
| P2 | Inconclusive live test | Native mouse resizing needs a reliable manual check. Automated edge drags did not change the observed test window. | Resizing a normal tile updates its neighbors; horizontal widths/groups remain usable and persist after reflow. |
| P2 | Coverage incomplete | Spaces/fullscreen, docking, sleep/wake, dialogs/minimum sizes, undo/redo across display changes and sustained CPU/energy use. | Complete a recorded compatibility matrix with no lost windows, persistent overlays or idle correction loops. |
| P2 | Observed tooling/config limitation | An external in-place edit to config.json was not noticed by the directory watcher; atomic replacement or Settings → Reload worked. | Both supported external save styles reload validated settings, or document and enforce one supported style. |

The screen-assignment bug is **fixed in build 28**: Preview and Apply share destination matching; live testing moved four matching apps to Odyssey with 4/4 verified positions and subsequent navigation remained on that screen. This does not resolve animation or sizing failures above.

Blur Off/intensity, focused-window borders, app removal, column grouping/width controls, autosave and the redesigned shortcut editor are implemented. Prior checks cover these controls; overlay quality during every transition and all apps is not certified.

The DMG is intentionally **ad-hoc signed and not notarized**, following the no-paid-Apple-account distribution choice. The developer warning is expected, not a crash fix awaiting implementation. Use the per-app instructions in [Distribution](DISTRIBUTION.md).

Evidence: [seven-app live validation](VALIDATION-2026-10-08.md), [test history](../TEST-RESULTS.md), [upstream design review](SCROLLING-DESIGN-REVIEW.md), and [release readiness](../RELEASE-READINESS.md).
