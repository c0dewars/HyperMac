<p align="center">
  <img src="Resources/AppIcon.png" width="112" alt="HyperMac icon">
</p>

# HyperMac

**A place for every window.**

HyperMac is a native macOS window manager that automatically arranges your apps, saves layouts for different setups, and puts window controls and app launchers on customizable keyboard shortcuts.

> **0.7.0 build 28 · Development preview · Apple Silicon only.** Intel support has been retired. Clean-Mac installation and the full window-management compatibility matrix are still being validated. Preview DMGs are ad-hoc signed; there is **no notarized production release**. See [release readiness](RELEASE-READINESS.md) for the remaining work.

## Feature tour

![HyperMac feature walkthrough](docs/media/hypermac-feature-tour.gif)

A captioned tour of automatic tiling, horizontal columns, the screen-first Layouts editor, destination previews, widths and groups, blur controls, and the redesigned shortcut editor. This is a screenshot walkthrough, not a recording or proof of animation smoothness. [Browse the screenshots and capture notes](docs/media/README.md).

## What you can do

- **Tile automatically:** opening, closing, minimizing or restoring eligible windows redistributes available space. Dynamic splits is the default for new configurations.
- **Keep selected apps floating:** choose apps from Applications in the exclusions list. System Settings is excluded by default.
- **Customize borders and transitions:** light-green borders by default, adjustable width and color, and eased movement that respects Reduce Motion.
- **Start with two presets:** Normal (adaptive tiling) and Horizontal (scrolling), using your default browser, VS Code and Teams. Choose different apps from Applications and customize widths or groups.
- **Create saved layouts:** drag apps onto monitor previews, resize their rectangles, duplicate layouts, or capture your current arrangement.
- **Try horizontal scrolling:** keep independent columns on one or every monitor, choose a tiling mode separately for each display, customize app widths per screen, reserve space for neighbors, and navigate with Hyper + H/L. [Experimental controls and limitations](docs/SCROLLING.md).
- **Use adaptive layouts:** let the open windows listed in a saved layout share the available space.
- **Undo and redo an arrangement:** restore one previous arrangement of surviving windows.
- **Edit shortcuts:** search or filter a compact list, click a key combination to record it, and expand a row to change its action. Conflicting combinations are rejected.
- **Adjust settings immediately:** valid changes save automatically; appearance controls apply without retiling. Blur has a complete Off switch and a 0–100% intensity slider.
- **Remove layout apps:** use × on a horizontal card or the minus control in the sidebar. Screen-specific exclusions keep removed apps out even with include-all enabled.
- **Switch layouts when docking:** save monitor profiles for your connected display setups.
- **Resize with the mouse:** in automatic Dynamic splits mode, drag a normal window edge or corner to adjust neighboring tiles when you release it.

## Requirements

- macOS **14 or later**, on **Apple Silicon (M1 or newer)**. This is the declared minimum; not every supported macOS version has been tested.
- Accessibility permission so HyperMac can move and resize windows.
- Xcode Command Line Tools only when building from source. Full Xcode is needed to run XCTest; neither is required to install a DMG.
- Access to this private GitHub repository to download source or clone it.

Karabiner-Elements is optional. If you already map Caps Lock to Hyper, that mapping works with HyperMac's Hyper shortcuts.

## Preview downloads

The **0.7.0 build 28** test prerelease includes horizontal scrolling, the new shortcut editor and corrected per-screen Preview & apply routing. Download the DMG and checksum from [Releases](https://github.com/c0dewars/HyperMac/releases). See the [remaining fixes and acceptance checks](docs/KNOWN-ISSUES.md) before testing.

Authorized repository users can run **Actions → Apple Silicon preview DMG → Run workflow**. The default creates a downloadable build artifact. Enable **Publish an unnotarized prerelease** on `main` to attach the DMG and SHA-256 checksum to [Releases](https://github.com/c0dewars/HyperMac/releases). Private repository access is required.

These are development previews: Gatekeeper may block them, and replacing a locally signed copy may require refreshing Accessibility permission. Source installation below preserves a stable local signing identity.

If a downloaded preview says **the developer cannot be verified**, move it into Applications, try opening it, then use **System Settings → Privacy & Security → Open Anyway** for HyperMac if you choose to trust it. Follow [Apple's instructions](https://support.apple.com/102445). HyperMac runs in the menu bar; enable Accessibility on each Mac after installation.

No paid Apple account is needed for this installation path. [Sharing a preview with friends](docs/DISTRIBUTION.md) explains the package, first launch and updates. Signing status is separate from app stability: horizontal scrolling remains experimental.

## Install from source

This is currently a developer/tester installation. Each Mac creates its own local signing identity; this does not produce an Apple-notarized release for redistribution.

1. Sign into GitHub, open [HyperMac](https://github.com/c0dewars/HyperMac), and choose **Code → Download ZIP**. Extract the ZIP outside Trash. Alternatively, clone the repository using your GitHub credentials.
2. Install Command Line Tools if needed:

   ```sh
   xcode-select --install
   ```

   Complete installation before continuing.
3. Open Terminal in the extracted project folder. Quit an existing HyperMac instance, then run:

   ```sh
   bash scripts/setup-local-signing.sh
   bash scripts/build.sh
   ```

   The setup script creates a signing certificate in your login Keychain. Authenticate directly in macOS if prompted. Keep this identity for future updates; do not share its private key.
4. The build script installs and opens the app, using `/Applications` or `~/Applications`. Keep the app in that location.
5. Open **System Settings → Privacy & Security → Accessibility**. Add the installed HyperMac app and enable its switch. HyperMac's General tab shows the exact installed path if needed.

Automatic tiling is enabled by default for new configurations. Existing settings are preserved. Screen Recording permission is not requested.

### Update an existing installation

Download the updated source, quit HyperMac, and run `bash scripts/build.sh` from the new project folder. Reuse the signing identity on that Mac. The installer checks signing continuity; do not delete the certificate or regenerate it for each update.

## Your first workspace

Open HyperMac from Applications to show its settings, or use its menu-bar controls.

| Tab | Use it for |
| --- | --- |
| **General** | Enable or pause tiling, choose its algorithm and gaps, customize borders and transitions, exclude apps, and capture an arrangement. |
| **Shortcuts** | Search/filter actions, record a key combination, and choose an app or layout. Valid changes save automatically. |
| **Layouts** | Create, preview, duplicate and edit saved arrangements across displays. |
| **Displays** | Inspect connected displays and configure automatic monitor profiles. |

To leave an app floating, add it under **General → Floating apps** with the Applications picker. To adjust a split with your mouse, use automatic **Dynamic splits** and drag a window's native edge or corner. App minimum sizes still apply.

### Automatic, saved layout, or paused

- **Automatic:** eligible visible windows share their current display. Dynamic splits expands neighboring windows as others close.
- **Saved layout:** each screen uses its selected mode. Automatic tiles includes all eligible local windows; Tile saved apps includes matching apps; Custom positions uses authored rectangles. Horizontal scroll can include saved apps and other eligible local windows. Matching saved apps move to their assigned screens when applied. Closed apps are not launched by a layout containing horizontal scrolling; other saved layouts may launch them once. Reflow does not relaunch an app you close.
- **Paused:** HyperMac stops scheduling arrangements and hides its borders. A movement already in progress may finish.

### Create a layout

1. In **Layouts**, choose **New layout**, or arrange your windows manually and use **General → Capture visible windows**.
2. Click a screen card and choose its **Screen mode**. **Automatic tiles** manages all eligible windows; **Tile saved apps** adjusts only matching apps; **Custom positions** uses editable rectangles; **Leave unchanged** skips that screen.
3. Add apps to that screen from the library. In Custom positions, move or resize their rectangles and use **Snap 5%** for alignment. Select another screen to configure it independently.
4. Choose **Preview & apply**, review each screen’s mode and planned windows, then **Apply layout**. Matching saved apps move to their assigned screens; unlisted windows remain on their current displays.

A monitor warning beside an app means its assigned display is unavailable. Select a connected display, choose **Use primary display**, or reconnect the original monitor. Primary-display fallback can make fixed rectangles overlap if multiple displays are redirected to one.

Valid layout edits and duplicates save automatically. **Preview & apply** switches the active arrangement. **Undo arrangement / Redo** restores one level of window geometry. Ordinary geometry restoration pauses tiling; restoring a saved horizontal session resumes its scrolling layout when it is still available. It does not undo editor changes, close launched apps, or reopen closed windows. History clears on restart or a new layout application.

### Horizontal columns

Choose **Horizontal** in Layouts, then click its display card under **Choose a screen** and choose **Screen mode → Horizontal scroll**. Drop a card onto another to stack, or expand **Screen overview** to drag rectangles sideways to reorder and into another rectangle’s lower third to stack. Resize with the corner/column handle or select an app and choose a saved width, including **Full width**.

Each screen has its own app rules, order and groups. Choose each display card and set its **Screen mode** independently: **Horizontal scroll**, **Automatic tiles**, **Tile saved apps**, **Custom positions**, or **Leave unchanged**. New layouts leave every screen unchanged until configured. Other screens keep their own windows. **Neighbor space** reserves room beside wide columns; full width fills the remaining area after these margins and gaps.

Enable **Hyper + scroll** to step through columns with the mouse/trackpad. One gesture advances one column; momentum is ignored. This is discrete navigation, not continuous finger-following scrolling. With monitors beside one another, macOS prevents clipping live windows at their shared edge: navigation currently switches instantly and that edge may not show a neighbor. [Controls and limitations](docs/SCROLLING.md), [upstream design review and remaining work](docs/SCROLLING-DESIGN-REVIEW.md).

### Automatically switch when docking

In **Displays → Automatic monitor profiles**, connect the desired monitors, add that setup, and choose a saved layout. Valid edits save automatically. Repeat for your other setups. Profiles match the exact set of connected display IDs and apply at startup or when that set changes. Different docks or display connections may require a new profile.

## Keyboard shortcuts

Defaults adapt Omarchy-style window and app controls to macOS:

- **Base:** Control + Option + Command
- **Hyper:** Control + Option + Command + Shift

| Shortcut | Default action |
| --- | --- |
| Base + arrow | Focus a window in that direction |
| Hyper + arrow | Swap windows in that direction |
| Hyper + H / L | Focus the previous / next horizontal column |
| Base + Return | Open a terminal |
| Hyper + Return or B | Open the default browser |
| Hyper + F | Open Finder |
| Hyper + N | Open an editor |
| Hyper + A | Open ChatGPT, falling back to Codex |
| Base + F | Maximize / restore |
| Base + minus / equal | Grow / shrink width |
| Hyper + minus / equal | Shrink / grow height |
| Base + T | Toggle tiling |
| Base + R | Retile |

The **Shortcuts** tab lists all bindings and lets you change launch targets. Click the current key combination and press your new combination; valid edits save automatically. Escape cancels recording. Conflicts stay unsaved with an error. Some macOS or third-party shortcuts can intercept a combination. Key mapping currently follows physical US/ANSI positions; non-US keyboard legends may differ.

## Troubleshooting

**Windows do not move:** check Accessibility permission, confirm tiling is active, and check the Floating apps list. Exit native fullscreen. Standard, movable and resizable windows are supported; dialogs and unusual app windows may be skipped.

**A window will not fit:** some apps enforce minimum sizes. Reduce gaps, use fewer windows on that display, or leave that app floating. The status footer reports verified placements and constraints.

**An update loses Accessibility access:** confirm System Settings points to the installed copy. If necessary, remove the stale entry and add that same installed app again. Preserve the local signing identity across builds.

**Two tools keep moving windows:** pause the other window manager while using HyperMac. Stage Manager and other tilers can compete for window positions.

**Movement is not perfectly smooth:** HyperMac uses macOS Accessibility calls, and individual apps can respond at different speeds. Adjust transition duration in General, or set it to zero. Compositor-level animation smoothness is not guaranteed.

Use **Copy troubleshooting report** and include the report, macOS version, app version and reproduction steps in a [GitHub issue](https://github.com/c0dewars/HyperMac/issues). Review reports and screenshots for personal information before sharing them. See [security guidance](SECURITY.md) for sensitive reports.

## Settings and removal

Settings are stored locally at `~/.config/hypermac/config.json`. Back up this file before manual edits. [The example configuration](examples/config.json) shows the format. Display-specific layouts may need adjustment when copied to another Mac. There is no automatic settings sync.

To uninstall, quit HyperMac, remove its installed app from Applications, and remove its Accessibility entry. You can keep the configuration and signing identity for a future reinstall. Delete them only if you no longer need your settings or signing continuity.

## Development and validation

Build and test on a Mac with full Xcode selected:

```sh
bash scripts/build.sh --test --build-only --ad-hoc
```

Package the Apple Silicon test app as a preview DMG:

```sh
bash scripts/build.sh --build-only --ad-hoc
bash scripts/package-dmg.sh
```

The output is `dist/HyperMac.app`. This ad-hoc test bundle is not a notarized release, and the normal installer refuses it.

[GitHub Actions](https://github.com/c0dewars/HyperMac/actions) runs unit tests, lifecycle/geometry regressions, native builds and bundle checks on Apple Silicon. Automated checks do not replace real-window and clean-machine testing.

See [test coverage and limitations](TEST-RESULTS.md), [release readiness](RELEASE-READINESS.md), [remaining fixes](docs/KNOWN-ISSUES.md), and [security](SECURITY.md). Native integration, docking, Spaces/fullscreen, performance and distribution validation remain incomplete.

HyperMac has its own native implementation. Its interaction design is inspired by Omarchy, yabai and JankyBorders; those projects are not bundled or required.

See [the responsiveness analysis](PERFORMANCE.md) for measured planning costs, implemented fixes, remaining bottlenecks and the live validation plan.
