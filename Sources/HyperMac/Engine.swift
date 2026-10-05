import AppKit
import ApplicationServices
import HyperMacCore

struct ArrangementPreview {
    var placements: [Placement]
    var messages: [String]
    var count: Int
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
    private var splitTrees: [String: BSPTree] = [:]
    private var minimumSizes: [Int: Rect] = [:]
    private var settledFrames: [Int: Rect] = [:]
    private var settledGeneration = -1
    private var placementVerified = false
    private var placementRetries = 0
    private var undoWindows: [ManagedWindow] = []
    private var redoWindows: [ManagedWindow] = []
    var canRedo: Bool { !redoWindows.isEmpty }
    private var profileTask: Task<Void, Never>?
    private var lastTopology: [String]?
    private var mouseWasDown = false
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
    private var maximizedFrames: [Int: Rect] = [:]
    private(set) var diagnosticReport = "No tiling/layout operation has run yet."
    var onStatus: ((String) -> Void)?

    init(config: Configuration) { self.config = config }

    func start() {
        events.onChange = { [weak self] in self?.windowEvent() }
        events.onResize = { [weak self] in
            guard let self, self.mode == .automatic, self.config.mouseResize,
                  self.config.algorithm == .bsp, NSEvent.pressedMouseButtons & 1 != 0 else { return }
            self.mouseWasDown = true
        }
        mouseReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mouseWasDown else { return }
                self.schedule()
            }
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
        let changedDefault = self.config.automaticTiling != config.automaticTiling
        let profilesChanged = self.config.monitorProfiles != config.monitorProfiles
        self.config = config
        if profilesChanged { lastTopology = nil; scheduleMonitorProfile() }
        generation += 1
        launchTask?.cancel()
        if changedDefault { mode = config.automaticTiling ? .automatic : .paused }
        if case .layout(let name) = mode, !config.layouts.contains(where: { $0.name == name }) { mode = .paused }
        schedule()
    }

    func toggleTiling() {
        arrangementRequest += 1
        changeMode(mode == .automatic ? .paused : .automatic)
    }

    func pause() { arrangementRequest += 1; changeMode(.paused) }
    func retile() { arrangementRequest += 1; changeMode(.automatic) }

    private func changeMode(_ mode: Mode) {
        if mode != .paused { maximizedFrames.removeAll() }
        generation += 1; launchTask?.cancel(); self.mode = mode
        schedule()
    }

    func run(_ shortcut: Shortcut) {
        switch shortcut.action {
        case .toggleTiling: toggleTiling()
        case .retile: retile()
        case .layout: applyLayout(shortcut.target)
        case .launch: launch(shortcut.target, activate: true)
        case .focusWindow:
            // Focusing does not mutate geometry and need not wait for settling/retries.
            // Keep focus requests ordered relative to one another.
            let previous = focusCommand
            previous?.cancel()
            focusCommand = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                await self?.performWindowCommand(shortcut)
            }
        case .swapWindow, .resizeWindow, .maximizeWindow:
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

    private func performWindowCommand(_ shortcut: Shortcut) async {
        guard AXIsProcessTrusted() else { onStatus?("Grant Accessibility access to control windows."); return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !config.excludedBundleIDs.contains(app.bundleIdentifier ?? "") else {
            onStatus?("Focus an eligible application window first."); return
        }
        let expectedGeneration = generation
        guard let focused = await accessibility.focused(pid: app.processIdentifier) else {
            onStatus?("No supported focused window. Exit native fullscreen first."); return
        }
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        guard expectedGeneration == generation, !Task.isCancelled else { return }
        guard let source = snapshot.windows.first(where: { CFEqual($0.element, focused.element) }) else {
            onStatus?("The focused window cannot be moved or resized."); return
        }
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
            if mode == .automatic, config.algorithm == .bsp {
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
            if shortcut.action == .resizeWindow, mode == .automatic, config.algorithm == .bsp {
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
        if case .layout(let name) = mode { return config.layouts.first { $0.name == name }?.adaptive == true }
        return false
    }

    func preview(_ layout: Layout, gap: Double) async -> ArrangementPreview {
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        let screens = ScreenCatalog.current()
        let plan = LayoutPlanner.plan(layout, windows: snapshot.windows.map(\.descriptor), displays: screens,
                                      gap: gap, minimumSizes: minimumSizes)
        let placements = plan.moves.compactMap { move -> Placement? in
            guard let window = snapshot.windows.first(where: { $0.descriptor.id == move.windowID }),
                  let screen = Displays.containing(move.frame, in: screens) else { return nil }
            return Placement(bundleID: window.descriptor.bundleID, display: "uuid:" + screen.id,
                             frame: move.frame.normalized(in: screen.usable))
        }
        return ArrangementPreview(placements: placements, messages: plan.messages, count: plan.moves.count)
    }

    func applyLayout(_ name: String) {
        guard config.layouts.contains(where: { $0.name == name }) else { return }
        arrangementRequest += 1
        let request = arrangementRequest
        changeMode(.paused)
        Task {
            while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard request == arrangementRequest else { return }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            guard request == arrangementRequest else { return }
            undoWindows = snapshot.windows
            redoWindows = []
            performApplyLayout(name)
        }
    }

    func undoArrangement() { restoreHistory(redo: false) }
    func redoArrangement() { restoreHistory(redo: true) }
    private func restoreHistory(redo: Bool) {
        guard redo ? canRedo : canUndo else { onStatus?("No arrangement to undo."); return }
        arrangementRequest += 1
        let request = arrangementRequest
        changeMode(.paused)
        Task {
            while busy || pendingWindowCommands > 0 { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard request == arrangementRequest else { return }
            busy = true
            defer { busy = false }
            let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
            let screens = ScreenCatalog.current()
            let saved = redo ? redoWindows : undoWindows
            let moves = saved.compactMap { old -> Move? in
                guard snapshot.windows.contains(where: { $0.descriptor.id == old.descriptor.id && $0.pid == old.pid }),
                      screens.contains(where: { $0.usable.intersectionArea(old.descriptor.frame) > 0 }) else { return nil }
                return Move(windowID: old.descriptor.id, frame: old.descriptor.frame)
            }
            let report = await accessibility.move(snapshot.windows, moves: moves)
            if report.succeeded == report.requested {
                if redo { undoWindows = snapshot.windows; redoWindows = [] }
                else { redoWindows = snapshot.windows; undoWindows = [] }
            }
            onStatus?("\(redo ? "Redo" : "Undo") · \(report.succeeded)/\(report.requested) positions restored · tiling paused" +
                (report.messages.isEmpty ? "" : " — " + report.messages.joined(separator: " ")))
        }
    }

    private func performApplyLayout(_ name: String) {
        guard let layout = config.layouts.first(where: { $0.name == name }) else { return }
        changeMode(.layout(name))
        let screens = ScreenCatalog.current()
        let bundles = Set(layout.placements.filter {
            Displays.resolve($0.display, in: screens, fallback: layout.fallbackToPrimary) != nil
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
        if config.mouseResize, mode == .automatic, config.algorithm == .bsp, NSEvent.pressedMouseButtons & 1 != 0 { mouseWasDown = true }
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
        if config.mouseResize, mode == .automatic, config.algorithm == .bsp,
           NSEvent.pressedMouseButtons & 1 != 0 { mouseWasDown = true; return }
        guard pendingWindowCommands == 0 else { dirty = true; return }
        guard !busy else { dirty = true; return }
        guard AXIsProcessTrusted() else {
            diagnosticReport = "Accessibility permission is not granted to this running build. Grant it in System Settings, then click Tile now."
            onStatus?(diagnosticReport); return
        }
        guard mode != .paused else { onStatus?("Paused — click Tile now or Save & arrange a layout."); return }
        busy = true
        let passStarted = ProcessInfo.processInfo.systemUptime
        let expectedGeneration = generation
        defer {
            busy = false
            if dirty { dirty = false; schedule() }
        }
        events.synchronize()
        let restoreMinimized: Bool
        if case .layout(let name) = mode { restoreMinimized = config.layouts.first { $0.name == name }?.adaptive != true } else { restoreMinimized = false }
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs, includeMinimized: restoreMinimized)
        let discoveryFinished = ProcessInfo.processInfo.systemUptime
        let windows = snapshot.windows
        guard expectedGeneration == generation else { return }
        events.watch(windows)
        let screens = ScreenCatalog.current()
        if mouseWasDown {
            mouseWasDown = false
            if config.mouseResize, mode == .automatic, config.algorithm == .bsp {
                for window in windows {
                    let id = window.descriptor.id, frame = window.descriptor.frame
                    guard let old = settledFrames[id],
                          abs(old.width - frame.width) > 6 || abs(old.height - frame.height) > 6,
                          let screen = Displays.containing(frame, in: screens) else { continue }
                    splitTrees[screen.id]?.resizeToFrame(id, from: old, to: frame, screen: screen.usable, gap: config.gap, minimumSizes: minimumSizes)
                }
            }
        }
        if settledGeneration != generation || Set(windows.map { $0.descriptor.id }) != Set(settledFrames.keys) {
            placementRetries = 0
        }
        if checkOnly, settledGeneration == generation,
           windows.count == settledFrames.count,
           windows.allSatisfy({ settledFrames[$0.descriptor.id] == $0.descriptor.frame }) {
            guard !placementVerified, placementRetries < 3 else { return }
            placementRetries += 1
        }
        let liveIDs = Set(windows.map { $0.descriptor.id })
        minimumSizes = minimumSizes.filter { liveIDs.contains($0.key) }
        var moves: [Move] = []
        var messages: [String] = []
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
            let plan = LayoutPlanner.plan(layout, windows: windows.map(\.descriptor), displays: screens, gap: config.gap, minimumSizes: minimumSizes)
            moves = plan.moves; messages = plan.messages
            if !plan.missingWindows { launchTask?.cancel(); launchTask = nil }
            label = "Layout · \(name)"
        }
        if windows.isEmpty {
            messages.append("No manageable windows found. Check Accessibility access and open normal, non-fullscreen windows.")
        }
        let targets = Dictionary(uniqueKeysWithValues: moves.map { ($0.windowID, $0.frame) })
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || targets == lastTargets
            ? 0 : config.animationDuration
        lastTargets = targets
        var report = await accessibility.move(windows, moves: moves, animationDuration: duration, onAnimation: onTransition)
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
                    corrected = LayoutPlanner.plan(layout, windows: windows.map(\.descriptor), displays: screens,
                        gap: config.gap, minimumSizes: minimumSizes).moves
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

    private func automaticMoves(_ members: [ManagedWindow], screen: Display) -> [Move] {
        let ids = members.map { $0.descriptor.id }
        if config.algorithm == .bsp {
            var tree = splitTrees[screen.id] ?? BSPTree()
            tree.reconcile(windowIDs: ids, screen: screen.usable)
            splitTrees[screen.id] = tree
            if let frames = tree.frames(screen: screen.usable, gap: config.gap, minimumSizes: minimumSizes) {
                return ids.compactMap { id in frames[id].map { Move(windowID: id, frame: $0) } }
            }
        }
        let minima = ids.map { minimumSizes[$0] ?? Rect(x: 0, y: 0, width: 1, height: 1) }
        let frames = Tiler.fittingFrames(minimumSizes: minima, screen: screen.usable,
            algorithm: config.algorithm, gap: config.gap)
            ?? Tiler.frames(count: members.count, screen: screen.usable, algorithm: config.algorithm, gap: config.gap)
        return zip(members, frames).map { Move(windowID: $0.0.descriptor.id, frame: $0.1) }
    }

    func capture(name: String) async throws -> Layout {
        guard AXIsProcessTrusted() else { throw ConfigError("Grant Accessibility access before capturing.") }
        // Pause so a capture describes the user's arrangement rather than competing with tiling.
        pause()
        let snapshot = await accessibility.snapshot(excluding: config.excludedBundleIDs)
        let windows = snapshot.windows
        let screens = ScreenCatalog.current()
        var placements: [Placement] = []
        for window in windows {
            let descriptor = window.descriptor
            let matching = windows.filter {
                $0.descriptor.bundleID == descriptor.bundleID && (descriptor.title.isEmpty ||
                    $0.descriptor.title.localizedCaseInsensitiveContains(descriptor.title))
            }
            let index = matching.firstIndex { $0.descriptor.id == descriptor.id } ?? 0
            guard let screen = Displays.containing(descriptor.frame, in: screens) else { continue }
            var r = descriptor.frame.normalized(in: screen.usable)
            r.x = min(max(r.x, 0), 0.99); r.y = min(max(r.y, 0), 0.99)
            r.width = min(max(r.width, 0.01), 1 - r.x); r.height = min(max(r.height, 0.01), 1 - r.y)
            var placement = Placement(bundleID: descriptor.bundleID, display: "uuid:" + screen.id, frame: r)
            let appWindowCount = windows.filter { $0.descriptor.bundleID == descriptor.bundleID }.count
            placement.titleContains = appWindowCount == 1 ? "" : descriptor.title
            placement.windowIndex = index
            placements.append(placement)
        }
        guard !placements.isEmpty else { throw ConfigError("No eligible visible windows to capture.") }
        var layout = Layout(name: name, placements: placements)
        layout.applyGap = false
        return layout
    }

    func stop() {
        if let mouseReleaseMonitor { NSEvent.removeMonitor(mouseReleaseMonitor) }
        mouseReleaseMonitor = nil
        focusCommand?.cancel(); focusCommand = nil
        reconciliationTimer?.invalidate(); reconciliationTimer = nil
        pause(); pending?.cancel(); discoveryRetry?.cancel()
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens.removeAll()
    }
}
