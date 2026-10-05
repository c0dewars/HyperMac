import AppKit
import ApplicationServices
import HyperMacCore

@MainActor
final class FocusBorder {
    private let probe = Accessibility()
    private var config = Configuration()
    private var active = false
    private var panels: [Int: BorderPanel] = [:]
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [pid_t: [AXUIElement]] = [:]
    private var pending: DispatchWorkItem?
    private var pendingGeometry: DispatchWorkItem?
    private var visibilityTimer: Timer?
    private var lastStack = ""
    private var transitionTimer: Timer?
    private var owners: [Int: Int] = [:]
    private var busy = false
    private var dirty = false
    private var generation = 0

    func start(config: Configuration) {
        self.config = config
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            tokens.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }))
        }
        let center = NotificationCenter.default
        tokens.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }))
        // Window ordering can change without AX move/resize notifications, notably
        // for floating/ignored apps and HyperMac's own settings window.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active, self.config.borderEnabled else { return }
                let stack = self.visibleStack()
                let signature = stack.map { String($0.number) }.joined(separator: "|")
                guard signature != self.lastStack else {
                    if self.transitionTimer == nil { self.trackExistingBorders() }
                    return
                }
                self.lastStack = signature
                self.schedule()
            }
        }
        schedule()
    }

    private func visibleStack() -> [(number: Int, frame: CGRect)] {
        let ownBorders = Set(panels.values.map(\.windowNumber))
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  !ownBorders.contains(number),
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (number, frame)
        }
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active; generation += 1
        if !active { hideAll(); clearObservers() }
        schedule()
    }

    func update(_ config: Configuration) {
        self.config = config; generation += 1
        if !config.borderEnabled { hideAll(); clearObservers() }
        schedule()
    }

    func schedule() {
        guard active, config.borderEnabled else { hideAll(); return }
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            Task { @MainActor in await self.refresh() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    private func refresh() async {
        if transitionTimer != nil { trackExistingBorders(); return }
        guard !busy else { dirty = true; return }
        guard active, config.borderEnabled, AXIsProcessTrusted() else { hideAll(); clearObservers(); return }
        busy = true
        let version = generation
        defer { busy = false; if dirty { dirty = false; schedule() } }
        let snapshot = await probe.snapshot(excluding: config.excludedBundleIDs)
        guard version == generation, active, config.borderEnabled else { return }
        synchronize(snapshot.windows)
        let live = Set(snapshot.windows.map { $0.descriptor.id })
        for id in Array(panels.keys) where !live.contains(id) {
            panels.removeValue(forKey: id)?.close()
            owners.removeValue(forKey: id)
        }
        let stack = visibleStack()
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for window in snapshot.windows {
            let id = window.descriptor.id
            guard let number = window.windowNumber,
                  let stackIndex = stack.firstIndex(where: { $0.number == number }) else {
                panels[id]?.orderOut(nil)
                continue
            }
            let panel: BorderPanel
            if let existing = panels[id] { panel = existing }
            else {
                panel = BorderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
                panel.level = .normal
                panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .transient]
                panel.isReleasedWhenClosed = false
                panel.contentView = BorderView(frame: .zero)
                panels[id] = panel
            }
            owners[id] = number
            update(panel, owner: stack[stackIndex].frame, number: number, top: top)
        }
    }

    func setTransitioning(_ active: Bool) {
        transitionTimer?.invalidate()
        transitionTimer = nil
        if active, self.active, config.borderEnabled {
            // Only read WindowServer geometry during motion; avoid rediscovering AX
            // windows while their size and position attributes are in transition.
            transitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.trackExistingBorders() }
            }
        } else { schedule() }
    }

    private func scheduleGeometryUpdate() {
        guard active, config.borderEnabled, transitionTimer == nil, pendingGeometry == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingGeometry = nil
            self.trackExistingBorders()
        }
        pendingGeometry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60, execute: work)
    }

    private func trackExistingBorders() {
        guard active, config.borderEnabled else { return }
        let stack = visibleStack()
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for (id, panel) in panels {
            guard let number = owners[id], let owner = stack.first(where: { $0.number == number }) else {
                panel.orderOut(nil); continue
            }
            update(panel, owner: owner.frame, number: number, top: top, reorder: !panel.isVisible)
        }
    }

    private func update(_ panel: BorderPanel, owner: CGRect, number: Int, top: CGFloat, reorder: Bool = true) {
            // Use the owner's current WindowServer bounds, not an earlier AX snapshot.
            let geometry = BorderGeometry.outside(window: Rect(x: owner.minX, y: owner.minY,
                width: owner.width, height: owner.height), width: config.borderWidth)
            let frame = geometry.panel
            let rect = NSRect(x: frame.x, y: top - frame.y - frame.height, width: frame.width, height: frame.height)
            let outline = panel.contentView as? BorderView
            let color = AppColor.nsColor(config.borderColor)
            let stroke = NSRect(x: geometry.stroke.x, y: geometry.stroke.y,
                width: geometry.stroke.width, height: geometry.stroke.height)
            if panel.frame != rect { panel.setFrame(rect, display: false) }
            if outline?.color != color || outline?.lineWidth != CGFloat(config.borderWidth) || outline?.strokeFrame != stroke {
                outline?.color = color
                outline?.lineWidth = CGFloat(config.borderWidth)
                outline?.strokeFrame = stroke
                outline?.needsDisplay = true
            }
            // The ring is outside the owner. Native ordering supplies occlusion;
            // rectangular clipping falsely treats transparent windows as opaque.
            if reorder { panel.order(.below, relativeTo: number) }
    }

    private var windowNotifications: [String] {
        [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
         kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    }

    private func synchronize(_ windows: [ManagedWindow]) {
        let grouped = Dictionary(grouping: windows, by: \.pid)
        for pid in Array(observers.keys) where grouped[pid] == nil {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            watched[pid] = nil
        }
        for (pid, members) in grouped {
            if observers[pid] == nil {
                var next: AXObserver?
                guard AXObserverCreate(pid, { _, _, notification, context in
                    guard let context else { return }
                    let owner = Unmanaged<FocusBorder>.fromOpaque(context).takeUnretainedValue()
                    let geometryOnly = notification as String == kAXMovedNotification || notification as String == kAXResizedNotification
                    Task { @MainActor in
                        if geometryOnly { owner.scheduleGeometryUpdate() }
                        else { owner.schedule() }
                    }
                }, &next) == .success, let next else { continue }
                observers[pid] = next
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.2)
                for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                    _ = AXObserverAddNotification(next, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
            }
            guard let observer = observers[pid] else { continue }
            let old = watched[pid] ?? []
            let current = members.map(\.element)
            for element in old where !current.contains(where: { CFEqual($0, element) }) {
                for name in windowNotifications { _ = AXObserverRemoveNotification(observer, element, name as CFString) }
            }
            for element in current where !old.contains(where: { CFEqual($0, element) }) {
                for name in windowNotifications {
                    _ = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
            watched[pid] = current
        }
    }

    private func hideAll() { panels.values.forEach { $0.orderOut(nil) } }
    private func clearObservers() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll(); watched.removeAll()
    }
    func stop() {
        pendingGeometry?.cancel(); pendingGeometry = nil
        transitionTimer?.invalidate(); transitionTimer = nil
        visibilityTimer?.invalidate(); visibilityTimer = nil
        active = false; generation += 1
        pending?.cancel(); pending = nil; clearObservers()
        panels.values.forEach { $0.close() }; panels.removeAll()
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }
}

private final class BorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BorderView: NSView {
    var color = NSColor.systemBlue
    var lineWidth: CGFloat = 3
    var strokeFrame: NSRect = .zero
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        color.setStroke()
        let radius = 12 + lineWidth / 2
        let path = NSBezierPath(roundedRect: strokeFrame, xRadius: radius, yRadius: radius)
        path.lineWidth = lineWidth; path.stroke()
    }
}
