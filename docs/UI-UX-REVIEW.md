# Settings review — normal layouts

8 October 2026 · HyperMac 0.8.0 build 34

## Changes

- **Native navigation:** an AppKit preferences toolbar replaces the custom tab buttons. The current category is visibly selected. Standard Settings/Quit shortcuts are preserved; Window adds Close, Minimize and Zoom.
- **Window sizing:** a 1360 × 940-point default content size is constrained to the current screen. The default is applied after SwiftUI hosting, which otherwise shrank the window. Resizing is remembered. Content scrolls within each category.
- **Hit areas:** screen cards and app rows define rectangular hit regions covering their padding. Action icons have explicit 24-point content areas inside native bordered controls. Icon-only actions have accessibility names and help.
- **Per-display editing:** one selected physical display, four plain-language modes, a visible monitor diagram in app-based modes, and a separate section for disconnected rules. Unassigned displays have an explicit default policy.
- **Editing and feedback:** empty layouts are valid drafts, app selection comes from Applications, incomplete shortcuts remain visibly unsaved, valid changes autosave, and deletion explains its effects on shortcuts/profiles. Native confirmation protects layout deletion.
- **Preview:** uses the same planner as Apply, captures the requested layout and displays, and rejects a changed display topology. Read-only preview does not move windows.
- **Appearance:** retains cyan accents from the icon with system typography, colors, forms and controls. Border colors have an explicit reset to the global default. Blur retains its Off switch and intensity setting. Effects are scoped to managed windows.

## Checks

Native UI validation confirmed toolbar navigation; clicking New layout on padding rather than text; app addition/removal; custom-position resize from 50% × 100% to 70% × 80%; a drag saving x=25%; duplication/deletion; recorder start and Escape cancellation; and autosave. The corrected 1360-point window width was visually verified, and Command-W/Command-comma closed/reopened Settings. Both external config save styles reloaded successfully. Temporary layouts were removed. Live tiling/other-app window tests remain paused.

Automated coverage and remaining device checks are recorded in [test results](../TEST-RESULTS.md) and [known issues](KNOWN-ISSUES.md). Full VoiceOver and every macOS text/display scaling combination remain manual acceptance checks.

## Apple references

The native preferences toolbar follows [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings). Standard controls and explicit hit areas follow [Buttons guidance](https://developer.apple.com/design/human-interface-guidelines/buttons); resizable windows and native interaction follow [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/). These changes are a review against that guidance, not an Apple certification.
