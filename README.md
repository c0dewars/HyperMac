<p align="center">
  <img src="Resources/AppIcon.png" width="112" alt="HyperMac icon">
</p>

# HyperMac

**A place for every window.**

HyperMac is a native macOS window manager that automatically arranges your apps, saves layouts for different setups, and puts window controls and app launchers on customizable keyboard shortcuts.

> **0.8.0 build 34 · Development preview · Apple Silicon only.** Intel support has been retired. Clean-Mac installation and the full window-management compatibility matrix are still being validated. Preview DMGs are ad-hoc signed; there is **no notarized production release**. See [release readiness](RELEASE-READINESS.md) for the remaining work.

```sh
brew install --cask c0dewars/tap/hypermac
```

Then grant Accessibility permission. See [Install](#install) for first-launch details.

## Normal layouts, per display

Horizontal scrolling has been removed. Each display has independent ordinary tiling or custom positions. The settings window is larger, uses a native macOS toolbar, and remembers its size and position.

Older scrolling layouts migrate to normal tiling while retaining their names, apps, screen assignments and exclusions. A dated/unique `config.before-normal-layouts-*.json` backup is saved beside the configuration before migration. Obsolete column shortcuts are removed; customized ordinary shortcuts stay intact.

![HyperMac 0.8.0 feature tour](docs/media/hypermac-feature-tour.gif)

A 49.5-second screenshot tour of the redesigned settings, per-display normal layouts, custom positions and shortcut recorder. Live window transitions are not demonstrated. [Screenshots and static poster](docs/media/README.md).

## What you can do

- **Tile automatically:** opening, closing, minimizing or restoring eligible windows redistributes available space. Dynamic splits is the default for new configurations.
- **Keep selected apps floating:** choose apps from Applications in the exclusions list. System Settings is excluded by default.
- **Customize borders and transitions:** light-green borders by default, adjustable width and color, and eased movement that respects Reduce Motion.
- **Start with one Normal preset:** your default browser, VS Code and Teams share their display. Choose different apps from Applications.
- **Create saved layouts:** drag apps onto monitor previews, resize their rectangles, duplicate layouts, or capture your current arrangement.
- **Use adaptive layouts:** let the open windows listed in a saved layout share the available space.
- **Undo and redo an arrangement:** restore one previous arrangement of surviving windows.
- **Edit shortcuts:** search or filter a compact list, click a key combination to record it, and expand a row to change its action. Conflicting combinations are rejected.
- **Adjust settings immediately:** valid changes save automatically; appearance controls apply without retiling. Blur has a complete Off switch and a 0–100% intensity slider.
- **Remove layout apps:** use the minus control beside a selected app, or Remove app in its inspector. Tile all windows also supports per-display exclusions.
- **Switch layouts when docking:** save monitor profiles for your connected display setups.
- **Resize with the mouse:** in automatic Dynamic splits mode, drag a normal window edge or corner to adjust neighboring tiles when you release it.

## Install

```sh
brew install --cask c0dewars/tap/hypermac
```

Then:

1. Open **HyperMac** from Applications. It is a development preview that is ad-hoc signed, not notarized. If macOS says it **cannot verify the developer**, use **System Settings → Privacy & Security → Open Anyway** for HyperMac if you choose to trust it. See [Apple's instructions](https://support.apple.com/102445). Do not disable Gatekeeper globally.
2. Open **System Settings → Privacy & Security → Accessibility** and enable HyperMac so it can move and resize windows. HyperMac's General tab shows the installed path if needed.
3. HyperMac runs in the menu bar. Click its icon to open Settings.

Automatic tiling is enabled by default for new configurations. Existing settings are preserved. Screen Recording permission is not requested.

### Update or uninstall

```sh
brew upgrade --cask hypermac
```

Each preview is ad-hoc signed, so macOS may drop Accessibility permission after an upgrade. If windows stop moving, remove HyperMac from the Accessibility list and add it again.

```sh
brew uninstall --cask hypermac
```

Add `--zap` to also delete your settings in `~/.config/hypermac`. Remove the Accessibility entry manually.

### Requirements

- macOS **14 or later**, on **Apple Silicon (M1 or newer)**. This is the declared minimum; not every supported macOS version has been tested.
- [Homebrew](https://brew.sh).
- Accessibility permission.

Karabiner-Elements is optional. If you already map Caps Lock to Hyper, that mapping works with HyperMac's Hyper shortcuts.

### Manual download

Each [GitHub release](https://github.com/c0dewars/HyperMac/releases) includes the Apple Silicon DMG and its SHA-256 checksum. Open the DMG, drag HyperMac to Applications, then follow the steps above. See the [remaining checks](docs/KNOWN-ISSUES.md) before relying on it for daily use, and [Distribution](docs/DISTRIBUTION.md) for sharing a preview with friends.

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
- **Saved layout:** each screen uses Tile all windows, Tile selected apps, Custom positions or Leave unchanged. Matching selected apps move to their assigned screens. Apply launches missing configured apps once; closing an app does not relaunch it during reflow. Minimized, hidden and native-fullscreen windows are left alone.
- **Paused:** HyperMac stops scheduling arrangements and hides its borders. A movement already in progress may finish.

### Create a layout

1. In **Layouts**, choose **New layout**, or arrange your windows manually and use **General → Capture visible windows**.
2. Click a screen card and choose its **arrangement**. **Tile all windows** manages all eligible windows; **Tile selected apps** adjusts only matching apps; **Custom positions** uses editable rectangles; **Leave unchanged** skips that screen.
3. Add apps to that screen from the library. In Custom positions, move or resize their rectangles and use **Snap to 5% grid** for alignment. Select another screen to configure it independently.
4. Choose **Preview & apply**, review each screen’s mode and planned windows, then **Apply layout**. Matching saved apps move to their assigned screens; unlisted windows remain on their current displays.

Rules for disconnected monitors appear under **Apps assigned to disconnected displays**. Reconnect that screen, move a rule to a connected display, or remove it. Layouts use physical display IDs by default. Advanced matching also supports portable `primary`, `built-in` and `external-N` roles. An explicit physical display mode wins over a role.

**Layout options → New or unassigned displays** controls monitors added later: leave them unchanged or tile all their windows. Missing-display fallback is off for new layouts. Enabling it deliberately redirects missing rules to the primary display; custom rectangles may then overlap.

Valid edits save automatically and update an active layout. **Preview & apply** uses the same screen assignment and placement planner as the runtime; it refuses to apply an out-of-date display preview. **Undo arrangement / Redo** restores one level of surviving window geometry and pauses tiling. It does not undo editor changes, close launched apps, or reopen closed windows. History clears on restart or a new layout application.

### Automatically switch when docking

In **Displays → Automatic monitor profiles**, connect the desired monitors, add that setup, and choose a saved layout. Valid edits save automatically. Repeat for your other setups. Profiles match the exact set of connected display IDs and apply at startup or when that set changes. Different docks or display connections may require a new profile.

## Keyboard shortcuts

When HyperMac is active, **Command + ,** opens Settings and **Command + Q** quits the app. These standard application shortcuts also appear in its menu-bar menu; they are separate from the configurable global window-management shortcuts below.

Defaults adapt Omarchy-style window and app controls to macOS:

- **Base:** Control + Option + Command
- **Hyper:** Control + Option + Command + Shift

| Shortcut | Default action |
| --- | --- |
| Base + arrow | Focus a window in that direction |
| Hyper + arrow | Swap windows in that direction |
| Hyper + H / L | Focus the nearest window to the left / right |
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

**An update loses Accessibility access:** confirm System Settings points to the installed copy in Applications. Remove the stale entry and add the installed app again.

**Two tools keep moving windows:** pause the other window manager while using HyperMac. Stage Manager and other tilers can compete for window positions.

**Movement is not perfectly smooth:** HyperMac uses macOS Accessibility calls, and individual apps can respond at different speeds. Adjust transition duration in General, or set it to zero. Compositor-level animation smoothness is not guaranteed.

Use **Copy troubleshooting report** and include the report, macOS version, app version and reproduction steps in a [GitHub issue](https://github.com/c0dewars/HyperMac/issues). Review reports and screenshots for personal information before sharing them. See [security guidance](SECURITY.md) for sensitive reports.

## Settings and removal

Settings are stored locally at `~/.config/hypermac/config.json`. Back up this file before manual edits. [The example configuration](examples/config.json) shows the format. Display-specific layouts may need adjustment when copied to another Mac. There is no automatic settings sync.

To uninstall, run `brew uninstall --cask hypermac` (or delete the app from Applications) and remove its Accessibility entry. Your configuration stays unless you use `--zap` or delete `~/.config/hypermac`.

## Development and validation

Build on an Apple Silicon Mac with full Xcode selected. Command Line Tools alone can't compile the SwiftUI settings window on recent SDKs.

```sh
bash scripts/build.sh --test
```

The output is an ad-hoc signed `dist/HyperMac.app`. Package it as a preview DMG with:

```sh
bash scripts/package-dmg.sh
```

Releases are built by **Actions → Apple Silicon preview DMG → Run workflow** with **Publish an unnotarized prerelease** enabled on `main`. Afterwards, bump `version` and `sha256` in [`Casks/hypermac.rb`](https://github.com/c0dewars/homebrew-tap/blob/main/Casks/hypermac.rb) in the tap. See [Distribution](docs/DISTRIBUTION.md#publish-a-homebrew-update).

[GitHub Actions](https://github.com/c0dewars/HyperMac/actions) runs unit tests, lifecycle/geometry regressions, native builds and bundle checks on Apple Silicon. Automated checks do not replace real-window and clean-machine testing.

See [test coverage and limitations](TEST-RESULTS.md), [release readiness](RELEASE-READINESS.md), [remaining fixes](docs/KNOWN-ISSUES.md), and [security](SECURITY.md). Native integration, docking, Spaces/fullscreen, performance and distribution validation remain incomplete.

HyperMac has its own native implementation. Its interaction design is inspired by Omarchy, yabai and JankyBorders; those projects are not bundled or required.

See [the responsiveness analysis](PERFORMANCE.md) for measured planning costs, implemented fixes, remaining bottlenecks and the live validation plan.
