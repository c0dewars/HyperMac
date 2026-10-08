> Historical reference: horizontal scrolling was removed in 0.8.0. This document describes the previous implementation.

# Scrolling behavior review — 8 October 2026

The current horizontal layout is experimental. Verified final rectangles do not establish smooth movement. User reports of wrong-side arrivals, overlapping parked windows and extra wheel steps remain release-gating evidence.

## Upstream implementations reviewed

| Project | Relevant implementation | Lesson for HyperMac |
| --- | --- | --- |
| [Niri](https://github.com/niri-wm/niri/blob/2c82b77a7116a1241ea2fd41dd008ff00b609aae/src/layout/scrolling.rs) | `ViewOffset` separates static, animated and gesture states. `animate_view_offset_with_config` starts from the current offset and avoids restarting an unchanged target. Gesture end computes a landing column. | Own one viewport position and target per screen. Geometry, input and focus must not independently recenter it. Resume interrupted motion from the last rendered position. |
| [Niri gesture tracking](https://github.com/niri-wm/niri/blob/2c82b77a7116a1241ea2fd41dd008ff00b609aae/src/input/scroll_swipe_gesture.rs) | Distinguishes beginning, updating and ending an axis gesture. | A stream of wheel events is one interaction, not repeated unrelated keyboard commands. |
| [Hyprland scrolling tape](https://github.com/hyprwm/Hyprland/blob/5e04ae1f9fc44705799ed9c0f97b99a305c6db25/src/layout/algorithm/tiled/scrolling/ScrollTapeController.cpp) | A shared offset determines column positions. Fit/center operations update that offset; drag ownership prevents automatic recentering. | Use a single owner for motion and suspend automatic corrections during direct manipulation. |
| [Hyprland gesture handling](https://github.com/hyprwm/Hyprland/blob/5e04ae1f9fc44705799ed9c0f97b99a305c6db25/src/managers/input/trackpad/gestures/ScrollMoveGesture.cpp) | Tracks gesture start, updates, filtered velocity, cancellation and bounded final projection, then chooses focus at landing. | Keep focus transfer separate from moving the strip. Bound momentum instead of triggering repeated focus changes. |
| [PaperWM for GNOME](https://github.com/paperwm/PaperWM/blob/8bf6dd264f60d6c0c402b63df7b424b888959a48/tiling.js) | Uses a monitor-clipped container of window clones. During movement it hides the original actors, animates the container, then places and reveals real windows. | Its fluidity depends on rendering control. Merely copying its frame arithmetic into Accessibility calls cannot reproduce its clipping. |
| [PaperWM.spoon for macOS](https://github.com/mogenson/PaperWM.spoon/blob/82f5dde20d40cf1bdef18ab92b2b847f16f368a3/README.md#limitations) | Parks windows at visible margins because they cannot move entirely off-screen. Documents vertical monitor arrangement to avoid spilling onto adjacent screens. | The closest platform comparison has the same native-window edge limitation. Do not promise an isolated compositor viewport for arbitrary monitor arrangements. |

These are architecture references, not copied source. The macOS conclusions below are an assessment of HyperMac's existing Accessibility backend.

## Changes in build 26

- A phased Hyper-scroll gesture advances at most one column. Momentum events do not generate extra navigation. Unphased wheel events are grouped until a 250 ms quiet interval; precise scrolling has an 8-point intent threshold.
- Native focus/raise happens after placement, preventing activation of a parked destination before its transition. Rapid keyboard requests retain their intended target while delayed activation events arrive.
- Regression coverage includes long gestures, momentum, wheel bursts, cancellation/new gestures and interrupted repeated navigation with different widths and stacked rows.
- Per-display strip membership, app widths and groups remain independent. Normal and Floating modes are available on other screens.

This is a predictable discrete navigation mode, not Niri's continuous finger-following gesture. Real hardware gesture acceptance is still required.

## Required next architecture work

1. **One viewport controller per display:** explicit idle/keyboard/gesture/resize states; input changes the target, while a single frame scheduler owns position writes. Keep app size negotiations outside translation ticks.
2. **Bounded reconciliation:** distinguish window create/close and user resize from our own writes. Reconcile once after navigation settles; report uncooperative apps without a long correction loop.
3. **A consistent presentation policy:** live windows cannot be clipped to a shared display boundary by the current backend. Current behavior switches instantly on blocked-edge topologies. It must be clearly described, not presented as smooth scrolling.
4. **Acceptance on real input:** hold and alternate H/L, swipe slowly and quickly, reverse mid-transition, close the focused window and repeat, type immediately after navigation, then repeat with two screens and different widths/groups.

The user selected live windows rather than capture-based previews. That choice remains in force. No display rearrangement, Screen Recording grant or compositor substitute is part of this change. Swift is suitable for the state-machine work; a language rewrite would not provide missing window-rendering control.

## Stable-release decision

Local build 33 implements the first laptop-only transport changes: versioned per-display rendered frames, separate bounded native sizing, cached grid-rounded sizes, whole-point position writes and logical-distance edge ordering during transitions. It also suppresses unchanged-strip reflow caused by delayed own events. This is a foundation for the controller work above, not a continuous gesture controller or a compositor. The full live rerun is paused at the user's request; build 32 still exposed native width drift and 383–1042 ms command times in the retained seven-app sample.

**Hold.** The requested visual behavior on side-by-side screens is not achieved by the current native-window projection. Keep the build local while improving and validating it. Do not publish a stable tag or label this GIF as evidence of animation quality.
