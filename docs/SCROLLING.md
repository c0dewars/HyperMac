# Horizontal scrolling — development preview

This branch adds a horizontal strip with optional vertical groups. It is experimental. Each horizontal display has its own strip, which must have a safe horizontal outside edge for parking overflow windows. The Odyssey G95C has been tested with the built-in display also connected; a monitor surrounded on both sides is rejected. A display without a safe outside edge is left unchanged and reported; other supported displays continue.

## Use

1. Create or select a layout. In **Choose a screen**, click the display you want to configure. Its card shows its current mode.
2. Choose **Screen mode → Horizontal scroll**. This changes the selected screen only. Choose **Automatic tiles**, **Tile saved apps**, **Custom positions**, or **Leave unchanged** independently on the other screens. A new layout initially leaves every screen unchanged.
3. Add apps from the library to the selected screen. Drag a card onto another to stack it; use Move left/right to reorder. Select an app to adjust its saved width, including Full width. Remove it with × or the sidebar minus button.
4. Expand **Horizontal defaults · shared across scrolling screens** for include-all, default column width, neighbor space, centering, wrap, Hyper + scroll, and transition duration. These options are shared; each screen's app widths and groups are independent. On Apply, matching saved apps move to their assigned screens. Include-all then adds eligible unlisted windows already on each screen and does not launch apps. Turn it off to use only saved apps.
5. Use **Preview & apply** to review the mode and visible placements for every screen before switching to this layout. Valid edits save automatically and update the layout when it is active. Selecting a screen card alone never changes saved settings. **Move rule to…** changes the saved destination. Applying the layout moves the matching open window there; destination edits in an active layout also take effect automatically. Empty horizontal screens are identified in the preview.

**Automatic tiles** includes all eligible open windows on the screen and uses General's algorithm. **Tile saved apps** redistributes space among matching app rules. **Custom positions** uses the saved rectangles. Preview and Apply share a display-assignment planner, so matching saved apps move to the displayed destination. Local matches on both screens are reserved first to keep two windows of the same app independent. Legacy layouts retain their original behavior until a screen mode is edited. Disconnected app rules remain accessible in the sidebar.

The current preview hides partially/off-screen columns. The editor is a template, not a live view of every running window. Missing template apps are not launched when “all eligible open windows” is enabled.

## Controls

**Hyper + H** focuses the previous column; **Hyper + L** focuses the next. Hyper is Control + Option + Command + Shift, including Caps Lock mapped by Karabiner. These defaults are editable in Shortcuts as “Focus window in direction.” Enable **Wrap left/right navigation** to cycle through the ends. Existing installations preserve custom shortcuts; add a Focus action for each direction if these keys are not yet configured.

Existing configurable Focus, Move/Swap and Resize window shortcuts operate on the active strip. Left/right moves through columns; up/down moves within a group. Moving left/right reorders the whole column. Moving up/down exchanges group members. Width resizing changes the column; height resizing changes the selected member's share.

Each display keeps its own windows. The screen cards select both the mode control and app editor; there is no separate scrolling-destination picker. Template rules set destinations, widths and groups. Ordinary navigation/reflow stays local after assignment; manually moving a window to another screen does not cause it to be pulled back on every refresh. Newly discovered matching windows are assigned when they appear. The same app can have a full-width rule on the laptop and a narrower rule on the external display. Window indices and group IDs are local to the screen. Drag a window to another screen to move it between modes. With focus on a normally tiled screen, directional shortcuts act on that screen. The editor's Previous/Next buttons are shown only for a horizontal screen and target that screen explicitly.

In Shortcuts, **Add shortcut → Window action…** lets you record a combination for Group into previous column, Group into next column, Separate from column, or Center column. No existing keybindings are overwritten. Hyper already includes Shift, Control, Option and Command; adding Shift to Hyper is not a distinct combination.

Drag a live window by its title bar into the lower third of another visible tile and release to stack it underneath. Drop near the horizontal center (away from the sides). Resize gestures do not group windows. Groups that cannot satisfy app minimum sizes are separated.

Choose an app card and set its column width with the slider or ⅓ / ½ / ⅔ / Full width presets. A plain first-window app rule also supplies the width for additional windows of that app. Add the same app twice to define a group with two of its windows. Full width fills the available width while preserving configured gaps and parking margins; it does not enter native macOS fullscreen.

Scrolling transitions have a separate duration (220 ms by default) and respect Reduce Motion. A new navigation press cancels superseded animation/settling work and replaces the pending intent. Interrupted transitions resume from their last emitted logical frames, so held keys cannot build a long queue of old destinations.

When a neighboring display blocks either scrolling edge, navigation uses instant placement. Animating a window parked on the opposite edge would make it cross in the wrong direction. Both horizontal edges must be free for continuous sideways animation; HyperMac does not change the macOS display arrangement. Per-display tiling isolation does not provide compositor-level clipping.

Mouse edge/corner resizing is reconciled on release when the General mouse resizing setting is enabled. Optional Hyper + wheel/trackpad scrolling advances at most one column per gesture and ignores momentum. Unphased wheel events are grouped until a 250 ms quiet interval. It is not continuous inertial panning. The global monitor does not suppress the original scroll event, so applications may also react to it. It is off by default.

## Lifecycle and recovery

- New windows are inserted after the focused column, without changing existing column widths.
- Closing/minimizing removes the live window; remaining members fill the column height. Restoring a minimized window treats it as a new insertion (its previous group is not retained unless specified by a template).
- Focusing a managed window brings it into view.
- Groups that exceed measured minimum heights are separated into individual columns. Windows too wide for the display are reported as unsupported.
- Native maximize is unavailable while scrolling; resize the column or pause first.
- Pausing, switching modes, normal app quit, or an incompatible display change attempts to restore pre-scrolling positions. Forced termination cannot run restoration.
- Runtime grouping/order changes last for the session. Capture the arrangement to save them as template rules.
- Undo/redo of applying an arrangement retains a scrolling session when the named scrolling layout still exists. This needs live validation.

## macOS limitation

Unlike a Linux compositor, HyperMac does not own window rendering or clipping. Off-screen windows are parked with a 32-point visible edge; their borders are suppressed. This is not invisible off-screen storage. Overflow uses a safe exposed edge of the selected display, avoiding other connected displays. Each horizontal display has independent membership, focus, order and groups. Native Spaces transitions, modal dialogs, failed AX positioning, perceptual animation quality, and quit/undo recovery still need real-app tests before release.

## Verification

Run these with Command Line Tools:

```sh
swiftc Sources/HyperMacCore/*.swift scripts/check-scrolling.swift -o /tmp/hypermac-scroll-checks
/tmp/hypermac-scroll-checks
swiftc Sources/HyperMacCore/*.swift scripts/check-shortcuts.swift -o /tmp/hypermac-checks
/tmp/hypermac-checks
swift build --configuration release --arch arm64 --product HyperMac
```

The scrolling checks cover stable sizes, insertion bursts, grouping/reflow, navigation/wrap, resizing, constraints, 1–100 windows, negative origins, 5120-point ultrawide geometry, configuration migration, safe overflow projection beside the built-in display, and rejection of surrounded displays. Both GitHub workflows also run them.

Live checks on the Odyssey G95C with the built-in display connected: four blank private Brave windows produced 4/4 verified placements; closing one produced 3/3 and opening a replacement produced 4/4. Remaining acceptance: minimizing/restoring, repeated physical shortcut navigation, two- and three-window groups, mouse resize, borders at both edges, pause, undo/redo, normal quit, and display reconnect. Do not treat passing geometry tests as evidence of smooth native animation.

## Focus appearance

General → Tiled-window borders defaults to outlining only the focused window. Explicit app colors override the global fallback. Optional experimental blur covers unfocused eligible windows using native AppKit behind-window material, with click-through panels ordered relative to each owner. It is off by default and suppressed by Reduce Transparency, paused tiling, ignored-app focus and parked windows. Blur is available across layout modes, not only centered scrolling.

## Starter presets

New installations receive exactly Normal and Horizontal. Both include the macOS default browser detected at first launch, VS Code, and Teams. Normal adapts to the open matching windows; Horizontal starts with half-width columns. With include-all enabled, Horizontal arranges eligible open windows and uses matching template rules for widths and groups. With include-all disabled, it launches missing configured apps. Existing installations keep their saved layouts unless the user explicitly replaces them.

## Blur intensity and column editing

General → Tiled-window borders includes Blur intensity from 0–100% in 5% steps. Zero hides the effect; macOS controls the material's blur radius. Intensity changes save automatically. Turning Blur unfocused windows off immediately removes its effect panels.

Column cards have a horizontal resize handle. Drag it to adjust width, or drop one app card onto another to stack their template windows. Expand **Screen overview** for the editable monitor diagram: drag rectangles sideways to reorder or separate them, drop into the lower third of another rectangle to stack, and select a rectangle to reveal its column-width handle. Columns beyond the first viewport remain accessible in the horizontally scrolling cards.

## Removing apps and window ordering

Use × on an app's column card or the minus button beside it under Apps on this screen. Removing the last rule for an app on a screen adds it to that screen’s exclusions, including when all open windows are included. Rules for that app on other screens remain independent. Add it again from the library to restore it, or use Add back beneath the selected app inspector. Other layouts are unaffected.

Scrolling reserves 48 points at each horizontal edge for parked-window edges and shadows, plus **Neighbor space** (120 points by default, adjustable from 0–240). Full-width columns fill the center area left after those margins. Narrower columns may reveal more neighbors; the reserve prevents wide columns hiding them on free edges. The first and last columns only have neighbors where they exist, unless wrap navigation is enabled (wrapping does not duplicate edge windows). Partially visible neighbors are raised above fully parked windows. Keyboard transitions interpolate logical strip positions together; macOS still controls clipping and app responsiveness. When another display blocks an edge, overflow must use the opposite safe edge, so this is not equivalent to a Linux compositor.


## Navigation diagnostics

Window discovery uses a stable WindowServer window number when macOS provides the optional `_AXUIElementGetWindow` function. This avoids confusing overlapping parked windows or dropping a moving window when AX and WindowServer bounds temporarily disagree. The function is resolved at runtime; public geometry matching remains the fallback. Windows must still be present in the on-screen window list, so hidden, minimized and other-Space windows are not pulled into the strip.

Stacked rows use the same safe parking edge, including when the laptop display is staggered below the external screen. Recent navigation reports retain the last eight commands with their column order, elapsed time, requested/actual frames, keyboard-focus verification and superseded status. Use More → View troubleshooting report or General → Copy troubleshooting report after reproducing a problem. Reports omit document titles.

Navigation keeps the requested focus through delayed activation events. New mouse or non-navigation keyboard input releases that focus ownership. Closing the requested window reconciles membership before selecting a surviving neighbor, including when macOS briefly reports no focused window.
