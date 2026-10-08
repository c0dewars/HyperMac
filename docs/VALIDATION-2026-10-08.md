> Historical reference: horizontal scrolling was removed in 0.8.0. This document describes the previous implementation.

# Live validation — 8 October 2026

**Result: not ready for a stable release.** Build 26 passes many final-placement and lifecycle checks, but smooth horizontal transitions on the connected laptop/Odyssey arrangement do not meet the requested behavior. A seven-app test also reproduced a native sizing failure.

## Setup

- Installed HyperMac 0.7.0, build 26; Accessibility granted; local signature verified.
- macOS 26.6.2 (25G83), Apple Silicon.
- Built-in display: usable `(0, 39, 1800, 1130)` points. Odyssey G95C: usable `(1800, -720, 5120, 1410)` points. Display arrangement/resolution were not changed.
- The same seven apps were tested first on the laptop, then on the Odyssey: Finder, ChatGPT/Codex, Brave, Teams, VS Code, Ghostty, and a temporary Firefox Developer Edition window. This was sequential seven-app coverage on each screen, not fourteen simultaneous app windows.
- A further isolation test kept seven app windows on Odyssey and two disposable TextEdit windows on the laptop: nine windows across both independent strips.
- The temporary Horizontal copy used all connected displays, centered focus, 10-point neighbor space, 100 ms configured duration, and no wrap. Laptop windows used full-width fallback. Odyssey used the existing mixed widths and the Firefox/Ghostty vertical group.

## Results

| Check | Result | Evidence and limits |
| --- | --- | --- |
| Automatic insertion of the seventh app | Pass | Automatic mode changed from 6/6 to 7/7 verified placements. |
| Laptop traversal | Pass for placement/focus | Six Next and six Previous commands traversed all seven apps. All twelve commands verified 7/7 rectangles and destination keyboard focus; 119–203 ms per command. These were editor controls. |
| Laptop end boundary | Pass | Previous at the first column did not wrap or create an extra navigation entry. |
| Smooth transitions on laptop and Odyssey | **Fail** | Both live previews/reports explicitly selected instant navigation because an adjacent display blocks a horizontal edge. A configured 100 ms duration does not enable animation on this topology. No continuous transition can be certified here. |
| Initial Odyssey horizontal placement | **Fail** | Two refreshed reports remained at 5/7. Firefox and Ghostty were requested at width 2,490 but reported width 1,303 at x=5,617. Total planning/placement time was 1,198 and 1,216 ms. |
| Odyssey traversal | Partial | A subsequent traversal reached every column and verified destination focus. Five Next commands reported 7/7; one took 703 ms while the others took 136–225 ms. One earlier leftward command was superseded after 591 ms. Later passes do not erase the initial failure. |
| Close focused temporary window | Pass for tested app | Closing Firefox without reactivating it during inspection produced 6/6. Ghostty filled the group height. Next/Previous still verified all six windows and keyboard focus (118/126 ms). |
| Reopen / minimize / restore | Pass for tested app | Firefox reopening produced 7/7, minimizing 6/6, and restoring 7/7. This does not establish equivalent behavior for every app. |
| Full-width and separate/group controls | Pass for final geometry | After Full width and Separate, Firefox and Ghostty each had independent 4,980 × 1,386-point rectangles. Regrouping at half width restored 2,490 × 687 rows and 7/7 verification. Intermediate autosave reports can be stale; settled reports were used. |
| Screen isolation | Pass | With nine windows, Odyssey navigation left both laptop frames exactly unchanged. Laptop navigation left all seven Odyssey frames exactly unchanged. Overall 9/9; commands verified 7/7 and 2/2 for their respective displays. |
| Duplicate / autosave / reload | Pass for tested workflow | Created Horizontal copy, edited only the copy, and observed persisted settings. Original Normal and Horizontal presets remained equal to the backup. |
| Physical Hyper+H/L | Unverified | An automated Hyper+L chord produced no navigation entry. Editor buttons exercised the engine but cannot establish Karabiner/global-hotkey delivery. |
| Rapid input interruption | Partial | A six-click burst coalesced; it did not establish that six physical key presses each advance exactly once. Pure interrupted-motion tests pass. |
| Hyper-wheel/trackpad | Unverified live | Pure tests pass gesture gating and momentum rejection. Hardware gesture phases/momentum were not delivered by the live automation. |
| Native mouse resize | Inconclusive | Two edge-drag attempts did not change the test window's recorded width. This cannot distinguish an automation/input limitation from a resize defect. |
| Border/blur visual quality | Previous evidence only | The owner previously confirmed blur and focus-only borders in this build series. This run did not capture whole-desktop overlays or certify every transition frame. |
| Spaces, fullscreen, docking, sleep/wake, modal dialogs, sustained CPU/energy, clean install | Not completed in this run | Remain release checks; do not infer passes from core tests. |

## Reproduced sizing failure

With ChatGPT/Codex centered on Odyssey, its next Firefox/Ghostty group is partly beyond the right edge:

```text
Firefox: requested x=5617 y=-708 w=2490 h=687
         actual    x=5617 y=-708 w=1303 h=687
Ghostty: requested x=5617 y=-9   w=2490 h=687
         actual    x=5617 y=-9   w=1303 h=687
```

The actual right edge is exactly the display boundary: `5617 + 1303 = 6920`. This is consistent with native sizing being constrained at that position; it does not prove which component applies the constraint. `Accessibility.move` currently writes the destination position before requesting the expanded size, then retries up to four times. Review size negotiation at partially off-screen destinations and the correction budget before claiming fluid navigation.

The topology fallback is separate: live windows parked on the opposite safe edge cannot provide a clipped, consistently directed strip on a shared edge. See [the upstream implementation review](SCROLLING-DESIGN-REVIEW.md).

## Automated checks

Both standalone Swift suites were rebuilt and passed during this run. Coverage includes 320 tiling geometry scenarios, 39 BSP lifecycle transitions, scrolling with 1–100 windows, multi-display membership and widths, groups, minimum-size constraints, delayed focus, closure recovery, interruption geometry, gesture gating/momentum, shortcuts, configuration round trips, and monitor profiles. These test core models, not real app rendering.

Installed strict code-signature verification passed with the local trust store. Full XCTest was not rerun: the selected toolchain is Command Line Tools, without full Xcode. No source/binary changes were made during this validation.

## Cleanup and evidence

- Closed the temporary Firefox and both blank TextEdit windows; all six original windows remain.
- Restored all six original window rectangles exactly (largest coordinate difference: zero), then returned to Automatic mode, reporting 6/6.
- Removed Horizontal copy, QA Odyssey transfer and QA Restore baseline. The final config matches `/tmp/hypermac-before-validation-20261008.json` byte for byte, including shortcuts, app colors, blur, original presets and 10-point neighbor space.
- Live geometry reports are saved locally as `/tmp/hypermac-qa-*.txt`; they contain bundle IDs/geometry, not document titles. Reports may include older navigation history; comparisons use the current placement section.
- Native computer control briefly disconnected and stalled during Firefox launch. Recovery succeeded. Those tool failures were not classified as HyperMac crashes.
- An in-place config file write was not noticed by the directory watcher; atomic replacement loaded it. Settings Reload reads the active saved configuration. External in-place editing deserves a separate regression check.
- No commit, push, release or tag was created. Stable-release approval remains blocked by the failures above.
