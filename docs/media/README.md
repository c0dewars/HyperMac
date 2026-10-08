# HyperMac feature tour

Captured from HyperMac **0.6.2**, on Apple Silicon, on 8 October 2026.

![HyperMac feature tour](hypermac-feature-tour.gif)

This 65-second looping GIF is a **captioned screenshot walkthrough**, not a recording of window movement or a performance benchmark. Monitor profiles use a clearly labeled concept illustration: docking was not recorded. Undo/redo controls are shown, but history restoration is not demonstrated.

## Screenshot gallery

Screenshots show the actual app. Main-window title bars were cropped for presentation; app content was not retouched. The Applications picker sidebar was hidden before capture. Layout examples are unsaved demonstration drafts. The border color shown is a customized setting, not the default.

| Screenshot | Features |
| --- | --- |
| [General](screenshots/01-general.png) | Automatic tiling, algorithm, gaps, mouse resizing and transitions |
| [Borders and capture](screenshots/02-borders-capture.png) | Border appearance and capturing an arrangement |
| [Floating apps](screenshots/03-floating-apps.png) | Application exceptions |
| [Shortcuts](screenshots/04-shortcuts.png) | Customizable actions and app launchers |
| [Shortcut recorder](screenshots/05-shortcut-recorder.png) | Press a combination to record |
| [Application picker](screenshots/06-app-picker.png) | Choose an installed application |
| [Layout editor](screenshots/07-layouts.png) | App library, monitor canvas, snapping and quick positions |
| [Adaptive layout](screenshots/08-adaptive-layout.png) | Open-window adaptation, gaps and display fallback |
| [Arrangement preview](screenshots/09-preview.png) | Planned positions and missing-window warnings |
| [Duplicate layout](screenshots/10-duplicate-layout.png) | A separate draft copied from an existing layout |

![Interface gallery](overview.png)

## Rebuild

Install Pillow in your Python environment, then run from the repository root:

```sh
python3 scripts/build-media.py
```

This regenerates the GIF, poster and overview from the checked-in screenshots. It does not control the app, modify settings or publish anything.
