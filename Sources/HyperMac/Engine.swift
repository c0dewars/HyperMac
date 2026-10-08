import AppKit
import ApplicationServices
import HyperMacCore

struct ArrangementPreview {
    var placements: [Placement]
    var messages: [String]
    var count: Int
    var totalCount: Int? = nil
}

@MainActor
final class Engine {
    enum Mode: Equatable { case paused, automatic, layout(String) }
    var config: Configuration
    private(set) var mode: Mode = .paused { didSet { onModeChange?(mode != .paused) } }
    var onTransition: ((Bool) -> Void)?
    var onModeChange: ((Bool) -> Void)?
    private let accessibility = Accessibility()
    private let events = WindowEvents()
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pending: DispatchWorkItem?
    private var reconciliationTimer: Timer?
    private struct ScrollingState {
        var session = ScrollingSession()
        var focus = ScrollingFocus()
        var lastFocus: Int?
        var frames: [Int: Rect] = [:]
        var parked: Set<Int> = []
        var visible: Set<Int> = []
    }
    private var scrollingStates: [String: ScrollingState] = [:]
    private var navigationDisplayID: String?
    private var scrollingOriginal: [Int: Rect] = [:]
    private var scrollRestorePending = false
    private var partialScrollRestore: Set<Int> = []
    private var assignmentSeenWindows: Set<Int> = []
    private var assignmentMatches: [Int: Int] = [:]
    private var pendingDestinations: [Int: String] = [:]
    private var assignmentAttempts = 0

    private func resetAssignments() {
        assignmentSeenWindows = []; assignmentMatches = [:]
        pendingDestinations = [:]; assignmentAttempts = 0
    }

    private func planningLayout(_ layout: Layout, windows: [ManagedWindow], displays: [Display]) -> Layout {
        LayoutAssignments.localized(layout, windows: windows.map(\.descriptor), displays: displays, matches: assignmentMatches)
    }

    private func assignedWindows(_ windows: [ManagedWindow], layout: Layout, displays: [Display]) -> ([ManagedWindow], [String]) {
        let live = Set(windows.map { $0.descriptor.id })
        assignmentSeenWindows.formIntersection(live)
        assignmentMatches = assignmentMatches.filter { live.contains($0.value) }
        pendingDestinations = pendingDestinations.filter { live.contains($0.key) }
        var messages: [String] = []
        if !live.subtracting(assignmentSeenWindows).isEmpty {
            let plan = LayoutAssignments.plan(layout, windows: windows.map(\.descriptor), displays: displays)
            for (index, id) in plan.matches where !assignmentSeenWindows.contains(id) {
                assignmentMatches[index] = id
                pendingDestinations[id] = plan.destinations[id]
            }
            messages = plan.messages
            assignmentSeenWindows.formUnion(live)
            assignmentAttempts = 0
        }
        let projected = LayoutAssignments.projected(windows.map(\.descriptor), destinations: pendingDestinations, displays: displays)
        return (zip(windows, projected).map { window, descriptor in
            ManagedWindow(element: window.element, descriptor: descriptor, pid: window.pid, windowNumber: window.windowNumber)
        }, messages)
    }
    private var focusInputMonitor: Any?
    var onParkedWindows: ((Set<Int>) -> Void)?
    private var scrollingLayout: Layout? {
        guard case .layout(let name) = mode else { return nil }
        return config.layouts.first { $0.name == name && $0.scrolling != nil }
    }
    private func usesAutomaticTiling(on screen: Display, displays: [Display]) -> Bool {
        if mode == .automatic { return true }
        guard let layout = scrollingLayout else { return false }
        return ScrollingSession.mode(on: screen, layout: layout, displays: displays) == "normal"
    }
    private func otherDisplayPlan(_ windows: [ManagedWindow], layout: Layout, displays: [Display]) -> LayoutPlan {
        var result = LayoutPlan()
        let layout = planningLayout(layout, windows: windows, displays: displays)
        for screen in displays {
            if LayoutScreens.mode(on: screen, layout: layout, displays: displays) == .normal {
                result.moves += automaticMoves(windows.filter { Displays.containing($0.descriptor.frame, in: displays)?.id == screen.id },
                    screen: screen, gap: layout.applyGap ? config.gap : 0)
            } else {
                let template = LayoutScreens.templatePlan(on: screen, layout: layout, windows: windows.map(\.descriptor),
                    displays: displays, gap: config.gap, minimumSizes: minimumSizes)
                result.moves += template.moves
                result.messages += template.messages
            }
        }
        return result
    }
    private func planScrolling(_ layout: Layout, windows: [ManagedWindow], displays: [Display], focused: Int?) -> (ScrollingPlan, ScrollingMotion?) {
        let layout = planningLayout(layout, windows: windows, displays: displays)
        var combined = ScrollingPlan()
        var motions: [ScrollingMotion] = []
        let targets = ScrollingSession.targets(layout: layout, displays: displays)
        let liveScreens = Set(targets.map(\.id))
        scrollingStates = scrollingStates.filter { liveScreens.contains($0.key) }
        for screen in targets {
            var state = scrollingStates[screen.id] ?? ScrollingState()
            let localLayout = ScrollingSession.layout(layout, on: screen, displays: displays)
            let localIDs = Set(windows.filter { Displays.containing($0.descriptor.frame, in: displays)?.id == screen.id }.map { $0.descriptor.id })
            let localFocus = state.focus.resolve(observed: focused, live: localIDs, fallback: state.session.strip.focused)
            let plan = state.session.plan(layout: localLayout, windows: windows.map(\.descriptor), displays: displays,
                gap: config.gap, focused: localFocus, minimumSizes: minimumSizes)
            motions.append(ScrollingMotion(starts: state.frames, ends: plan.logicalFrames, screen: screen, displays: displays))
            state.frames = plan.logicalFrames; state.lastFocus = localFocus
            state.parked = plan.parked; state.visible = plan.visible
            scrollingStates[screen.id] = state
            combined.moves += plan.moves
            combined.logicalFrames.merge(plan.logicalFrames) { _, new in new }
            combined.parked.formUnion(plan.parked); combined.visible.formUnion(plan.visible)
            combined.messages += plan.messages.map { screen.name + ": " + $0 }
        }
        for screen in displays where ScrollingSession.mode(on: screen, layout: layout, displays: displays) == "horizontal" && !liveScreens.contains(screen.id) {
            combined.messages.append("\(screen.name): no safe outside edge; windows on this display were left unchanged.")
        }
        return (combined, motions.isEmpty ? nil : ScrollingMotion(parts: motions))
    }
    private func updateParkedWindows(_ windows: [ManagedWindow]) {
        let parked = scrollingStates.values.reduce(into: Set<Int>()) { $0.formUnion($1.parked) }
        onParkedWindows?(Set(windows.filter { parked.contains($0.descriptor.id) }.compactMap(\.windowNumber)))
    }
    private var splitTrees: [String: BSPTree] = [:]
    private var minimumSizes: [Int: Rect] = [:]
    private var settledFrames: [Int: Rect] = [:]
    private var settledGeneration = -1
    private var placementVerified = false
    private var placementRetries = 0
    private var undoScroll: (name: String, states: [String: ScrollingState])?
    private var redoScroll: (name: String, states: [String: ScrollingState])?
    private var undoWindows: [ManagedWindow] = []
    private var redoWindows: [ManagedWindow] = []
    var canRedo: Bool { !redoWindows.isEmpty }
    private var profileTask: Task<Void, Never>?
    private var lastTopology: [String]?
    private var mouseWasDown = false
    private var mouseDropPoint: CGPoint?
    private var scrollMonitor: Any?
    private var scrollingGesture = ScrollingGesture()
    private var mouseReleaseMonitor: Any?
    private var focusCommand: Task<Void, Never>?
    var canUndo: Bool { !undoWindows.isEmpty }
    private var arrangementRequest = 0
    private var lastTargets: [Int: Rect] = [:]
    private var busy = false
    private var dirty = false
    private var generation = 0
    private var launchTask: Task<Void, Never>?
    private var discoveryRetry: Task<Void, Never>?
    private var windowCommand: Task<Void, Never>?
    private var pendingWindowCommands = 0
    private struct NavigationIntent {
        var shortcut: Shortcut
        var displayID: String?
    }
    private var pendingNavigation: NavigationIntent?
    private var navigationWorker: Task<Void, Never>?
    private var activeNavigation: Task<Void, Never>?
    private var navigationHistory: [String] = []
    private var maximizedFrames: [Int: Rect] = [:]
    private var latestDiagnosticReport = "No tiling/layout operation has run yet."
    var diagnosticReport: String {
        get { latestDiagnosticReport + (navigationHistory.isEmpty ? "" : "\nRecent navigation (oldest first):\n" + navigationHistory.joined(separator: "\n")) }
        set { latestDiagnosticReport = newValue }
    }
    var onStatus: ((String) -> Void)?

    init(config: Configuration) { self.config = config }

    func start() {
        events.onChange = { [weak self] in self?.windowEvent() }
        events.onResize = { [weak self] in
            guard let self, self.config.mouseResize,
                  (self.scrollingLayout != nil || (self.mode == .automatic && self.config.algorithm == .bsp)), NSEvent.pressedMouseButtons & 1 != 0 else { return }
            self.mouseWasDown = true
        }
        mouseReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mouseWasDown else { return }
                let point = NSEvent.mouseLocation
                self.mouseDropPoint = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
                self.schedule()
            }
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hyper = flags.contains([.control, .option, .command, .shift])
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let phase: ScrollingGesture.Phase = event.phase.contains(.began) ? .began :
                event.phase.contains(.ended) ? .ended : event.phase.contains(.cancelled) ? .cancelled :
                event.phase.isEmpty ? .unphased : .changed
            let momentum = !event.momentumPhase.isEmpty
            let precise = event.hasPreciseScrollingDeltas
            let time = event.timestamp
            Task { @MainActor in
                guard let self else { return }
                guard hyper, self.scrollingLayout?.scrolling?.hyperScroll == true else {
                    self.scrollingGesture.reset(); return
                }
                guard let direction = self.scrollingGesture.consume(delta: delta, time: time, phase: phase,
                    momentum: momentum, precise: precise) else { return }
                self.run(Shortcut(key: "", action: .focusWindow, target: direction.rawValue))
            }
        }
        // Explicit mouse/keyboard activity releases navigation ownership. Delayed
        // AX activation notifications alone must never reverse a held H/L sequence.
        focusInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
                let isNavigation = event.type == .keyDown && self.config.shortcuts.contains { shortcut in
                    guard shortcut.action == .focusWindow, KeyMap.codes[shortcut.key.lowercased()] == UInt32(event.keyCode) else { return false }
                    var expected: NSEvent.ModifierFlags = []
                    for modifier in shortcut.modifiers {
                        switch modifier {
                        case "ctrl": expected.insert(.control)
                        case "alt": expected.insert(.option)
                        case "cmd": expected.insert(.command)
                        case "shift": expected.insert(.shift)
                        default: break
                        }
                    }
                    return flags == expected
                }
                if !isNavigation {
                    for id in self.scrollingStates.keys { self.scrollingStates[id]?.focus.userInteracted() }
                }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.windowEvent() }
            }
            notificationTokens.append((workspace, token))
        }
        let center = NotificationCenter.default
        let token = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleMonitorProfile() }
            }
        notificationTokens.append((center, token))
        mode = config.automaticTiling ? .automatic : .paused
        scheduleMonitorProfile()
        schedule()
        // AX notifications are best effort (including registration during app startup).
        // Recover missed create/close/minimize events without repeatedly writing geometry.
        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.needsReflow, !self.busy, self.pending == nil else { return }
                await self.reconcile(checkOnly: true)
            }
        }
    }

    func update(_ config: Configuration) {
        let activeLayoutChanged: Bool
        if case .layout(let name) = mode {
            activeLayoutChanged = self.config.layouts.first(where: { $0.name == name }) != config.layouts.first(where: { $0.name == name })
        } else { activeLayoutChanged = false }
        let affectsArrangement = self.config.automaticTiling != config.automaticTiling ||
            self.config.algorithm != config.algorithm || self.config.gap != config.gap ||
            activeLayoutChanged || self.config.excludedBundleIDs != config.excludedBundleIDs ||
            self.config.monitorProfiles != config.monitorProfiles
        guard affectsArrangement else { self.config = config; return }
        let changedDefault = self.config.automaticTiling != config.automaticTiling
        let profilesChanged = self.config.monitorProfiles != config.monitorProfiles
        if let active = scrollingLayout, config.layouts.first(where: { $0.name == active.name })?.scrolling == nil { scrollRestorePending = true }
        if scrollingLayout != nil, self.config.excludedBundleIDs != config.excludedBundleIDs { scrollRestorePending = true }
        if let active = scrollingLayout,
           config.layouts.first(where: { $0.name == active.name })?.scrolling?.excludedBundleIDs != active.scrolling?.excludedBundleIDs {
            scrollRestorePending = true
        }
        if activeLayoutChanged, let old = scrollingLayout {
            let screens = ScreenCatalog.current()
            let updated = config.layouts.first { $0.name == old.name }
            for (id, state) in scrollingStates {
                guard let screen = screens.first(where: { $0.id == id }), let updated else { continue }
                let previousLocal = ScrollingSession.layout(old, on: screen, displays: screens)
                let newLocal = ScrollingSession.layout(updated, on: screen, displays: screens)
                if ScrollingSession.mode(on: screen, layout: updated, displays: screens) != "horizontal" ||
                   previousLocal.scrolling?.excludedBundleIDs != newLocal.scrolling?.excludedBundleIDs {
                    partialScrollRestore.formUnion(state.session.strip.ids)
                }
            }
            scrollingStates = scrollingStates.filter { id, _ in
                guard let updated, updated.scrolling != nil, let screen = screens.first(where: { $0.id == id }) else { return false }
                return ScrollingSession.mode(on: screen, layout: updated, displays: screens) == "horizontal" &&
                    ScrollingSession.layout(old, on: screen, displays: screens) == ScrollingSession.layout(updated, on: screen, displays: screens)
            }
            if let id = navigationDisplayID, scrollingStates[id] == nil { navigationDisplayID = nil }
        }
        if activeLayoutChanged, case .layout(let name) = mode,
           let old = self.config.layouts.first(where: { $0.name == name }),
           let new = config.layouts.first(where: { $0.name == name }) {
            let oldRules = old.placements.map { [$0.bundleID, $0.display, $0.titleContains, String($0.windowIndex)] }
            let newRules = new.placements.map { [$0.bundleID, $0.display, $0.titleContains, String($0.windowIndex)] }
            if oldRules != newRules || old.scrolling?.displayModes != new.scrolling?.displayModes ||
               old.scrolling?.display != new.scrolling?.display || old.fallbackToPrimary != new.fallbackToPrimary {
                resetAssignments()
            }
        }
        self.config = config
        if profilesChanged { lastTopology = nil; scheduleMonitorProfile() }
        generation += 1
        pendingNavigation = nil; activeNavigation?.cancel()
        launchTask?.cancel()
        if changedDefault { changeMode(config.automaticTiling ? .automatic : .paused) }
        if case .layout(let name) = mode, !config.layouts.contains(where: { $0.name == name }) { changeMode(.paused) }
        schedule()
    }

    func toggleTiling() {
        arrangementRequest += 1
        changeMode(mode == .automatic ? .paused : .automatic)
    }

    func pause() { arrangementRequest += 1; changeMode(.paused) }
    func retile() { arrangementRequest += 1; changeMode(.automatic) }

    private func changeMode(_ mode: Mode) {
        resetAssignments()
        if !scrollingOriginal.isEmpty { scrollRestorePending = true }
        scrollingStates = [:]; navigationDisplayID = nil
        onParkedWindows?([])
        if mode != .paused { maximizedFrames.removeAll() }
        generation += 1; pendingNavigation = nil; activeNavigation?.cancel()
        launchTask?.cancel(); self.mode = mode
        schedule()
    }

    func run(_ shortcut: Shortcut) {
        switch shortcut.action {
        case .toggleTiling: toggleTiling()
        case .retile: retile()
        case .layout: applyLayout(shortcut.target)
        case .launch: launch(shortcut.target, activate: true)
        case .focusWindow where scrollingLayout == nil:
            // Focusing does not mutate geometry and need not wait for settling/retries.
            // Keep focus requests ordered relative to one another.
            let previous = focusCommand
            previous?.cancel()
            focusCommand = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                await self?.performWindowCommand(shortcut)
            }
        case .focusWindow:
            queueNavigation(shortcut)
        case .swapWindow, .resizeWindow, .maximizeWindow, .groupPrevious, .groupNext, .ungroupWindow, .centerColumn:
            let previous = windowCommand
            pendingWindowCommands += 1
            windowCommand = Task { [weak self] in
                await previous?.value
                guard let self else { return }
                defer {
                    self.pendingWindowCommands -= 1
                    if self.pendingWindowCommands == 0, self.dirty {
                        self.dirty = false
                        self.schedule()
                    }
                }
                // Finish any in-flight automatic pass before issuing a manual command.
                while self.busy { try? await Task.sleep(nanoseconds: 50_000_000) }
                await self.performWindowCommand(shortcut)
            }
        }
    }

    func navigateScrolling(_ direction: String, displayID: String?) {
        guard scrollingLayout != nil else { return }
        queueNavigation(Shortcut(key: "", action: .focusWindow, target: direction), displayID: displayID ?? "editor")
    }

    private func queueNavigation(_ shortcut: Shortcut, displayID: String? = nil) {
        // One replaceable pending intent; key repeat cannot build a stale FIFO.
        pendingNavigation = NavigationIntent(shortcut: shortcut, displayID: displayID)
        activeNavigation?.cancel()
        guard navigationWorker == nil else { return }
        let previous = windowCommand
        pendingWindowCommands += 1
        let worker = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                self.activeNavigation = nil; self.navigationWorker = nil
                self.pendingWindowCommands -= 1
                if self.pendingWindowCommands == 0, self.dirty {
                    self.dirty = false; self.schedule()
                }
            }
            while self.pendingNavigation != nil {
                while self.busy { try? await Task.sleep(nanoseconds: 20_000_000) }
                guard self.scrollingLayout != nil, let next = self.pendingNavigation else { break }
                self.pendingNavigation = nil
                let command = Task { await self.performWindowCommand(next.shortcut, editorDisplay: next.displayID) }
                self.activeNavigation = command
                await command.value
            }
        }
        navigationWorker = worker
        windowCommand = worker
    }

    private func performWindowCommand(_ shortcut: Shortcut, editorDisplay: String? = nil) async {
        let commandStarted = ProcessInfo.processInfo.systemUptime

        guard AXIsProcessTrusted() else { onStatus?("Grant Accessibility access to control windows."); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let fromEditor = scrollingLayout != nil && (editorDisplay != nil || app.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        guard fromEditor || !config.excludedBundleIDs.contains(app.bundleIdentifier ?? "") else {
            onStatus?("Focus an eligible application window first."); return
        }
        let expectedGeneration = generation
        let focused = fromEditor ? nil : await accessibility.focused(pid: app.processIdentifier)
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        guard expectedGeneration == generation, !Task.isCancelled else { return }
        let source = snapshot.windows.first(where: { window in
            return focused.map { window.pid == $0.pid && (($0.windowNumber != nil && window.windowNumber == $0.windowNumber) || CFEqual(window.element, $0.element)) } ?? false
        })
        let screens = ScreenCatalog.current()
        let sourceScreen = source.flatMap { Displays.containing($0.descriptor.frame, in: screens) }
        let targets = scrollingLayout.map { ScrollingSession.targets(layout: $0, displays: screens) } ?? []
        let lockedScreen = navigationDisplayID.flatMap { id in scrollingStates[id]?.focus.requested == nil ? nil : targets.first { $0.id == id } }
        if let editorDisplay, editorDisplay != "editor", !targets.contains(where: { $0.id == editorDisplay }) {
            onStatus?("Choose Horizontal for the editing display before navigating its columns."); return
        }
        let scrollingScreen = fromEditor ? (targets.first { $0.id == editorDisplay } ?? targets.first) :
            (lockedScreen ?? sourceScreen.flatMap { source in targets.first { $0.id == source.id } } ?? (sourceScreen == nil ? targets.first { $0.id == navigationDisplayID } ?? targets.first : nil))
        if let rootLayout = scrollingLayout, let screen = scrollingScreen {
            let layout = ScrollingSession.layout(planningLayout(rootLayout, windows: snapshot.windows, displays: screens), on: screen, displays: screens)
            var state = scrollingStates[screen.id] ?? ScrollingState()
            // Reconcile membership before choosing a neighbor. The previous
            // focused window may have closed between the keypress and this task.
            let membership = state.session.plan(layout: layout, windows: snapshot.windows.map(\.descriptor),
                displays: screens, gap: config.gap, focused: nil, minimumSizes: minimumSizes)
            let live = Set(state.session.strip.ids)
            guard var id = state.focus.resolve(observed: source?.descriptor.id, live: live, fallback: state.session.strip.focused) else {
                onStatus?("No eligible windows remain in this scrolling layout."); return
            }
            if shortcut.action != .focusWindow, !fromEditor, source == nil {
                onStatus?("Focus an eligible application window first."); return
            }
            for window in snapshot.windows where live.contains(window.descriptor.id) && scrollingOriginal[window.descriptor.id] == nil {
                scrollingOriginal[window.descriptor.id] = window.descriptor.frame
            }
            if state.frames.isEmpty { state.frames = membership.logicalFrames }
            if let direction = WindowDirection(rawValue: shortcut.target) {
                if shortcut.action == .focusWindow {
                    guard let next = state.session.strip.neighbor(id, direction: direction, wrap: layout.scrolling?.wrap == true) else { return }
                    id = next
                } else if shortcut.action == .swapWindow { state.session.strip.swap(id, direction: direction) }
            }
            switch shortcut.action {
            case .groupPrevious: state.session.strip.group(id, next: false)
            case .groupNext: state.session.strip.group(id, next: true)
            case .ungroupWindow: state.session.strip.ungroup(id)
            case .resizeWindow: state.session.strip.resize(id, target: shortcut.target)
            case .maximizeWindow:
                onStatus?("Use column resizing or pause scrolling before maximizing."); return
            default: break
            }
            state.session.strip.focus(id)
            state.lastFocus = id
            state.focus.request(id)
            let plan = state.session.plan(layout: layout, windows: snapshot.windows.map(\.descriptor),
                displays: ScreenCatalog.current(), gap: config.gap, focused: id, minimumSizes: minimumSizes,
                center: shortcut.action == .centerColumn)
            state.parked = plan.parked; state.visible = plan.visible
            scrollingStates[screen.id] = state; navigationDisplayID = screen.id
            updateParkedWindows(snapshot.windows)
            let motion = ScrollingMotion(starts: state.frames, ends: plan.logicalFrames, screen: screen, displays: screens)
            let destination = snapshot.windows.first(where: { $0.descriptor.id == id })
            // Activating a parked window can make its app bring it on screen.
            // Move the strip first; transfer focus only once it has settled.
            guard expectedGeneration == generation, !Task.isCancelled else { return }
            var report = await accessibility.move(snapshot.windows, moves: plan.moves,
                animationDuration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !ScrollingSession.supportsContinuousMotion(on: screen, displays: screens) ? 0 : (layout.scrolling?.animationDuration ?? config.animationDuration),
                nonAnimatedWindowIDs: plan.parked, scrollingMotion: motion,
                onAnimation: onTransition)
            let cancelled = Task.isCancelled
            guard expectedGeneration == generation else { return }
            scrollingStates[screen.id]?.frames = cancelled ? (report.logicalFrames ?? motion.starts) : plan.logicalFrames
            var focusVerified = false
            if !cancelled {
                await accessibility.orderVisible(snapshot.windows, ids: plan.visible, focused: id)
                if let destination {
                    for _ in 0..<3 {
                        guard !Task.isCancelled else { break }
                        let actualFocus = await accessibility.focused(pid: destination.pid)
                        focusVerified = NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid && actualFocus.map {
                            ($0.windowNumber != nil && $0.windowNumber == destination.windowNumber) || CFEqual($0.element, destination.element)
                        } == true
                        if focusVerified { break }
                        _ = await accessibility.raise(destination)
                        try? await Task.sleep(nanoseconds: 30_000_000)
                    }
                }
                if !focusVerified, !Task.isCancelled { report.messages.append("The destination did not accept keyboard focus.") }
            }
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - commandStarted) * 1000)
            let columns = state.session.strip.columns.map { $0.windows.map(String.init).joined(separator: ",") }.joined(separator: " | ")
            navigationHistory.append("\(shortcut.target) display=\(screen.name) source=\(app.bundleIdentifier ?? "unknown")/\(source?.descriptor.id.description ?? "none") focus=\(id), columns=[\(columns)], \(elapsed) ms, \(Task.isCancelled ? "superseded" : "\(report.succeeded)/\(report.requested) verified"), keyboard focus=\(focusVerified)\n" + (report.details + snapshot.notes + report.messages).joined(separator: "\n"))
            if navigationHistory.count > 8 { navigationHistory.removeFirst(navigationHistory.count - 8) }
            guard expectedGeneration == generation, !Task.isCancelled else { return }
            settledFrames.merge(report.actualFrames) { _, new in new }
            lastTargets.merge(Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.windowID, $0.frame) })) { _, new in new }
            settledGeneration = generation
            placementVerified = report.succeeded == report.requested
            diagnosticReport = (["Scrolling command: \(shortcut.action.rawValue) \(shortcut.target)",
                "\(report.succeeded)/\(report.requested) positions verified"] + report.details + plan.messages + report.messages).joined(separator: "\n")
            onStatus?("Scrolling · \(report.succeeded)/\(report.requested) positions verified" + (plan.messages + report.messages).joined(separator: " · "))
            return
        }
        guard let source else { onStatus?("The focused window cannot be moved or resized."); return }
        if [.groupPrevious, .groupNext, .ungroupWindow, .centerColumn].contains(shortcut.action) {
            onStatus?("Apply a horizontal scrolling layout first."); return
        }
        var moves: [Move] = []
        if let direction = WindowDirection(rawValue: shortcut.target),
           shortcut.action == .focusWindow || shortcut.action == .swapWindow {
            guard let neighbor = WindowNavigation.neighbor(of: source.descriptor,
                    among: snapshot.windows.filter { scrollingLayout == nil || Displays.containing($0.descriptor.frame, in: screens)?.id == sourceScreen?.id }.map(\.descriptor), direction: direction),
                  let destination = snapshot.windows.first(where: { $0.descriptor.id == neighbor.id }) else {
                onStatus?("No window to the \(direction.rawValue)."); return
            }
            if shortcut.action == .focusWindow {
                let raised = await accessibility.raise(destination)
                onStatus?(raised ? "Focused window to the \(direction.rawValue)." : "Application could not focus that window.")
                return
            }
            if let sourceScreen, usesAutomaticTiling(on: sourceScreen, displays: screens), config.algorithm == .bsp {
                for key in Array(splitTrees.keys) {
                    if splitTrees[key]?.swap(source.descriptor.id, neighbor.id) == true {
                        generation += 1; dirty = true
                        onStatus?("Swapped windows · automatic tiling active")
                        return
                    }
                }
                onStatus?("Select a neighboring window on the same display to swap.")
                return
            }
            moves = [Move(windowID: source.descriptor.id, frame: neighbor.frame),
                     Move(windowID: neighbor.id, frame: source.descriptor.frame)]
        } else if let screen = Displays.containing(source.descriptor.frame, in: ScreenCatalog.current()) {
            if shortcut.action == .resizeWindow, usesAutomaticTiling(on: screen, displays: screens), config.algorithm == .bsp {
                if splitTrees[screen.id]?.resize(source.descriptor.id, target: shortcut.target) == true {
                    generation += 1; dirty = true
                    onStatus?("Adjusted split · automatic tiling active")
                } else { onStatus?("No split in that direction to resize.") }
                return
            }
            let target: Rect
            if shortcut.action == .maximizeWindow {
                if let saved = maximizedFrames.removeValue(forKey: source.descriptor.id) {
                    // Clamp restored geometry if the monitor arrangement changed.
                    target = WindowNavigation.clamped(saved, in: screen.usable)
                    moves = [Move(windowID: source.descriptor.id, frame: target)]
                } else {
                    maximizedFrames[source.descriptor.id] = source.descriptor.frame
                    target = screen.usable
                    moves = [Move(windowID: source.descriptor.id, frame: target)]
                }
            } else {
                target = WindowNavigation.resized(source.descriptor.frame, in: screen.usable, target: shortcut.target)
                moves = [Move(windowID: source.descriptor.id, frame: target)]
            }
        }
        guard !moves.isEmpty else { return }
        if shortcut.action != .maximizeWindow {
            for move in moves { maximizedFrames[move.windowID] = nil }
        }
        // A saved/automatic layout would undo manual geometry on its next event.
        pause()
        let report = await accessibility.move(snapshot.windows, moves: moves)
        diagnosticReport = (["Manual window command: \(shortcut.action.rawValue) \(shortcut.target)"]
            + report.details + report.messages).joined(separator: "\n")
        onStatus?("\(report.succeeded)/\(report.requested) positions verified · automatic tiling paused"
            + (report.messages.isEmpty ? "" : " — \(report.messages.joined(separator: " "))"))
    }

    func launch(_ bundleID: String, activate: Bool) {
        let url = AppSelection.url(for: bundleID)
        guard let url else {
            onStatus?("Application not found: \(bundleID)"); return
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = activate
        NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] app, error in
            Task { @MainActor in
                if let error { self?.onStatus?(error.localizedDescription) }
                else { app?.unhide(); self?.schedule() }
            }
        }
    }

    private func scheduleMonitorProfile() {
        profileTask?.cancel()
        profileTask = Task {
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            let ids = ScreenCatalog.current().map(\.id).sorted()
            guard ids != lastTopology else { schedule(); return }
            lastTopology = ids
            if let profile = config.monitorProfiles.first(where: { $0.matches(ids) }) {
                applyLayout(profile.layoutName)
            } else { schedule() }
        }
    }

    private var needsReflow: Bool {
        if mode == .automatic { return true }
        if case .layout(let name) = mode { return config.layouts.first { $0.name == name } .map { $0.adaptive || $0.scrolling != nil } == true }
        return false
    }

    func preview(_ layout: Layout, gap: Double) async -> ArrangementPreview {
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        let screens = ScreenCatalog.current()
        let plan: LayoutPlan
        var totalCount: Int?
        if layout.scrolling != nil {
            var preview = LayoutPlan()
            let assignments = LayoutAssignments.plan(layout, windows: snapshot.windows.map(\.descriptor), displays: screens)
            let projected = LayoutAssignments.projected(snapshot.windows.map(\.descriptor), destinations: assignments.destinations, displays: screens)
            let layout = LayoutAssignments.localized(layout, windows: projected, displays: screens, matches: assignments.matches)
            preview.messages += assignments.messages
            totalCount = 0
            for screen in ScrollingSession.targets(layout: layout, displays: screens) {
                var session = ScrollingSession()
                let scrolling = session.plan(layout: ScrollingSession.layout(layout, on: screen, displays: screens), windows: projected, displays: screens, gap: gap, focused: nil)
                totalCount! += scrolling.moves.count
                if scrolling.moves.isEmpty {
                    preview.messages.append("\(screen.name): no matching open windows on this screen. Open a saved app or add an app rule for this screen.")
                }
                preview.moves += scrolling.moves.filter { !scrolling.parked.contains($0.windowID) }
                preview.messages += scrolling.messages.map { screen.name + ": " + $0 }
            }
            for screen in screens where ScrollingSession.mode(on: screen, layout: layout, displays: screens) == "normal" {
                let members = projected.filter { Displays.containing($0.frame, in: screens)?.id == screen.id }
                let frames = Tiler.frames(count: members.count, screen: screen.usable, algorithm: config.algorithm, gap: layout.applyGap ? gap : 0)
                preview.moves += zip(members, frames).map { Move(windowID: $0.0.id, frame: $0.1) }
            }
            for screen in screens {
                let template = LayoutScreens.templatePlan(on: screen, layout: layout, windows: projected,
                    displays: screens, gap: gap, minimumSizes: minimumSizes)
                preview.moves += template.moves
                preview.messages += template.messages
            }
            if (totalCount ?? 0) > 0 {
                preview.messages.append("Saved apps move to their assigned screens when applied. Other windows stay on their current screens. Preview omits parked columns.")
            } else { totalCount = nil }
            plan = preview
        } else {
            plan = LayoutPlanner.plan(layout, windows: snapshot.windows.map(\.descriptor), displays: screens,
                                      gap: gap, minimumSizes: minimumSizes)
        }
        let placements = plan.moves.compactMap { move -> Placement? in
            guard let window = snapshot.windows.first(where: { $0.descriptor.id == move.windowID }),
                  let screen = Displays.containing(move.frame, in: screens) else { return nil }
            return Placement(bundleID: window.descriptor.bundleID, display: "uuid:" + screen.id,
                             frame: move.frame.normalized(in: screen.usable))
        }
        return ArrangementPreview(placements: placements, messages: plan.messages, count: plan.moves.count, totalCount: totalCount)
    }

    func applyLayout(_ name: String) {
        guard config.layouts.contains(where: { $0.name == name }) else { return }
        let previousScroll = scrollingLayout.map { (name: $0.name, states: scrollingStates) }
        arrangementRequest += 1
        let request = arrangementRequest
        changeMode(.paused)
        Task {
            while busy || pendingWindowCommands > 0 || scrollRestorePending || pending != nil { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard request == arrangementRequest else { return }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            guard request == arrangementRequest else { return }
            undoWindows = snapshot.windows
            undoScroll = previousScroll
            redoWindows = []; redoScroll = nil
            performApplyLayout(name)
        }
    }

    func undoArrangement() { restoreHistory(redo: false) }
    func redoArrangement() { restoreHistory(redo: true) }
    private func restoreHistory(redo: Bool) {
        guard redo ? canRedo : canUndo else { onStatus?("No arrangement to undo."); return }
        arrangementRequest += 1
        let request = arrangementRequest
        Task {
            while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard request == arrangementRequest else { return }
            busy = true
            let outgoing = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            let outgoingScroll = scrollingLayout.map { (name: $0.name, states: scrollingStates) }
            let saved = redo ? redoWindows : undoWindows
            let savedScroll = redo ? redoScroll : undoScroll
            busy = false
            guard request == arrangementRequest else { return }
            changeMode(.paused)
            while busy || scrollRestorePending || pending != nil { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard request == arrangementRequest else { return }
            if let savedScroll, config.layouts.contains(where: { $0.name == savedScroll.name && $0.scrolling != nil }), ScrollingSession.target(layout: config.layouts.first { $0.name == savedScroll.name }!, displays: ScreenCatalog.current()) != nil {
                if redo { undoWindows = outgoing.windows; undoScroll = outgoingScroll; redoWindows = []; redoScroll = nil }
                else { redoWindows = outgoing.windows; redoScroll = outgoingScroll; undoWindows = []; undoScroll = nil }
                performApplyLayout(savedScroll.name)
                scrollingStates = savedScroll.states
                return
            }
            busy = true
            defer { busy = false; if dirty { dirty = false; schedule() } }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            let screens = ScreenCatalog.current()
            let moves = saved.compactMap { old -> Move? in
                guard snapshot.windows.contains(where: { $0.descriptor.id == old.descriptor.id && $0.pid == old.pid }),
                      let screen = Displays.containing(old.descriptor.frame, in: screens) else { return nil }
                return Move(windowID: old.descriptor.id, frame: WindowNavigation.clamped(old.descriptor.frame, in: screen.usable))
            }
            let report = await accessibility.move(snapshot.windows, moves: moves)
            if report.succeeded == report.requested {
                if redo { undoWindows = outgoing.windows; undoScroll = outgoingScroll; redoWindows = []; redoScroll = nil }
                else { redoWindows = outgoing.windows; redoScroll = outgoingScroll; undoWindows = []; undoScroll = nil }
            }
            onStatus?("\(redo ? "Redo" : "Undo") · \(report.succeeded)/\(report.requested) positions restored · tiling paused" +
                (report.messages.isEmpty ? "" : " — " + report.messages.joined(separator: " ")))
        }
    }

    private func performApplyLayout(_ name: String) {
        guard let layout = config.layouts.first(where: { $0.name == name }) else { return }
        changeMode(.layout(name))
        if layout.scrolling?.allWindows == true { return }
        let screens = ScreenCatalog.current()
        let bundles = Set(layout.placements.filter {
            guard let screen = Displays.resolve($0.display, in: screens, fallback: layout.fallbackToPrimary) else { return false }
            let mode = LayoutScreens.mode(on: screen, layout: layout, displays: screens)
            return mode != .floating && mode != .normal
        }.map(\.bundleID))
        for bundleID in bundles {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.unhide()
            } else { launch(bundleID, activate: false) }
        }
        let expectedGeneration = generation
        // Bounded startup retries only. There is no idle polling timer.
        launchTask = Task { [weak self] in
            for _ in 0..<16 {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                guard let self, self.generation == expectedGeneration else { return }
                self.schedule()
            }
        }
    }

    func schedule() {
        // Coalesce a burst at its first deadline; repeated events must not postpone it.
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pending = nil
                await self?.reconcile()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func windowEvent() {
        if (scrollingLayout != nil || (config.mouseResize && mode == .automatic && config.algorithm == .bsp)), NSEvent.pressedMouseButtons & 1 != 0 { mouseWasDown = true }
        schedule()
        discoveryRetry?.cancel()
        guard mode != .paused else { return }
        discoveryRetry = Task { [weak self] in
            // Some apps publish AXWindowCreated before their window attributes are ready.
            for delay in [600_000_000, 1_200_000_000] as [UInt64] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                self?.schedule()
            }
        }
    }

    private func reconcile(checkOnly: Bool = false) async {
        if (scrollingLayout != nil || (config.mouseResize && mode == .automatic && config.algorithm == .bsp)),
           NSEvent.pressedMouseButtons & 1 != 0 { mouseWasDown = true; return }
        guard pendingWindowCommands == 0 else { dirty = true; return }
        guard !busy else { dirty = true; return }
        guard AXIsProcessTrusted() else {
            scrollRestorePending = false
            diagnosticReport = "Accessibility permission is not granted to this running build. Grant it in System Settings, then click Tile now."
            onStatus?(diagnosticReport); return
        }
        busy = true
        let passStarted = ProcessInfo.processInfo.systemUptime
        let expectedGeneration = generation
        defer {
            busy = false
            if dirty { dirty = false; schedule() }
        }
        if scrollRestorePending || !partialScrollRestore.isEmpty {
            let snapshot = await accessibility.snapshot(excluding: [])
            let screens = ScreenCatalog.current()
            let moves = snapshot.windows.compactMap { window -> Move? in
                guard scrollRestorePending || partialScrollRestore.contains(window.descriptor.id),
                      let old = scrollingOriginal[window.descriptor.id], let screen = Displays.containing(old, in: screens) else { return nil }
                return Move(windowID: window.descriptor.id, frame: WindowNavigation.clamped(old, in: screen.usable))
            }
            if scrollRestorePending { scrollingOriginal = [:] }
            else { scrollingOriginal = scrollingOriginal.filter { !partialScrollRestore.contains($0.key) } }
            scrollRestorePending = false; partialScrollRestore = []
            _ = await accessibility.move(snapshot.windows, moves: moves)
            onParkedWindows?([])
        }
        guard mode != .paused else { onStatus?("Paused — choose Tile now or apply a layout."); return }
        events.synchronize()
        let restoreMinimized: Bool
        if case .layout(let name) = mode { restoreMinimized = config.layouts.first { $0.name == name }.map { !$0.adaptive && $0.scrolling == nil } ?? false } else { restoreMinimized = false }
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs, includeMinimized: restoreMinimized)
        let discoveryFinished = ProcessInfo.processInfo.systemUptime
        let windows = snapshot.windows
        guard expectedGeneration == generation else { return }
        events.watch(windows)
        let screens = ScreenCatalog.current()
        if let layout = scrollingLayout {
            let supported = Set(ScrollingSession.targets(layout: layout, displays: screens).map(\.id))
            let departed = scrollingStates.filter { !supported.contains($0.key) }
            for state in departed.values { partialScrollRestore.formUnion(state.session.strip.ids) }
            if !partialScrollRestore.isEmpty {
                scrollingStates = scrollingStates.filter { supported.contains($0.key) }
                dirty = true; return
            }
        }
        var focusedID: Int?
        if scrollingLayout != nil, let app = NSWorkspace.shared.frontmostApplication,
           let focused = await accessibility.focused(pid: app.processIdentifier) {
            focusedID = windows.first(where: { $0.pid == focused.pid && ((focused.windowNumber != nil && $0.windowNumber == focused.windowNumber) || CFEqual($0.element, focused.element)) })?.descriptor.id
        }
        let scrollFocusChanged = focusedID.map { focused in
            !scrollingStates.values.contains { $0.lastFocus == focused }
        } ?? false
        if mouseWasDown {
            mouseWasDown = false
            let dropPoint = mouseDropPoint
            mouseDropPoint = nil
            if let layout = scrollingLayout {
                for screen in ScrollingSession.targets(layout: layout, displays: screens) {
                    guard var state = scrollingStates[screen.id] else { continue }
                    let members = windows.filter { Displays.containing($0.descriptor.frame, in: screens)?.id == screen.id }
                    if let id = focusedID, let point = dropPoint, let old = settledFrames[id],
                       let moved = members.first(where: { $0.descriptor.id == id }) {
                        state.session.strip.dropBelow(id, old: old, new: moved.descriptor.frame,
                            pointerX: point.x, pointerY: point.y, frames: settledFrames, screen: screen.usable)
                    }
                    for window in members where config.mouseResize {
                        guard let old = settledFrames[window.descriptor.id] else { continue }
                        state.session.strip.resizeToFrame(window.descriptor.id, old: old, new: window.descriptor.frame,
                            screen: ScrollingSession.viewport(on: screen, neighborPreview: layout.scrolling?.neighborPreview ?? 120), gap: config.gap)
                    }
                    scrollingStates[screen.id] = state
                }
            }
            if config.mouseResize, config.algorithm == .bsp {
                for window in windows {
                    let id = window.descriptor.id, frame = window.descriptor.frame
                    guard let old = settledFrames[id],
                          abs(old.width - frame.width) > 6 || abs(old.height - frame.height) > 6,
                          let screen = Displays.containing(frame, in: screens),
                          usesAutomaticTiling(on: screen, displays: screens) else { continue }
                    splitTrees[screen.id]?.resizeToFrame(id, from: old, to: frame, screen: screen.usable, gap: config.gap, minimumSizes: minimumSizes)
                }
            }
        }
        if settledGeneration != generation || Set(windows.map { $0.descriptor.id }) != Set(settledFrames.keys) {
            placementRetries = 0
        }
        if checkOnly, !scrollFocusChanged, settledGeneration == generation,
           windows.count == settledFrames.count,
           windows.allSatisfy({ settledFrames[$0.descriptor.id] == $0.descriptor.frame }) {
            guard !placementVerified, placementRetries < 3 else { return }
            placementRetries += 1
        }
        let liveIDs = Set(windows.map { $0.descriptor.id })
        minimumSizes = minimumSizes.filter { liveIDs.contains($0.key) }
        var moves: [Move] = []
        var messages: [String] = []
        var parkedForAnimation: Set<Int> = []
        var visibleScrolling: Set<Int> = []
        var scrollingMotion: ScrollingMotion?
        var planningWindows = windows
        var label = ""
        switch mode {
        case .paused: return
        case .automatic:
            for screen in screens {
                let members = windows.filter { Displays.containing($0.descriptor.frame, in: screens)?.id == screen.id }
                moves += automaticMoves(members, screen: screen)
            }
            label = "Automatic · \(windows.count) windows"
        case .layout(let name):
            guard let layout = config.layouts.first(where: { $0.name == name }) else { return }
            if layout.scrolling != nil {
                let assigned = assignedWindows(windows, layout: layout, displays: screens)
                planningWindows = assigned.0
                let (plan, motion) = planScrolling(layout, windows: planningWindows, displays: screens, focused: focusedID)
                let other = otherDisplayPlan(planningWindows, layout: layout, displays: screens)
                moves = plan.moves + other.moves
                messages = assigned.1 + plan.messages + other.messages; scrollingMotion = motion
                parkedForAnimation = plan.parked; visibleScrolling = plan.visible
                let stripIDs = Set(plan.moves.map(\.windowID))
                scrollingOriginal = scrollingOriginal.filter { stripIDs.contains($0.key) }
                for window in windows where stripIDs.contains(window.descriptor.id) {
                    if scrollingOriginal[window.descriptor.id] == nil { scrollingOriginal[window.descriptor.id] = window.descriptor.frame }
                }
                onParkedWindows?(Set(windows.filter { plan.parked.contains($0.descriptor.id) }.compactMap(\.windowNumber)))
            } else {
                let plan = LayoutPlanner.plan(layout, windows: windows.map(\.descriptor), displays: screens, gap: config.gap, minimumSizes: minimumSizes)
                moves = plan.moves; messages = plan.messages
                if !plan.missingWindows { launchTask?.cancel(); launchTask = nil }
            }
            label = "Layout · \(name)"
        }
        if windows.isEmpty {
            messages.append("No manageable windows found. Check Accessibility access and open normal, non-fullscreen windows.")
        }
        let targets = Dictionary(uniqueKeysWithValues: moves.map { ($0.windowID, $0.frame) })
        let blockedScrollingEdge = scrollingLayout.map { layout in
            ScrollingSession.targets(layout: layout, displays: screens).contains { !ScrollingSession.supportsContinuousMotion(on: $0, displays: screens) }
        } ?? false
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || targets == lastTargets || blockedScrollingEdge
            ? 0 : (scrollingLayout?.scrolling?.animationDuration ?? config.animationDuration)
        let changedTargets = targets != lastTargets
        lastTargets = targets
        var report = await accessibility.move(windows, moves: moves, animationDuration: duration,
            nonAnimatedWindowIDs: parkedForAnimation, scrollingMotion: scrollingMotion, onAnimation: onTransition)
        if scrollingLayout != nil, changedTargets {
            await accessibility.orderVisible(windows, ids: visibleScrolling, focused: focusedID)
        }
        if needsReflow, expectedGeneration == generation {
            var learned = false
            for move in moves {
                guard let actual = report.actualFrames[move.windowID] else { continue }
                var minimum = minimumSizes[move.windowID] ?? Rect(x: 0, y: 0, width: 1, height: 1)
                if actual.width > move.frame.width + 4, actual.width > minimum.width {
                    minimum.width = actual.width; learned = true
                }
                if actual.height > move.frame.height + 4, actual.height > minimum.height {
                    minimum.height = actual.height; learned = true
                }
                minimumSizes[move.windowID] = minimum
            }
            if learned {
                var corrected: [Move] = []
                if case .layout(let name) = mode, let layout = config.layouts.first(where: { $0.name == name }) {
                    if layout.scrolling != nil {
                        let (plan, _) = planScrolling(layout, windows: planningWindows, displays: screens, focused: focusedID)
                        corrected = plan.moves + otherDisplayPlan(planningWindows, layout: layout, displays: screens).moves
                        messages += plan.messages
                        onParkedWindows?(Set(windows.filter { plan.parked.contains($0.descriptor.id) }.compactMap(\.windowNumber)))
                    } else {
                        corrected = LayoutPlanner.plan(layout, windows: windows.map(\.descriptor), displays: screens,
                            gap: config.gap, minimumSizes: minimumSizes).moves
                    }
                } else {
                    for screen in screens {
                        let members = windows.filter { Displays.containing($0.descriptor.frame, in: screens)?.id == screen.id }
                        corrected += automaticMoves(members, screen: screen)
                    }
                }
                if !corrected.isEmpty {
                    lastTargets = Dictionary(uniqueKeysWithValues: corrected.map { ($0.windowID, $0.frame) })
                    report = await accessibility.move(windows, moves: corrected)
                    // A new arrangement may reveal another app's width/height limit.
                    if report.succeeded < report.requested { dirty = true }
                }
            }
        }
        if expectedGeneration == generation, !pendingDestinations.isEmpty {
            let actualFrames = Dictionary(uniqueKeysWithValues: windows.map { ($0.descriptor.id, report.actualFrames[$0.descriptor.id] ?? $0.descriptor.frame) })
            pendingDestinations = pendingDestinations.filter { id, destination in
                actualFrames[id].flatMap { Displays.containing($0, in: screens)?.id } != destination
            }
            assignmentAttempts += 1
            if !pendingDestinations.isEmpty {
                if assignmentAttempts < 3 { dirty = true }
                else {
                    messages.append("Some apps could not move to their assigned display; apply the layout again after checking their windows.")
                    pendingDestinations = [:]
                }
            }
        }
        settledFrames = report.actualFrames
        settledGeneration = expectedGeneration
        placementVerified = report.succeeded == report.requested
        messages += report.messages
        guard expectedGeneration == generation else { return }
        let summary = "\(label) · \(report.succeeded)/\(report.requested) positions verified"
        let screenLines = screens.map {
            "\($0.name) [\($0.id)] builtIn=\($0.builtIn) primary=\($0.primary) usable x=\($0.usable.x) y=\($0.usable.y) w=\($0.usable.width) h=\($0.usable.height)"
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "source"
        var diagnosticLines: [String] = ["HyperMac \(version)",
            ProcessInfo.processInfo.operatingSystemVersionString, "\(Date())", summary,
            "Accessibility: granted", "Displays:"]
        diagnosticLines.append(contentsOf: screenLines)
        diagnosticLines.append("Discovery:")
        diagnosticLines.append(contentsOf: snapshot.notes)
        diagnosticLines.append("Placement results:")
        diagnosticLines.append(contentsOf: report.details)
        diagnosticLines.append("Issues:")
        diagnosticLines.append(contentsOf: messages)
        diagnosticLines.append("Timing: discovery=\(Int((discoveryFinished - passStarted) * 1000))ms total=\(Int((ProcessInfo.processInfo.systemUptime - passStarted) * 1000))ms")
        diagnosticReport = diagnosticLines.joined(separator: "\n")
        onStatus?(messages.isEmpty ? summary : "\(summary) — \(messages.prefix(3).joined(separator: " "))")
    }

    private func automaticMoves(_ members: [ManagedWindow], screen: Display, gap: Double? = nil) -> [Move] {
        let tileGap = gap ?? config.gap
        let ids = members.map { $0.descriptor.id }
        if config.algorithm == .bsp {
            var tree = splitTrees[screen.id] ?? BSPTree()
            tree.reconcile(windowIDs: ids, screen: screen.usable)
            splitTrees[screen.id] = tree
            if let frames = tree.frames(screen: screen.usable, gap: tileGap, minimumSizes: minimumSizes) {
                return ids.compactMap { id in frames[id].map { Move(windowID: id, frame: $0) } }
            }
        }
        let minima = ids.map { minimumSizes[$0] ?? Rect(x: 0, y: 0, width: 1, height: 1) }
        let frames = Tiler.fittingFrames(minimumSizes: minima, screen: screen.usable,
            algorithm: config.algorithm, gap: tileGap)
            ?? Tiler.frames(count: members.count, screen: screen.usable, algorithm: config.algorithm, gap: tileGap)
        return zip(members, frames).map { Move(windowID: $0.0.descriptor.id, frame: $0.1) }
    }

    func capture(name: String) async throws -> Layout {
        guard AXIsProcessTrusted() else { throw ConfigError("Grant Accessibility access before capturing.") }
        let capturedScrolling = scrollingLayout
        let capturedColumns = scrollingStates.mapValues { $0.session.strip.columns }
        // Pause so a capture describes the user's arrangement rather than competing with tiling.
        if capturedScrolling == nil { pause() }
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        let windows = snapshot.windows
        let screens = ScreenCatalog.current()
        var placements: [Placement] = []
        for window in windows {
            let descriptor = window.descriptor
            guard let screen = Displays.containing(descriptor.frame, in: screens) else { continue }
            let matching = windows.filter {
                (capturedScrolling == nil || Displays.containing($0.descriptor.frame, in: screens)?.id == screen.id) &&
                $0.descriptor.bundleID == descriptor.bundleID && (descriptor.title.isEmpty ||
                    $0.descriptor.title.localizedCaseInsensitiveContains(descriptor.title))
            }
            let index = matching.firstIndex { $0.descriptor.id == descriptor.id } ?? 0
            var r = descriptor.frame.normalized(in: screen.usable)
            r.x = min(max(r.x, 0), 0.99); r.y = min(max(r.y, 0), 0.99)
            r.width = min(max(r.width, 0.01), 1 - r.x); r.height = min(max(r.height, 0.01), 1 - r.y)
            var placement = Placement(bundleID: descriptor.bundleID, display: "uuid:" + screen.id, frame: r)
            let appWindowCount = windows.filter { $0.descriptor.bundleID == descriptor.bundleID }.count
            placement.titleContains = appWindowCount == 1 ? "" : descriptor.title
            placement.windowIndex = index
            if let capturedScrolling, LayoutScreens.mode(on: screen, layout: capturedScrolling, displays: screens) == .horizontal {
                guard let columns = capturedColumns[screen.id], let column = columns.firstIndex(where: { $0.windows.contains(descriptor.id) }) else { continue }
                placement.scrollColumn = column
                placement.frame = Rect(x: 0, y: 0, width: columns[column].width, height: 1)
            }
            placements.append(placement)
        }
        guard !placements.isEmpty else { throw ConfigError("No eligible visible windows to capture.") }
        var layout = Layout(name: name, placements: placements)
        layout.applyGap = capturedScrolling?.applyGap ?? false
        layout.scrolling = capturedScrolling?.scrolling
        if capturedScrolling != nil { pause() }
        return layout
    }

    func prepareToQuit() async {
        guard !scrollingOriginal.isEmpty else { return }
        pause()
        while busy || pendingWindowCommands > 0 || scrollRestorePending || pending != nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func stop() {
        if let focusInputMonitor { NSEvent.removeMonitor(focusInputMonitor); self.focusInputMonitor = nil }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        if let mouseReleaseMonitor { NSEvent.removeMonitor(mouseReleaseMonitor) }
        mouseReleaseMonitor = nil
        focusCommand?.cancel(); focusCommand = nil
        reconciliationTimer?.invalidate(); reconciliationTimer = nil
        pause(); pending?.cancel(); discoveryRetry?.cancel()
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens.removeAll()
    }
}
