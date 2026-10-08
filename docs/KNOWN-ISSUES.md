# Remaining validation for normal layouts

Status: **0.8.0 build 34, local only, 8 October 2026**. Horizontal scrolling and its navigation, off-screen parking, column grouping and width controls have been removed. The historical scrolling test documents do not describe this build.

## Implemented

- Independent display modes: tile all windows, tile selected apps, custom positions, leave unchanged.
- One shared preview/runtime planner, physical monitor IDs, arbitrary external-N roles, explicit missing-display policy, and local-first matching for apps with windows on multiple displays.
- Lifecycle reflow without repeated writes for unchanged windows; bounded correction for app minimum sizes; no forced unconstrained fallback when tiles cannot fit.
- Larger resizable Settings window, native toolbar, full-row selection, larger icon controls, safe deletion bindings, autosave and per-screen exclusions.
- Horizontal configuration migration with a recoverable backup; custom names, apps, assignments, ordinary shortcuts and appearance settings retained.
- Border and blur effects limited to managed windows. Reduce Motion and Reduce Transparency honored.

## Checks still required

| Priority | Check | Acceptance |
| --- | --- | --- |
| P1 | Live lifecycle regression | Opening, closing, minimizing, hiding and restoring supported app windows reflows the correct display, with no repeated correction loop. Live window testing remains paused at the user's request. |
| P1 | Physical multiple-monitor validation | Laptop + Odyssey, display reconnect, main-display changes, rotation, scaling and additional monitors agree with preview/apply. Automated geometry coverage is not a substitute for hardware testing. |
| P1 | Clean second-Mac installation and upgrade | Downloaded DMG, per-app Open Anyway, Accessibility, launch and migration on supported Apple Silicon/macOS versions. |
| P2 | Mouse resize and rapid shortcut input | Native window edge drags update BSP neighbors; focus/swap/resize shortcuts remain responsive under rapid input. |
| P2 | Spaces, fullscreen, sleep/wake and energy | No lost windows, stale borders, excessive idle work or interference with dialogs and fullscreen apps. |

App minimum sizes can make an arrangement impossible. HyperMac reports that limitation; custom positions may intentionally overlap and should be reviewed in preview. macOS Accessibility cannot guarantee identical animation or resizing behavior in every app.

Builds remain **ad-hoc signed and unnotarized** under the no-paid-Apple-account distribution choice. The developer warning is expected; see [Distribution](DISTRIBUTION.md).
