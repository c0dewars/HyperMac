# HyperMac

A lightweight, native window-management prototype for Apple Silicon. Built for a MacBook display plus one or two external monitors, including ultrawides. Layouts use proportions rather than hard-coded resolutions.

**Status: 0.6.0 development preview — not production-ready.** See [release readiness](RELEASE-READINESS.md) before installing on another Mac. The Apple Silicon release builds with Command Line Tools and uses a persistent local signing certificate. Focused standalone core checks and selected live window-management checks pass; see `TEST-RESULTS.md` for coverage and limitations. XCTest requires full Xcode and has not run on this Mac. Broader integration and performance checks remain outstanding.

## Workspace controls — 0.6.0

- Layouts has **Duplicate** and **Redo** alongside Undo. Duplication creates an independent draft with a unique name; save to keep it. Undo/redo is one level of window geometry history, stays paused after restoration, and clears on restart or a new layout application. It does not undo layout-editor text changes or app launches.
- Shortcuts has **Record shortcut** for each row. Click, press modifiers plus a supported key, then Save changes. Escape cancels. HyperMac unregisters its own hotkeys during recording and restores them afterward. macOS-reserved combinations or other shortcut tools may still intercept keys. Key codes retain the existing physical ANSI mapping; this does not translate Portuguese key legends.
- Displays has **Automatic monitor profiles**. Connect a setup, add it, select its saved layout, and save. Repeat for each docked/undocked setup. Matching uses the exact unordered display UUID set; a 1.2-second debounce waits for display changes to settle. A matching profile applies at startup and topology changes. No profiles are created automatically. Layout rename updates profile references; deleting a layout removes its linked profiles.
- General has **Mouse resizing adjusts Dynamic splits**, enabled by default. In automatic BSP mode, drag a native window edge/corner; tiling waits during the drag, then adjusts the corresponding split and neighboring tiles on release. Screen edges remain fixed and app minimum sizes still constrain the result. Other algorithms and saved layouts retain their existing placement behavior. This is native edge resizing, not a modifier-drag-anywhere gesture.

## Layout tools — 0.5.0

- **Adaptive** is opt-in per saved layout. Matching open, visible windows share their assigned display using an adaptive grid with learned minimum sizes. Close/minimize/hide removes a window from that arrangement; opening/restoring it adds it back. Unlisted windows remain untouched. Fixed mode preserves authored rectangles; existing layouts stay fixed. Apply launches configured apps once, but subsequent reflow does not relaunch closed apps.
- Disconnected-display rows show the display selector, **Use primary display**, and a connected-display menu. These edit the draft; preview and save to apply them.
- **Preview & apply** shows the placement plan for currently visible windows and missing-window/display warnings before saving. It does not move windows or launch apps. Apply may launch additional apps, so the final plan can differ from that snapshot.
- **Undo arrangement** restores surviving visible windows from the snapshot before the last layout application and pauses tiling so the restored positions remain. It does not close launched apps, reopen closed windows, restore hidden/minimized state, or roll back layout edits. Undo history is one level, in memory, and disappears on restart. Windows targeting a completely disconnected area are skipped.

## Window transitions — 0.4.5

General → Transition duration controls eased window movement (180 ms by default; 0 turns it off). macOS Reduce Motion disables animation. Existing borders follow WindowServer geometry during transitions. Movement uses public Accessibility attributes, so app responsiveness affects animation smoothness; this is not a compositor-level animation guarantee.

Finder placement now corrects the origin after resizing has settled and avoids redundant pre-resize writes. Failed stable placements get up to three additional fallback passes instead of being immediately treated as settled. Verification retries do not replay an unchanged animation target.

## Local signed updates — 0.4.3

Installed builds reuse a certificate in your login Keychain, pinned by fingerprint in `~/.config/hypermac/signing-identity`. The installer checks that updates satisfy the installed app's signing requirement and refuses unexpected identity changes. Keep the certificate/private key and installed app location unchanged across updates. Losing or replacing the identity may require granting Accessibility again.

For the first migration from an ad-hoc build, build with `bash scripts/build.sh --build-only`, quit HyperMac, then run `bash scripts/install.sh --allow-identity-change`. Refresh its Accessibility entry once if required. Subsequent updates use the normal installer. `bash scripts/check-signing.sh` checks identity continuity across changed bundle contents and rejects an ad-hoc replacement.

This signing setup is for this Mac. Public distribution still requires a suitable Developer ID signing and notarization workflow.

## 0.4.1 settings refresh

Compact branding and explicit in-content navigation avoid macOS moving the tab bar into the title bar and clipping the header. The layout editor separates its actions into two rows, provides a scrollable canvas/inspector, and keeps save controls visible. Draft changes have an unsaved indicator; runtime details can expand in the footer. Missing system apps use readable names. The existing settings schema and tiling behavior are unchanged.

## 0.4.0 dynamic split tiling

Dynamic splits (BSP) is the default for new configurations, inspired by [yabai's split-tree model](https://github.com/asmvik/yabai/wiki/Configuration). Each display maintains a session-local tree: opening a window splits the largest available region, and closing/minimizing it expands its sibling. Hyper-arrow swaps and width/height shortcuts modify the tree while automatic tiling stays active. App minimum sizes are respected where possible; the constraint-aware layout fallback remains available. Existing algorithms, saved layouts, application pickers, exclusions and configurable shortcuts remain available.

This is HyperMac's native implementation, not a bundled yabai daemon or complete yabai feature set. Trees track the current visible windows per display; persistent per-Space trees, mouse-driven split editing and cross-display swaps are not implemented. Maximize still pauses automatic tiling, as before. Existing configurations retain their chosen algorithm unless changed in Settings.

## 0.3.4 exterior borders

Borders are drawn outside their owner's current WindowServer bounds, with antialiasing padding, and ordered directly below that window. macOS handles foreground occlusion; HyperMac no longer subtracts foreground bounding rectangles, which could incorrectly truncate outlines for transparent windows. This uses AppKit, inspired by the exterior-border/owner-relative design in [JankyBorders](https://github.com/FelixKratz/JankyBorders). JankyBorders is not bundled or required. Light-green color and configurable width remain unchanged.

## 0.3.2 automatic reflow

Automatic tiling now reconciles the visible window set every second in addition to window events. Opening, closing, hiding, minimizing or restoring a window redistributes space without clicking Tile now. Stable windows are not repeatedly resized. When an app refuses a smaller tile, HyperMac learns its accepted minimum size and searches for a non-overlapping arrangement that fits. If window minimum sizes exceed the display, the status reports the constraint. Reopening HyperMac opens Settings & capture.

## 0.3.1 layout deletion fix

Deleting the selected layout could crash while SwiftUI refreshed the outgoing inspector. Layout and placement bindings now retain safe fallback values during removal. Verified deletion with the advanced inspector open, including consecutive deletion of two temporary layouts. Capture, presets, renaming, saved placement, and missing-monitor fallback were also exercised against real windows; see `TEST-RESULTS.md`.

## 0.3.0 settings and tiling update

- Shortcuts use a native Applications picker, app icons and friendly names. Choose app changes the launch target; Add app shortcut opens the same picker. Set a key before saving.
- General → Floating apps lets you select one or more apps from Applications to ignore, or choose Allow tiling to remove an exception. Other normal, visible, movable and resizable windows tile automatically. HyperMac itself, dialogs and native fullscreen windows remain unmanaged.
- New configurations enable automatic tiling by default and exclude System Settings, which stays floating. Existing saved startup preferences are retained on upgrade.
- All eligible windows have the same light-green border while automatic tiling or a saved layout is active. General controls the shared color, width and visibility. Pausing hides borders. Layout-editor app colors remain independent.
- The settings header and controls use the icon's indigo, cyan, violet and mint palette. Shortcuts have search, grouped cards and a one-click Hyper modifier preset.
- macOS app build and focused core checks pass; border behavior still requires Accessibility access and real-window validation.

## Placement reliability development

- Selected minimized windows are restored in a separate phase, with a bounded settling delay before geometry writes. A window still minimized during a retry is restored again and deferred to the next pass.
- Placement verification waits 150, 300, then 600 milliseconds across the three bounded passes, giving slower applications more time to settle. Only unmatched targets receive further geometry writes.
- Real-device acceptance still requires applying a saved layout to minimized windows and moving windows between displays, then inspecting Copy troubleshooting report for verified positions.

## 0.2.3 installation and icon update

- The default build now installs and opens HyperMac, and reveals the installed app in Finder.
- Installation uses `/Applications` when writable, otherwise `~/Applications`. An existing user installation stays in that location. If a previous global installation cannot be replaced, the installer reveals the new build for manual replacement in Finder.
- A new tiled-window icon is bundled as ICNS. Building requires no image-conversion tools.
- General settings shows the running app's exact path, with Show this app in Finder and Copy app path buttons for Accessibility setup.
- `bash scripts/build.sh --build-only` builds without installing or opening. `bash scripts/install.sh` installs a previously built app. Quit the running HyperMac before installation.

## 0.2.2 placement reliability update

- Window discovery accepts small AX/WindowServer decoration differences and uses Core Graphics rectangle decoding. A failed writability query no longer silently excludes a window; explicit non-resizable windows are still skipped.
- Window IDs and ordering remain stable for an app session instead of changing with the order returned by AXWindows. IDs are not persistent across app restarts. Distinctive title rules remain useful for multiple documents.
- Moving across displays first shrinks the window if needed, changes its position, then sets the requested size and final position. Geometry is read after a short settling delay. Only unmatched targets are retried, for at most three passes.
- Saved layouts can restore their selected minimized windows. Running apps are unhidden without requesting another launch/reopen, which could otherwise create extra windows.
- Window events get two bounded follow-up discovery passes for apps that expose their attributes after the creation notification. Automatic mode also checks the window set and geometry once per second to recover missed notifications; unchanged frames are not rewritten.
- General settings now has Tile now, Pause, and Copy troubleshooting report. Runtime status reports how many requested positions were actually verified. Save settings persists configuration; Save & arrange applies the selected layout.
- The build prints the source folder/version and stops when launched from Trash, to avoid rebuilding an old copy after replacing the project folder.

If placement is still wrong: reproduce it once, choose Copy troubleshooting report in the menu bar or General settings, and inspect/share that text. It includes app bundle IDs, display IDs, discovery failures, and requested/actual frames; it excludes document/window titles. No report is transmitted automatically. This update addresses code weaknesses, but the exact cause on your Mac needs the runtime report if it persists. The macOS adapter remains untested in this Linux environment.

## 0.2.1 compatibility fix

The supplied macOS 27 SDK build log resolves `@State` to a SwiftUI macro whose `SwiftUIMacros` plugin is unavailable in the selected Command Line Tools. The editor now stores its state in `StateObject`/`ObservableObject` models with `Published` properties, avoiding that macro dependency. This also addresses the cascading missing-binding and immutable-self diagnostics. App-directory enumeration now runs in a synchronous helper invoked from a background task, avoiding the async `makeIterator` warning.

Use the complete updated source and rebuild with `bash scripts/build.sh`. The source passes syntax parsing here; a successful Mac build and runtime test are still required. Existing layouts and configuration are unchanged by this patch.

## What is implemented in source

- Native arm64 Swift app; AppKit menu bar and an on-demand SwiftUI settings window.
- Global configurable shortcuts for launching/focusing apps, layouts, toggling tiling, and retiling.
- Adaptive grid, equal columns, and main-window/stack automatic tiling, independently per monitor.
- Saved multi-monitor layouts with normalized frames, application bundle IDs, optional title filters, and window indices.
- Visual monitor canvas: drag installed apps onto screens, move rectangles between screens, resize from a corner, and optionally snap to a 5% grid.
- Searchable installed-app library with icons; per-app layout colors and click-through shared-color borders around tiled desktop windows.
- Graphical editors for shortcuts, gaps, exclusions, and tiling defaults, with advanced window matching available when needed.
- Capture of the current visible arrangement, including specific display IDs.
- JSON configuration, validated and reloaded on file changes without restarting.
- Display roles (`built-in`, `primary`, `external-1`, `external-2`) and specific display UUIDs.
- Event-driven updates, debouncing, background AX window operations, and bounded app-launch retries.
- No third-party package dependencies, embedded browser, helper daemon, or network requests.

This manages existing macOS application windows. It does not replace WindowServer or implement Hyprland's compositor effects. It does not create, move, or switch native Spaces.

## Build on your Mac

Declares macOS 14 or later; builds for the host CPU (Intel or Apple Silicon). Requires and an Xcode/Command Line Tools installation with Swift 5.9 or later. M2 Pro and M3 Pro are the initial target hardware; neither has been tested yet.

1. Quit the old HyperMac and extract the source ZIP outside Trash.
2. If developer tools are missing, run `xcode-select --install` in Terminal and finish installation.
3. Open Terminal in the extracted `HyperMac` directory and run:

   ```sh
   bash scripts/setup-local-signing.sh # once per Mac
   bash scripts/build.sh
   ```

4. The installer copies HyperMac to `/Applications` or `~/Applications`, reveals it in Finder, and opens it. Keep it at this stable location.
5. Grant access under **System Settings → Privacy & Security → Accessibility**. Click **+**, press **Command–Shift–G**, and enter the installed app path printed by the script. You can also copy the exact path from HyperMac Settings → General → Permissions. Select HyperMac, click Open, and enable its switch. If an old entry stops working after a rebuild, remove it and add the installed app again.
6. Select **Resume / automatic tiling** from its menu-bar icon, or apply a saved layout.

The setup script creates a local code-signing certificate and stores its private key in the login Keychain. Approve codesign access when macOS asks; choosing Always Allow permits subsequent local builds. The certificate is trusted only for code signing. No SIP changes are required. Disposable builds can use `bash scripts/build.sh --ad-hoc --build-only`; the installer refuses these builds.

### Running the tests

The app does not depend on XCTest. The test target does. If `swift test` reports `unable to resolve module dependency: XCTest` while using `/Library/Developer/CommandLineTools`, build the app with `bash scripts/build.sh` (the default no longer invokes tests).

To run tests, install and open full Xcode to finish its setup, then use its developer tools for this command only:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build.sh --test
```

Adjust the path if Xcode is installed elsewhere. This does not change the system-wide developer directory. CI uses `--test --build-only --ad-hoc` so failed tests still block its build. An app-only build does not imply tests passed.

To run at login, add the installed app in macOS Login Items. The prototype does not register itself automatically.

## Visual layout editor (0.2.0)

1. Open Settings → Layouts and choose an existing layout or New layout.
2. Search the app library on the left. Drag an app onto a monitor, or click the app to add it to the first external display (primary if none is connected).
3. Drag its rectangle to position it, including between monitors. Select it and drag the bottom-right handle to resize. “Snap 5%” snaps on release; turn it off for free placement. Left half, Right half, and Full screen area are quick presets.
4. Click the rectangle and use **App color**. All placements of that application share the color. The selected rectangle uses a thicker stroke; other app rectangles keep their own colors.
5. Click **Save & arrange** to persist settings and apply the layout to actual app windows. Creating/editing rectangles alone does not move desktop windows. You can still assign layout shortcuts on the Shortcuts tab.

Connected screens appear in their macOS arrangement, scaled to fit. Screen arrangement itself is changed in macOS Display Settings, not by moving monitor outlines here. The sidebar lists every placement, including those targeting a disconnected display. Select an unavailable placement and use its advanced display field to assign a connected display, or reconnect that monitor to position it visually. The canvas previews the requested rectangles; real apps may impose minimum dimensions. Layout gaps are applied on the desktop, not simulated in the canvas.

The app library scans `/Applications`, `/System/Applications`, and `~/Applications` only when the settings designer opens or you click Refresh. Apps elsewhere can still be specified by bundle ID in advanced controls. It does not scan your documents or send app inventory over the network. Adding the same app again selects its next zero-based window index; HyperMac does not automatically create multiple document windows for that app.

**Desktop borders:** enable them in Settings → General and choose a shared color and width. All eligible visible windows are outlined while tiling is active. The default is light green. Ignored apps, HyperMac, dialogs and native fullscreen windows are excluded. Pausing hides borders. Panels ignore clicks and never take keyboard focus. Updates use window/workspace events plus a lightweight window-stack check. Outlines sit outside and below their owning windows, with native window stacking handling occlusion. Multi-window performance still needs profiling.

Updating from 0.1.0 retains your existing config and layouts. New color settings use defaults until you save your choices. Quit the old app, build this source in a normal project folder, and replace the installed app. Keep the installed location and signing identity the same to retain Accessibility access across updates.

## Default shortcuts

Defaults follow [Omarchy's window and application shortcuts](https://github.com/omacom/omarchy/blob/quattro/manual/07-hotkeys.md), adapted to macOS. **Base = Control + Option + Command** represents Omarchy's Super; **Hyper = Control + Option + Command + Shift** represents Super+Shift. Your existing Karabiner Caps Lock → Hyper mapping works directly. Hyper already includes Shift, so Hyper+Shift cannot be a separate shortcut.

| Shortcut | Action |
| --- | --- |
| Base + arrows | Focus the nearest window in that direction |
| Hyper + arrows | Swap focused window geometry with a window in that direction |
| Base + Return | Terminal: Ghostty, iTerm2, then Terminal |
| Hyper + Return or B | Default browser (B is a compatibility alias) |
| Hyper + F | Finder |
| Hyper + N | VS Code, then TextEdit |
| Hyper + M | Spotify, then Music |
| Hyper + C / E | Calendar / Mail |
| Hyper + A | ChatGPT, then Codex |
| Hyper + G | Signal, WhatsApp, then Messages |
| Hyper + P / S | Photos / Maps |
| Hyper + D | Docker Desktop |
| Hyper + O | Obsidian, then Notes |
| Hyper + slash | 1Password, NordPass, then Apple Passwords |
| Base + F | Maximize to usable screen / restore |
| Base + minus / equal | Grow / shrink width by 100 points |
| Hyper + minus / equal | Shrink / grow height by 100 points |
| Base + T / R | Toggle automatic tiling / retile |

App aliases choose the first installed application in the listed order, except `@browser`, which resolves the macOS default web handler. An unavailable app reports an error; HyperMac does not install apps. All launch targets can be changed to exact bundle IDs in Settings → Shortcuts.

Manual swapping, resizing, and maximizing pause automatic/saved-layout reapplication to preserve your changes. Directional selection uses visible manageable windows, including neighboring monitors; when no directional neighbor exists it leaves the window unchanged. Swapping exchanges rectangles, not app content. Maximize uses the usable desktop without entering native fullscreen. Resizing affects the focused window only, so windows can overlap. App minimum sizes still apply.

This preset covers supported desktop window and app actions. Omarchy-specific workspaces, scratchpads, grouping, compositor floating modes, mouse bindings, and Linux-only app variants are not emulated. The previous numbered saved-layout defaults are no longer assigned; saved layouts remain available through the menu and custom shortcuts.

On startup, the exact original six-shortcut preset is upgraded automatically, with the original configuration backed up to `~/.config/hypermac/config.before-omarchy-shortcuts.json`. Custom shortcut sets are preserved. Choose **Settings → Shortcuts → Add missing Omarchy shortcuts** to add available default actions while keeping existing bindings. Occupied key combinations and actions already assigned to another key are skipped. Every shortcut appears as an editable row. To replace the whole set, choose **Use Omarchy / Hyper defaults**, review the draft, then **Save settings**.

Change these in Settings → Shortcuts. Shortcut registration reports OS-level conflicts and attempts to restore the previous bindings if an update fails. Some macOS-reserved combinations cannot be used. Names refer to physical US/ANSI key positions in this prototype; logical keys on Portuguese and other keyboard layouts need a future keyboard-layout-aware recorder.

Focused regression checks for the preset, configuration validation and directional/resize geometry run with Command Line Tools alone:

```sh
swiftc Sources/HyperMacCore/*.swift scripts/check-shortcuts.swift -o /tmp/hypermac-shortcut-checks
/tmp/hypermac-shortcut-checks
```

## Two modes, no layout fighting

**Automatic:** new/closed/minimized/restored eligible windows trigger a debounced reflow on their current screens. You can manually move windows; movement itself does not trigger a reflow, so dragging stays usable. Use Retile after manually moving a window between monitors.

**Saved layout:** the named arrangement applies and automatic tiling stops. App/window/display events reapply that arrangement; unrelated windows are left where they are. Switching back to automatic is explicit. Layout selection is manual; automatic Office/Home profile selection is not implemented.

**Paused:** no arrangement work. Settings and shortcuts remain available. Automatic mode is enabled for new configurations; grant Accessibility access to start managing windows. The startup preference is distinct from the current runtime mode.

Applying a saved layout unhides running apps and launches missing apps and makes bounded retries for up to roughly eight seconds. Reopening does not guarantee that an app creates a window. HyperMac does not create multiple documents, restore browser tabs, or open a particular VS Code project. Open those windows first and assign title rules. Reapply a layout if an app takes longer to start.

## Configure Office, Home, and other screens

The starter layouts use Apple apps so they are editable without additional software:

| Layout | External display | Built-in display |
| --- | --- | --- |
| Office | Safari 65%, Terminal 35% | TextEdit |
| Home | Safari 50%, Terminal 25%, TextEdit 25% | Left unchanged |
| Two externals | Safari on external-1; Terminal on external-2 | TextEdit |

Replace these apps in Settings → Layouts. Example bundle IDs: `com.microsoft.VSCode`, `com.google.Chrome`, `com.apple.Terminal`, `com.apple.Safari`. To inspect an installed app's ID:

```sh
mdls -name kMDItemCFBundleIdentifier '/Applications/Visual Studio Code.app'
```

`external-1` is the leftmost external display according to the macOS display arrangement; `external-2` is the next one. On vertically aligned displays, the upper one comes first. These roles remain portable between different Macs, but changing physical ordering can change their assignments. Use `uuid:…` from Settings → Displays for a particular monitor. UUID persistence depends on macOS, display firmware, and the connection/dock.

Coordinates use the usable display area in **logical points**, respecting menu bars and the Dock. A 3440 × 1440 physical display may report a different logical size. No particular G9 resolution is assumed. The engine also handles negative display origins, portrait displays, and scaled displays.

By default, a missing target monitor causes that placement to be skipped. Enabling “Use primary display if a target display is missing” redirects it to primary, but multiple redirected placements can overlap. Existing windows are never closed to enforce a layout. macOS handles its own relocation when a display disconnects.

## Capture and edit a layout

1. Pause HyperMac and arrange your visible windows.
2. Open Settings → General, enter a unique layout name, and click **Capture visible windows**.
3. Review Settings → Layouts. Select an app rectangle and open Advanced window matching & coordinates. Capture records exact display UUIDs. It leaves the title filter empty for single-window apps, and uses the full title as a substring rule for apps with multiple windows. Shorten changing titles, or clear the rule and use a zero-based window index. Indices follow the session-stable discovered window order and are not persistent document identities across application restarts.
4. For a layout shared between Macs, replace UUIDs with display roles.
5. Add a shortcut with action “Apply layout” and the exact layout name.
6. Click **Save & apply**. Apply the layout from its shortcut or menu.

Captured layouts disable the additional gap by default, preserving measured bounds as closely as rounding and app constraints permit. The visual editor supports drag-and-drop placement and corner resizing. Numeric percentage entry remains under Advanced window matching & coordinates.

## Text configuration

The first launch creates `~/.config/hypermac/config.json`. See `examples/config.json` for the complete schema. Copy the file between your work and home Macs if desired; no automatic sync is included.

Each placement contains:

```json
{
  "bundleID": "com.microsoft.VSCode",
  "titleContains": "HyperMac",
  "windowIndex": 0,
  "display": "external-1",
  "frame": { "x": 0, "y": 0, "width": 0.65, "height": 1 }
}
```

In JSON, X/Y/width/height are fractions from 0 to 1. The advanced graphical controls show percentages. Rectangles must fit inside the display. Each layout has `name`, `fallbackToPrimary`, `applyGap`, and `placements`. Keep all original fields shown in the complete example. The new `borderEnabled`, `borderWidth`, `borderColor`, and `appColors` fields are optional when reading an existing 0.1.0 config; defaults preserve compatibility. When renaming or deleting a layout, update its shortcuts too.

Invalid config edits leave the last accepted configuration running and display an error. The settings editor detects changes to the active configuration while it is open and asks you to reload before saving. File writes are atomic. Deleting the configuration directory while running is unsupported; restart after recreating it.

## macOS limits and prototype caveats

- Accessibility access is required. Screen Recording permission is not requested.
- Automatic tiling manages visible, standard, movable and resizable windows. Saved layouts can also restore selected minimized windows. Hidden and native-fullscreen windows, sheets and dialogs are excluded from normal discovery; applying a layout unhides its apps. Exit native fullscreen before arranging.
- Visible-window filtering matches public WindowServer owner PID and geometry to AX window geometry; ambiguous or unusual windows can be missed. No private window-ID API is used.
- Applications can enforce minimum sizes or reject geometry changes. The menu status reports these constraints. A layout is best effort, not an atomic multi-app transaction; the user can see sequential movement.
- Saved window-title rules can stop matching as document/tab titles change. Distinctive title rules are preferable to indices for multiple windows of one app.
- Apps vary in their AX notification support. Automatic mode reconciles once per second as a fallback for missed notifications, including windows that become eligible after startup. Saved layouts remain event-driven.
- Use one window manager at a time. Stage Manager and other tilers can compete with requested positions.
- Native Spaces, Stage Manager, mirror mode, clamshell transitions, and third-party app compatibility require real-device testing. This prototype does not emulate virtual workspaces.
- Pause prevents new layout passes; a move batch already in progress may finish.
- The settings UI loads only when opened; system frameworks may retain caches after it closes. Memory and CPU performance have not been measured.

## Architecture

`HyperMacCore` is Foundation-only: validated configuration, portable display selection, normalized geometry, tiling algorithms, and layout planning. `HyperMac` contains the macOS adapters:

| Component | Responsibility |
| --- | --- |
| `App` | Menu bar, lifecycle and configuration changes |
| `Engine` | Mode switching, debounced events, bounded launch reconciliation |
| `Accessibility` | Window discovery and movement on a serial worker queue; AX subscriptions |
| `ScreenCatalog` | Public screen IDs, usable bounds, AppKit-to-AX coordinate conversion |
| `HotKeys` | Carbon registered hotkeys; no global keystroke stream |
| `ConfigStore` | Atomic JSON writes and directory change notifications |
| `SettingsView` / `LayoutDesigner` | On-demand native editors, draggable monitor canvas, app library, and capture controls |
| `FocusBorder` | Nonactivating, click-through outlines for eligible windows while tiling is active, updated via AX events |

AX timeouts are bounded; observers ignore movement notifications to avoid feedback loops; matching frames are not repeatedly written. A one-second reconciliation timer is active in automatic mode to recover missed window events. Notification setup uses the main run loop and can still incur AX work; profile it before making latency guarantees. The first performance goal is negligible idle activity, not an unmeasured RAM or CPU promise.

Primary API references:

- https://developer.apple.com/documentation/applicationservices/axuielement_h
- https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
- https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification
- https://developer.apple.com/documentation/appkit/nsworkspace

## Validation and next acceptance gate

Local checks passed: all 17 Swift files parse with the tree-sitter Swift grammar; the example JSON and app plist parse; the build script passes Bash syntax checking. These checks do not type-check Apple APIs or execute Swift code.

The included XCTest suite covers config round-tripping and rejection, duplicate keybindings, display-role ordering and fallback, negative origins and scaled geometry, nonoverlapping tiling over multiple aspect ratios, window matching, duplicate assignments, and captured gap preservation. **These Swift tests have not been run in the authoring environment.**

`bash scripts/build.sh` creates the host-architecture app without building the XCTest target. `bash scripts/build.sh --test` runs tests first and stops on failures; it requires full Xcode selected. `.github/workflows/macos.yml` provides a Mac CI build with mandatory tests when this project is placed in a GitHub repository; it has not been run or connected to a repository here.

Before treating 0.2.2 as usable:

1. Build with the macOS SDK and resolve any compiler/API issues.
2. Grant/revoke Accessibility permission and verify recovery; exercise shortcuts and conflicting registrations.
3. Test Safari, Terminal, VS Code and your real work apps; check min sizes, multiple windows, capture, and restore.
4. Test built-in + office ultrawide, built-in + G9, and two external displays, including screens to the left/above primary.
5. Test unplug/replug, sleep/wake, lid close/open, scaling changes, and fullscreen/Spaces transitions.
6. Check invalid JSON edits retain the active config, and settings/shortcut updates recover after errors.
7. Test app-library search, drag/drop, cross-monitor moves, corner resizing, snapping, Save & arrange, color persistence, old config migration, and border changes while focusing/moving/resizing windows. Confirm clicks pass through the border.
8. With Settings closed, use Activity Monitor and Instruments to record idle CPU/wakeups/memory, 20-window tiling latency, and layout startup latency on both M2 Pro and M3 Pro. No numerical performance result is claimed yet.

Potential follow-ups: keyboard shortcut recorder with Portuguese keyboard support; declarative app/document launch rules; automatic display-profile selection; undo-last-layout; signed/notarized distribution; broader integration tests.
