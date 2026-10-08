# HyperMac 0.8.0 feature tour

Captured from installed **0.8.0 build 34** on Apple Silicon, on 8 October 2026.

![HyperMac normal-layout and keyboard-shortcut tour](hypermac-feature-tour.gif)

This 49.5-second looping GIF contains nine captioned scenes from the actual app. It is a **screenshot walkthrough**, not a recording or benchmark of window movement. Tiling was paused during capture. The earlier four-window preview was captured on the same build; no layout was applied for the tour.

The tour covers ordinary per-display layouts, selected-app templates, editable custom positions, preview, blur and borders, searchable shortcuts and the recorder. Docking, undo/redo restoration, actual mouse-driven window tiling and live multi-display transitions are not demonstrated.

## Current screenshots

The app content and control states have not been retouched. The blur scene crops the General screenshot to enlarge its appearance controls. App choices, bindings, colors and timings shown here are customized settings, not defaults. The temporary “Workspace demo” copy was removed after capture, and the saved user configuration was verified unchanged byte for byte.

| Screenshot | Features |
| --- | --- |
| [General](screenshots/30-general-080.png) | Native toolbar, tiling controls, gaps, transitions, focus borders and blur intensity |
| [Shortcuts](screenshots/31-shortcuts-080.png) | Search, categories, app launchers, edit and removal controls |
| [Directional focus](screenshots/32-focus-shortcuts-080.png) | Search for focus; Hyper+H/L and directional bindings |
| [Recorder](screenshots/33-recorder-080.png) | Press a combination; Escape cancels |
| [Per-display layouts](screenshots/34-layouts-080.png) | Screen card and independent arrangement mode |
| [Selected apps](screenshots/36-selected-apps-080.png) | Applications picker, app library, direct removal and adaptive template |
| [Custom positions](screenshots/37-custom-positions-080.png) | Editable rectangles, resize handle, grid, half-screen presets and app color |
| [Destination preview](normal-layout-preview-080.png) | Four open windows planned on the built-in display |
| [Current single-window preview](screenshots/35-preview-080.png) | Preview captured during this tour session |

![Interface gallery](overview.png)

[Static tour poster](tour-poster.png) · [User guide](../../README.md) · [Remaining acceptance checks](../KNOWN-ISSUES.md)

## Rebuild

With Python 3 and Pillow installed:

```sh
python3 scripts/build-media.py
```

The script regenerates the GIF, poster and gallery from checked-in captures. It does not operate the app, change settings or publish anything. Older numbered `01`–`28` screenshots remain as historical captures of 0.6.2/0.7.0; none are used by the current tour. Their horizontal scrolling controls were removed in 0.8.0.
