import AppKit
import ApplicationServices
import HyperMacCore

struct ArrangementPreview {
    var placements: [Placement]
    var messages: [String]
    var count: Int
    var displays: [Display]
}

@MainActor
final class Engine {
    enum Mode: Equatable { case paused, automatic, layout(String) }
    var config: Configuration
    private(set) var mode: Mode = .paused { didSet { onModeChange?(mode != .paused) } }
    var onTransition: ((Bool) -> Void)?
    var onModeChange: ((Bool) -> Void)?
    var onManagedWindows: ((Set<Int>) -> Void)?
    var onStatus: ((String) -> Void)?
    private let accessibility = Accessibility()
    private let events = WindowEvents()
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pending: DispatchWorkItem?
    private var reconciliationTimer: Timer?
    private var placementTask: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var discoveryRetry: Task<Void, Never>?
    private var focusCommand: Task<Void, Never>?
    private var windowCommand: Task<Void, Never>?
    private var pendingWindowCommands = 0
    private var lastTopology: [String]?
    private var mouseReleaseMonitor: Any?
    private var mouseWasDown = false
    private var splitTrees: [String: BSPTree] = [:]
    private var minimumSizes: [Int: Rect] = [:]
    private var settledFrames: [Int: Rect] = [:]
    private var settledGeneration = -1
    private var settledDisplays: [String] = []
    private var lastTargets: [Int: Rect] = [:]
    private var busy = false
    private var dirty = false
    private var generation = 0
    private var arrangementRequest = 0
    private var undoWindows: [ManagedWindow] = []
    private var redoWindows: [ManagedWindow] = []
    private var maximizedFrames: [Int: Rect] = [:]
    var canUndo: Bool { !undoWindows.isEmpty }
    var canRedo: Bool { !redoWindows.isEmpty }
    private(set) var diagnosticReport = "No tiling/layout operation has run yet."

    init(config: Configuration) { self.config = config }

    func start(paused: Bool = false) {
        events.onChange = { [weak self] in self?.windowEvent() }
        events.onResize = { [weak self] in
            guard let self, self.config.mouseResize, !self.busy,
                  NSEvent.pressedMouseButtons & 1 != 0 else { return }
            self.mouseWasDown = true
        }
        mouseReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.windowEvent() }
            }
            notificationTokens.append((workspace, token))
        }
        let center = NotificationCenter.default
        let token = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.generation += 1
                    self.placementTask?.cancel()
                    self.minimumSizes = [:]
                    self.scheduleMonitorProfile()
                }
            }
        notificationTokens.append((center, token))
        mode = !paused && config.automaticTiling ? .automatic : .paused
        if !paused { scheduleMonitorProfile() }
        schedule()
        // Some apps omit lifecycle notifications. Read-only reconciliation recovers
        // those events; unchanged windows never cause more AX writes.
        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode != .paused, !self.busy, self.pending == nil else { return }
                self.schedule()
            }
        }
    }

    func update(_ next: Configuration) {
        let activeChanged: Bool
        if case .layout(let name) = mode {
            activeChanged = config.layouts.first { $0.name == name } != next.layouts.first { $0.name == name }
        } else { activeChanged = false }
        let defaultChanged = config.automaticTiling != next.automaticTiling
        let profilesChanged = config.monitorProfiles != next.monitorProfiles
        let rearrange = defaultChanged || profilesChanged || activeChanged || config.algorithm != next.algorithm ||
            config.gap != next.gap || config.excludedBundleIDs != next.excludedBundleIDs
        config = next
        guard rearrange else { return }
        generation += 1; placementTask?.cancel()
        if defaultChanged { changeMode(config.automaticTiling ? .automatic : .paused) }
        if case .layout(let name) = mode, !config.layouts.contains(where: { $0.name == name }) { changeMode(.paused) }
        if profilesChanged { lastTopology = nil; scheduleMonitorProfile() }
        schedule()
    }

    func toggleTiling() { mode == .paused ? retile() : pause() }
    func pause() { arrangementRequest += 1; changeMode(.paused) }
    func retile() { arrangementRequest += 1; changeMode(.automatic) }
    private func changeMode(_ next: Mode) {
        generation += 1
        placementTask?.cancel(); launchTask?.cancel(); discoveryRetry?.cancel()
        if next != .paused { maximizedFrames.removeAll() }
        mode = next
        if next == .paused { onManagedWindows?([]) }
        schedule()
    }

    private var activeLayout: Layout {
        if case .layout(let name) = mode, let layout = config.layouts.first(where: { $0.name == name }) { return layout }
        var layout = Layout(name: "Automatic", placements: [])
        layout.defaultScreenMode = .normal
        return layout
    }
    private func usesAutomaticTiling(on screen: Display, displays: [Display]) -> Bool {
        mode != .paused && LayoutScreens.mode(on: screen, layout: activeLayout, displays: displays) == .normal
    }

    func run(_ shortcut: Shortcut) {
        switch shortcut.action {
        case .toggleTiling: toggleTiling()
        case .retile: retile()
        case .layout: applyLayout(shortcut.target)
        case .launch: launch(shortcut.target, activate: true)
        case .focusWindow:
            let previous = focusCommand
            focusCommand = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                await self?.performWindowCommand(shortcut)
            }
        case .swapWindow, .resizeWindow, .maximizeWindow:
            let previous = windowCommand
            let requestedGeneration = generation
            pendingWindowCommands += 1
            windowCommand = Task { [weak self] in
                await previous?.value
                guard let self else { return }
                defer { self.pendingWindowCommands -= 1; self.schedule() }
                while self.busy { try? await Task.sleep(nanoseconds: 20_000_000) }
                guard requestedGeneration == self.generation, !Task.isCancelled else { return }
                await self.performWindowCommand(shortcut)
            }
        }
    }

    private func performWindowCommand(_ shortcut: Shortcut) async {
        guard AXIsProcessTrusted() else { onStatus?("Grant Accessibility access to control windows."); return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              !config.excludedBundleIDs.contains(app.bundleIdentifier ?? "") else { return }
        let expectedGeneration = generation
        let focused = await accessibility.focused(pid: app.processIdentifier)
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        guard expectedGeneration == generation, !Task.isCancelled,
              let focused, let source = snapshot.windows.first(where: {
                  $0.pid == focused.pid && ((focused.windowNumber != nil && $0.windowNumber == focused.windowNumber) || CFEqual($0.element, focused.element))
              }) else { return }
        let screens = ScreenCatalog.current()
        let sourceScreen = Displays.containing(source.descriptor.frame, in: screens)
        var moves: [Move] = []
        if let direction = WindowDirection(rawValue: shortcut.target),
           shortcut.action == .focusWindow || shortcut.action == .swapWindow {
            guard let neighbor = WindowNavigation.neighbor(of: source.descriptor,
                    among: snapshot.windows.map(\.descriptor), direction: direction),
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

    /// Preview and apply share assignments, constraints and per-display split trees.
    private func plan(_ layout: Layout, windows: [WindowDescriptor], displays: [Display], gap: Double,
                      updateTrees: Bool) -> LayoutPlan {
        var plan = LayoutPlanner.plan(layout, windows: windows, displays: displays, gap: gap,
                                      minimumSizes: minimumSizes, algorithm: config.algorithm)
        guard config.algorithm == .bsp else { return plan }
        for screen in displays where LayoutScreens.mode(on: screen, layout: layout, displays: displays) == .normal {
            let ids = plan.moves.filter { Displays.containing($0.frame, in: displays)?.id == screen.id }.map(\.windowID).sorted()
            var tree = splitTrees[screen.id] ?? BSPTree()
            tree.reconcile(windowIDs: ids, screen: screen.usable)
            if updateTrees { splitTrees[screen.id] = tree }
            if let frames = tree.frames(screen: screen.usable, gap: layout.applyGap ? gap : 0, minimumSizes: minimumSizes) {
                plan.moves.removeAll { ids.contains($0.windowID) }
                plan.moves += ids.compactMap { id in frames[id].map { Move(windowID: id, frame: $0) } }
            }
        }
        return plan
    }

    func preview(_ layout: Layout, gap: Double) async -> ArrangementPreview {
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        let screens = ScreenCatalog.current()
        let result = plan(layout, windows: snapshot.windows.map(\.descriptor), displays: screens, gap: gap, updateTrees: false)
        let placements = result.moves.compactMap { move -> Placement? in
            guard let window = snapshot.windows.first(where: { $0.descriptor.id == move.windowID }),
                  let screen = Displays.containing(move.frame, in: screens) else { return nil }
            return Placement(bundleID: window.descriptor.bundleID, display: "uuid:" + screen.id,
                             frame: move.frame.normalized(in: screen.usable))
        }
        return ArrangementPreview(placements: placements,
            messages: (AXIsProcessTrusted() ? [] : ["Accessibility access is required to read and arrange windows."]) + result.messages,
            count: result.moves.count, displays: screens)
    }

    func applyLayout(_ name: String) {
        guard config.layouts.contains(where: { $0.name == name }) else { return }
        pause()
        let request = arrangementRequest
        Task {
            while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
            guard request == arrangementRequest else { return }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            guard request == arrangementRequest else { return }
            undoWindows = snapshot.windows; redoWindows = []
            guard let layout = config.layouts.first(where: { $0.name == name }) else { return }
            changeMode(.layout(name))
            let screens = ScreenCatalog.current()
            let bundles = Set(layout.placements.filter {
                guard let screen = Displays.resolve($0.display, in: screens, fallback: layout.fallbackToPrimary) else { return false }
                let mode = LayoutScreens.mode(on: screen, layout: layout, displays: screens)
                return (mode == .adaptive || mode == .fixed) && !LayoutScreens.exclusions(on: screen, layout: layout, displays: screens).contains($0.bundleID)
            }.map(\.bundleID)).subtracting(config.excludedBundleIDs)
            for id in bundles where NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty { launch(id, activate: false) }
            let expectedGeneration = generation
            launchTask = Task { [weak self] in
                for _ in 0..<12 {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    guard let self, self.generation == expectedGeneration else { return }
                    self.schedule()
                }
            }
        }
    }

    func undoArrangement() { restoreHistory(redo: false) }
    func redoArrangement() { restoreHistory(redo: true) }
    private func restoreHistory(redo: Bool) {
        guard redo ? canRedo : canUndo else { return }
        pause()
        let request = arrangementRequest
        Task {
            while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
            guard request == arrangementRequest else { return }
            busy = true
            defer { busy = false; if dirty { dirty = false; schedule() } }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            guard request == arrangementRequest else { return }
            let saved = redo ? redoWindows : undoWindows
            let screens = ScreenCatalog.current()
            let moves = saved.compactMap { old -> Move? in
                guard snapshot.windows.contains(where: { $0.descriptor.id == old.descriptor.id && $0.pid == old.pid }),
                      let screen = Displays.containing(old.descriptor.frame, in: screens) else { return nil }
                return Move(windowID: old.descriptor.id, frame: WindowNavigation.clamped(old.descriptor.frame, in: screen.usable))
            }
            let report = await accessibility.move(snapshot.windows, moves: moves)
            if report.succeeded == report.requested {
                if redo { undoWindows = snapshot.windows; redoWindows = [] }
                else { redoWindows = snapshot.windows; undoWindows = [] }
            }
            onStatus?("\(redo ? "Redo" : "Undo") · \(report.succeeded)/\(report.requested) positions restored · tiling paused")
        }
    }

    func schedule() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            guard !self.busy, self.pendingWindowCommands == 0 else { self.dirty = true; return }
            self.placementTask = Task { await self.reconcile() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }
    private func windowEvent() {
        schedule()
        discoveryRetry?.cancel()
        guard mode != .paused else { return }
        discoveryRetry = Task { [weak self] in
            for delay in [300_000_000, 900_000_000] as [UInt64] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                self?.schedule()
            }
        }
    }

    private func reconcile() async {
        guard mode != .paused else { onStatus?("Paused"); return }
        guard !Task.isCancelled, !busy else { return }
        // Never fight a user's drag, including when mouse resizing is disabled.
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        guard AXIsProcessTrusted() else { onStatus?("Accessibility access required"); return }
        busy = true
        let expectedGeneration = generation
        let started = ProcessInfo.processInfo.systemUptime
        defer { busy = false; if dirty { dirty = false; schedule() } }
        events.synchronize()
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        let windows = snapshot.windows
        events.watch(windows)
        let screens = ScreenCatalog.current()
        if mouseWasDown {
            mouseWasDown = false
            if config.mouseResize, config.algorithm == .bsp {
                for window in windows {
                    let id = window.descriptor.id, frame = window.descriptor.frame
                    guard let old = settledFrames[id], let screen = Displays.containing(frame, in: screens),
                          usesAutomaticTiling(on: screen, displays: screens) else { continue }
                    splitTrees[screen.id]?.resizeToFrame(id, from: old, to: frame, screen: screen.usable,
                        gap: activeLayout.applyGap ? config.gap : 0, minimumSizes: minimumSizes)
                }
            }
        }
        let observed = Dictionary(windows.map { ($0.descriptor.id, $0.descriptor.frame) }) { first, _ in first }
        let displaySignature = screens.map { "\($0.id):\($0.primary):\($0.frame):\($0.usable)" }.sorted()
        guard settledGeneration != generation || observed != settledFrames || displaySignature != settledDisplays else { return }
        minimumSizes = minimumSizes.filter { observed[$0.key] != nil }
        splitTrees = splitTrees.filter { id, _ in screens.contains { $0.id == id } }
        let layout = activeLayout
        var result = plan(layout, windows: windows.map(\.descriptor), displays: screens, gap: config.gap, updateTrees: true)
        if !result.missingWindows { launchTask?.cancel() }
        let managedIDs = Set(result.moves.map(\.windowID))
        onManagedWindows?(Set(windows.filter { managedIDs.contains($0.descriptor.id) }.compactMap(\.windowNumber)))
        let targets = Dictionary(result.moves.map { ($0.windowID, $0.frame) }) { _, last in last }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || targets == lastTargets ? 0 : config.animationDuration
        lastTargets = targets
        var report = await accessibility.move(windows, moves: result.moves, animationDuration: duration, onAnimation: onTransition)
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        // At most one corrective plan per pass, using actual app minimum sizes.
        // An impossible fit is reported instead of repeatedly forcing overlap.
        if learnMinimumSizes(report.actualFrames, moves: result.moves) {
            let corrected = plan(layout, windows: windows.map(\.descriptor), displays: screens, gap: config.gap, updateTrees: true)
            result.messages += corrected.messages
            let correctedIDs = Set(corrected.moves.map(\.windowID))
            onManagedWindows?(Set(windows.filter { correctedIDs.contains($0.descriptor.id) }.compactMap(\.windowNumber)))
            if !corrected.moves.isEmpty {
                report = await accessibility.move(windows, moves: corrected.moves)
                _ = learnMinimumSizes(report.actualFrames, moves: corrected.moves)
            }
        }
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        settledFrames = observed.merging(report.actualFrames) { _, actual in actual }
        settledGeneration = expectedGeneration
        settledDisplays = displaySignature
        let issues = result.messages + report.messages
        let summary = "\(layout.name) · \(report.succeeded)/\(report.requested) positions verified"
        let screenLines = screens.map { "\($0.name) [\($0.id)] mode=\(LayoutScreens.mode(on: $0, layout: layout, displays: screens).rawValue) usable=\($0.usable)" }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "source"
        var diagnosticLines = ["HyperMac \(version)", summary, "Accessibility: granted", "Displays:"]
        diagnosticLines.append(contentsOf: screenLines)
        diagnosticLines.append("Discovery:")
        diagnosticLines.append(contentsOf: snapshot.notes)
        diagnosticLines.append("Placement results:")
        diagnosticLines.append(contentsOf: report.details)
        diagnosticLines.append("Issues:")
        diagnosticLines.append(contentsOf: issues)
        let elapsedMilliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        diagnosticLines.append("Total: \(elapsedMilliseconds) ms")
        diagnosticReport = diagnosticLines.joined(separator: "\n")
        onStatus?(issues.isEmpty ? summary : summary + " — " + issues.joined(separator: " "))
    }
    @discardableResult
    private func learnMinimumSizes(_ frames: [Int: Rect], moves: [Move]) -> Bool {
        var learned = false
        for move in moves {
            guard let actual = frames[move.windowID] else { continue }
            var minimum = minimumSizes[move.windowID] ?? Rect(x: 0, y: 0, width: 1, height: 1)
            if actual.width > move.frame.width + 4, actual.width > minimum.width {
                minimum.width = actual.width; learned = true
            }
            if actual.height > move.frame.height + 4, actual.height > minimum.height {
                minimum.height = actual.height; learned = true
            }
            minimumSizes[move.windowID] = minimum
        }
        return learned
    }
    func capture(name: String) async throws -> Layout {
        guard AXIsProcessTrusted() else { throw ConfigError("Grant Accessibility access before capturing.") }
        let windows = await accessibility.snapshot(excluding: config.excludedBundleIDs).windows
        let screens = ScreenCatalog.current()
        var placements: [Placement] = []
        for window in windows {
            let d = window.descriptor
            guard let screen = Displays.containing(d.frame, in: screens) else { continue }
            let local = windows.filter { $0.descriptor.bundleID == d.bundleID && Displays.containing($0.descriptor.frame, in: screens)?.id == screen.id }
            var p = Placement(bundleID: d.bundleID, display: "uuid:" + screen.id,
                              frame: CanvasGeometry.placement(d.frame, on: screen, snap: false))
            p.windowIndex = local.firstIndex { $0.descriptor.id == d.id } ?? 0
            placements.append(p)
        }
        guard !placements.isEmpty else { throw ConfigError("No eligible visible windows to capture.") }
        var layout = Layout(name: name, placements: placements)
        layout.applyGap = false
        return layout
    }

    func prepareToQuit() async {
        pause()
        while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
    }
    func stop() {
        placementTask?.cancel(); launchTask?.cancel(); profileTask?.cancel(); discoveryRetry?.cancel()
        focusCommand?.cancel(); windowCommand?.cancel(); pending?.cancel()
        reconciliationTimer?.invalidate()
        if let mouseReleaseMonitor { NSEvent.removeMonitor(mouseReleaseMonitor) }
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens.removeAll()
    }
}
