# Responsiveness audit — 5 October 2026

## Conclusion

Keep Swift/AppKit. The source contains avoidable scheduling and cross-process work that explains plausible sources of lag. There is no evidence that Swift arithmetic or layout planning requires a language migration. Dropping Intel simplifies builds and testing; it does not by itself accelerate the already-native arm64 app.

This is a source audit and a planning microbenchmark, not a completed Instruments trace or a claim of flawless native animation. Full Xcode/Instruments is unavailable on the development machine. The new runtime report includes discovery and total reconciliation time in milliseconds to support the next measurements.

## Findings and first fixes

| Path | Previous behavior | Change in 0.6.1 |
| --- | --- | --- |
| Open/close events | Every event restarted a 180 ms debounce, postponing work during bursts. | Coalesce at the first 30 ms deadline. Retain delayed discovery retries for late-publishing apps. |
| Focus shortcuts | Waited for the full automatic move/verify cycle. | Independent serialized focus task; superseded queued focus requests are canceled. AX calls still share the serial worker. |
| Verification | First successful placement always waited 150 + 100 ms after writes. Failed batches waited at least 1.35 s across three passes. | First verification after 40 ms; extra 100 ms only when an origin correction was issued. Longer bounded retries retained for slow apps/Finder. This is a scheduling reduction, not a measured end-to-end latency result. |
| Mouse resize | No resize event subscription or mouse-up trigger; often depended on the one-second reconciliation timer. | Resize events mark the active drag; mouse release schedules reflow. Timer remains a fallback if notifications are unavailable. |
| Animation | Each frame added 16.7 ms sleep *after* serial AX writes. | Subtract write time from the frame budget. Slow apps still limit actual frame rate. |
| Borders | Move/resize notifications and changed geometry triggered separate full AX discovery; existing panels were redrawn/reordered repeatedly. | Geometry-only events track WindowServer bounds, coalesced at 60 Hz; discovery remains for membership/order changes. Skip unchanged drawing and avoid reordering on every geometry tick. |
| Border transition timer | Ran at 60 Hz through verification and retries. | Runs only during the actual animated write phase. |

No SIP changes, screen-capture overlays, private WindowServer hooks or security-permission expansions were introduced.

## Planning microbenchmark

Command: `swiftc -O Sources/HyperMacCore/*.swift scripts/benchmark-tiling.swift -o /tmp/hypermac-benchmark && /tmp/hypermac-benchmark`.

10,000 repeated BSP plans, 3440×1440 logical area, 12-point gaps, no app constraints, local Apple Silicon:

| Windows | Mean planning time |
| --- | --- |
| 5 | 0.37 µs |
| 10 | 0.70 µs |
| 20 | 1.54 µs |

These numbers exclude window discovery, Accessibility IPC, rendering, event delivery, constraint fallback and display refresh. They do not establish interactive frame rate; they indicate that this pure planning path is not the hundred-millisecond delay seen in the control flow.

## Remaining work, in priority order

1. **One shared window registry.** The engine and borders still maintain separate AX discovery/observer infrastructure. Cache stable roles/capabilities and batch attribute reads. Invalidate on relevant events; refresh only affected apps. Keep a slow watchdog for missed notifications.
2. **Latest-target movement with cancellation.** Focus no longer waits for verification, but geometry commands still queue behind in-flight moves. Add generation-aware cancellation between AX operations and verification passes, with a fresh geometry read before a superseding plan. A pause or new layout must not allow old corrections to overwrite it. Test these races before deployment.
3. **Per-app latency isolation.** Current AX timeouts are up to 500 ms per call, with several calls per window. A stalled client can block the shared worker. Measure per-app times, batch attributes, and consider bounded workers per PID while preserving order within each app. Do not simply shorten all timeouts and silently drop windows.
4. **Move observer registration off the main thread.** Both observer systems perform synchronous registration/removal on the UI run loop. Use a dedicated run loop and explicit ownership/lifetime rules. Resolve the existing Swift Sendable warning through ownership design, not an unchecked annotation alone.
5. **Live resize pipeline.** This release adjusts neighbors on mouse release. For continuous neighboring resize, sample the dragged window within a bounded frame budget, skip animations while dragging, and distinguish app/user motion from HyperMac's writes. Do not send repeated sizes to all apps every display frame.
6. **Display-paced rendering.** Consider display-linked border updates and per-app animation budgets after profiling. If public AX cannot sustain the target rate, explore an optional visual snapshot animation backend separately, with explicit Screen Recording permission and accessibility/occlusion tradeoffs.

Rewriting the whole UI/engine in Rust/C++ would preserve the same macOS IPC delays and add migration risk. A small lower-level helper only becomes justified if profiling identifies work Swift cannot handle efficiently, or a separately reviewed backend requires it.

Hyprland owns its compositor; HyperMac requests geometry changes from independent applications. Those control models do not offer the same timing guarantees. Yabai's documented animated-window path requires Screen Recording and partially disabled SIP; matching it is not simply a choice of language. Source: [yabai manual](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc#configuration).

## Acceptance measurements before claiming smoothness

On a locally signed Apple Silicon build, with the user's configuration backed up:

- Repeat open → close, minimize → restore and hide → unhide 30 times with 2, 5 and 10 windows. Record event-to-first-write and event-to-settled p50/p95, retries and overlaps.
- Hold focus shortcuts during an active transition and while one app is unresponsive. Verify final focus, ordering, and no stale queue continuing after release.
- Drag each split edge rapidly, including while opening/closing another window. Verify no movement while held, neighbor adjustment on release, and no snap-back.
- Inspect all border edges during focus, movement, resize, occlusion, fullscreen and monitor disconnects.
- Profile main-thread stalls, AX call durations, WindowServer work and energy at idle/60 Hz/120 Hz. Timing diagnostics currently cover discovery and total pass duration only; event/first-write timestamps and frame pacing traces remain to add.
- Repeat on minimum-supported and current macOS, with multiple displays and apps that constrain their window size.

Target budgets (acceptance goals, not achieved results): event-to-first-write p95 under 50 ms for responsive apps; no avoidable main-thread work over one display frame; no unbounded geometry/focus queue; no repeated writes at idle. Separate slow-app outcomes from scheduling regressions.

## GitHub build/release finding

GitHub had one historical compiler failure (`37139537420`), followed by successful runs including main (`37142729012`). No release workflow or release assets existed at audit time. Version 0.6.1 adds an Apple Silicon-only preview DMG workflow: manual build artifacts, optional prerelease publication from main, checksums, and explicit unnotarized labeling. Production Developer ID signing/notarization remains a separate release blocker. The repository remains private.
