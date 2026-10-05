import AppKit
import ApplicationServices
import HyperMacCore

struct ManagedWindow {
    let element: AXUIElement
    let descriptor: WindowDescriptor
    let pid: pid_t
    var windowNumber: Int? = nil
}

struct WindowSnapshot {
    var windows: [ManagedWindow] = []
    var notes: [String] = []
}

struct MoveReport {
    var actualFrames: [Int: Rect] = [:]
    var succeeded = 0
    var requested = 0
    var messages: [String] = []
    var details: [String] = []
}

/// Synchronous AX calls live on one worker queue, never in the shortcut/UI callback.
final class Accessibility {
    private let queue = DispatchQueue(label: "local.hypermac.accessibility", qos: .userInitiated)
    // AXWindows is often ordered by focus. Keep session identities independent of that order.
    // Only accessed on queue.
    private var identities: [pid_t: [(element: AXUIElement, id: Int)]] = [:]
    private var nextID = 1

    func focused(pid: pid_t) async -> ManagedWindow? {
        await withCheckedContinuation { continuation in
            queue.async {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.2)
                let window: AXUIElement? = Self.attribute(app, kAXFocusedWindowAttribute)
                guard let window else { continuation.resume(returning: nil); return }
                AXUIElementSetMessagingTimeout(window, 0.2)
                let minimized: Bool = Self.attribute(window, kAXMinimizedAttribute) ?? false
                let fullscreen: Bool = Self.attribute(window, "AXFullScreen") ?? false
                let subrole: String = Self.attribute(window, kAXSubroleAttribute) ?? ""
                let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]] ?? []
                guard !minimized, !fullscreen, subrole == kAXStandardWindowSubrole,
                      let frame = Self.frame(window), frame.width > 0, frame.height > 0,
                      visible.contains(where: { Self.matchesVisible($0, pid: pid, frame: frame) }) else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: ManagedWindow(element: window,
                    descriptor: WindowDescriptor(id: 0, bundleID: "", title: "", frame: frame), pid: pid))
            }
        }
    }

    static func requestPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func raise(_ window: ManagedWindow) async -> Bool {
        _ = await MainActor.run {
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                continuation.resume(returning: AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success)
            }
        }
    }

    func snapshot(excluding: [String], includeMinimized: Bool = false) async -> WindowSnapshot {
        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    && !excluding.contains($0.bundleIdentifier ?? "")
            }.map { ($0.processIdentifier, $0.bundleIdentifier ?? "", $0.isHidden) }
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                // Bounds and owner PID do not require screen-recording access. No window titles are read here.
                let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]] ?? []
                var result = WindowSnapshot()
                let live = Set(apps.map { $0.0 })
                self.identities = self.identities.filter { live.contains($0.key) }
                for (pid, bundleID, hidden) in apps {
                    if hidden { result.notes.append("\(bundleID): application is hidden."); continue }
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.5)
                    var raw: CFTypeRef?
                    let listStatus = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
                    guard listStatus == .success, let windows = raw as? [AXUIElement] else {
                        result.notes.append("\(bundleID): cannot read windows (AX \(listStatus.rawValue)).")
                        continue
                    }
                    let previous = self.identities[pid] ?? []
                    var current: [(element: AXUIElement, id: Int)] = []
                    for window in windows {
                        let id: Int
                        if let known = previous.first(where: { CFEqual($0.element, window) }) { id = known.id }
                        else { id = self.nextID; self.nextID += 1 }
                        current.append((window, id))
                        AXUIElementSetMessagingTimeout(window, 0.5)
                        let minimized: Bool = Self.attribute(window, kAXMinimizedAttribute) ?? false
                        let fullscreen: Bool = Self.attribute(window, "AXFullScreen") ?? false
                        let subrole: String = Self.attribute(window, kAXSubroleAttribute) ?? ""
                        let role: String = Self.attribute(window, kAXRoleAttribute) ?? ""
                        let reason: String?
                        if minimized && !includeMinimized { reason = "minimized" }
                        else if fullscreen { reason = "native fullscreen" }
                        else if role != kAXWindowRole || (!subrole.isEmpty && subrole != kAXStandardWindowSubrole) { reason = "nonstandard window (\(role)/\(subrole))" }
                        else { reason = nil }
                        if let reason { result.notes.append("\(bundleID) window \(id): skipped — \(reason)."); continue }
                        guard let frame = Self.frame(window), frame.width > 0, frame.height > 0 else {
                            result.notes.append("\(bundleID) window \(id): cannot read its frame."); continue
                        }
                        guard Self.settable(window, kAXPositionAttribute) != false,
                              Self.settable(window, kAXSizeAttribute) != false else {
                            result.notes.append("\(bundleID) window \(id): app reports it cannot move or resize."); continue
                        }
                        guard (minimized && includeMinimized) || visible.contains(where: { Self.matchesVisible($0, pid: pid, frame: frame) }) else {
                            result.notes.append("\(bundleID) window \(id): not matched on the visible desktop; AX frame \(Self.describe(frame)).")
                            continue
                        }
                        let title: String = Self.attribute(window, kAXTitleAttribute) ?? ""
                        result.windows.append(ManagedWindow(element: window,
                            descriptor: WindowDescriptor(id: id, bundleID: bundleID, title: title, frame: frame), pid: pid,
                            windowNumber: (visible.first(where: { Self.matchesVisible($0, pid: pid, frame: frame) })?[kCGWindowNumber as String] as? NSNumber)?.intValue))
                    }
                    self.identities[pid] = current
                    if windows.isEmpty { result.notes.append("\(bundleID): no windows; open a document/window first.") }
                }
                result.windows.sort { $0.descriptor.id < $1.descriptor.id }
                continuation.resume(returning: result)
            }
        }
    }

    func move(_ windows: [ManagedWindow], moves: [Move], animationDuration: Double = 0,
              onAnimation: (@MainActor (Bool) -> Void)? = nil) async -> MoveReport {
        guard !moves.isEmpty else { return MoveReport() }
        var pending = moves
        var lastErrors: [Int: String] = [:]
        var actualFrames: [Int: Rect] = [:]
        // Restoring a window is asynchronous in many apps. Let restoration settle
        // before writing geometry rather than resizing a still-minimized window.
        let restored: Bool = await withCheckedContinuation { continuation in
            queue.async {
                var restored = false
                for window in windows where moves.contains(where: { $0.windowID == window.descriptor.id }) {
                    let minimized: Bool = Self.attribute(window.element, kAXMinimizedAttribute) ?? false
                    if minimized {
                        restored = true
                        _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                }
                continuation.resume(returning: restored)
            }
        }
        if restored { try? await Task.sleep(nanoseconds: 300_000_000) }
        if animationDuration > 0 {
            await onAnimation?(true)
            await animate(windows, moves: moves, duration: animationDuration)
            await onAnimation?(false)
        }
        // Allow apps/WindowServer to settle before checking, then correct only failed targets.
        for settlingDelay in [40_000_000, 150_000_000, 300_000_000, 600_000_000] as [UInt64] {
            let batch = pending
            let errors: [Int: String] = await withCheckedContinuation { continuation in
            queue.async {
                var errors: [Int: String] = [:]
                for move in batch {
                    guard let window = windows.first(where: { $0.descriptor.id == move.windowID }) else { continue }
                    let target = move.frame
                    let minimized: Bool = Self.attribute(window.element, kAXMinimizedAttribute) ?? false
                    if minimized {
                        let result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                        errors[move.windowID] = "window restoration pending (AX \(result.rawValue))"
                        continue
                    }
                    if let current = Self.frame(window.element), Self.close(current, target, tolerance: 1) { continue }
                    var point = CGPoint(x: target.x, y: target.y)
                    var size = CGSize(width: target.width, height: target.height)
                    guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { continue }
                    // Shrink before moving across displays; expand after reaching the destination.
                    if let current = Self.frame(window.element),
                       current.width > target.width || current.height > target.height {
                        var interim = CGSize(width: min(current.width, target.width), height: min(current.height, target.height))
                        if let value = AXValueCreate(.cgSize, &interim) {
                            _ = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, value)
                        }
                    }
                    _ = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p)
                    let sizeResult = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
                    if sizeResult != .success {
                        errors[move.windowID] = "resize AX \(sizeResult.rawValue)"
                    }
                }
                continuation.resume(returning: errors)
            }
            }
            lastErrors.merge(errors) { _, new in new }
            try? await Task.sleep(nanoseconds: settlingDelay)
            // Finder can apply AXSize asynchronously and shift the origin while resizing.
            // Correct the origin only after the size write has settled.
            let repositioned: Bool = await withCheckedContinuation { continuation in
                queue.async {
                    var repositioned = false
                    for move in batch {
                        guard let window = windows.first(where: { $0.descriptor.id == move.windowID }),
                              let current = Self.frame(window.element),
                              abs(current.x - move.frame.x) > 1 || abs(current.y - move.frame.y) > 1 else { continue }
                        var point = CGPoint(x: move.frame.x, y: move.frame.y)
                        if let value = AXValueCreate(.cgPoint, &point) {
                            _ = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, value)
                            repositioned = true
                        }
                    }
                    continuation.resume(returning: repositioned)
                }
            }
            if repositioned { try? await Task.sleep(nanoseconds: 100_000_000) }
            actualFrames = await withCheckedContinuation { continuation in
                queue.async {
                    var frames: [Int: Rect] = [:]
                    for window in windows {
                        let minimized: Bool = Self.attribute(window.element, kAXMinimizedAttribute) ?? false
                        if !minimized, let frame = Self.frame(window.element) { frames[window.descriptor.id] = frame }
                    }
                    continuation.resume(returning: frames)
                }
            }
            pending = moves.filter { move in
                guard let actual = actualFrames[move.windowID] else { return true }
                return !Self.close(actual, move.frame, tolerance: 4)
            }
            if pending.isEmpty { break }
        }
        var report = MoveReport(actualFrames: actualFrames, succeeded: moves.count - pending.count, requested: moves.count)
        for move in moves {
            let name = windows.first { $0.descriptor.id == move.windowID }?.descriptor.bundleID ?? "Unknown app"
            let actual = actualFrames[move.windowID].map(Self.describe) ?? "unavailable"
            report.details.append("\(name) window \(move.windowID): requested \(Self.describe(move.frame)); actual \(actual).")
            if pending.contains(where: { $0.windowID == move.windowID }) {
                report.messages.append("\(name): \(lastErrors[move.windowID] ?? "app constrained the size/position or did not settle").")
            }
        }
        return report
    }

    private func animate(_ windows: [ManagedWindow], moves: [Move], duration: Double) async {
        // Capture fresh starts after restoration. Use elapsed time, not a fixed frame
        // count, so a slow AX client cannot turn a short transition into a long queue.
        let starts: [Int: Rect] = await withCheckedContinuation { continuation in
            queue.async {
                var frames: [Int: Rect] = [:]
                for window in windows {
                    if let frame = Self.frame(window.element) { frames[window.descriptor.id] = frame }
                }
                continuation.resume(returning: frames)
            }
        }
        guard moves.contains(where: { move in
            starts[move.windowID].map { !Self.close($0, move.frame, tolerance: 4) } ?? false
        }) else { return }
        let started = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            let frameStarted = ProcessInfo.processInfo.systemUptime
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    for move in moves {
                        guard let start = starts[move.windowID], !Self.close(start, move.frame, tolerance: 1),
                              let window = windows.first(where: { $0.descriptor.id == move.windowID }) else { continue }
                        let frame = WindowTransition.frame(from: start, to: move.frame, progress: progress)
                        var size = CGSize(width: frame.width, height: frame.height)
                        var point = CGPoint(x: frame.x, y: frame.y)
                        if let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &point) {
                            _ = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
                            _ = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p)
                        }
                    }
                    continuation.resume()
                }
            }
            if progress >= 1 { break }
            // AX writes consume part of the frame budget; do not add a full frame
            // of sleep after them or the animation slows as the window count grows.
            let remaining = 1.0 / 60 - (ProcessInfo.processInfo.systemUptime - frameStarted)
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func settable(_ element: AXUIElement, _ name: String) -> Bool? {
        var value = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success else { return nil }
        return value.boolValue
    }

    private static func frame(_ element: AXUIElement) -> Rect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        let p = positionRef as! AXValue
        let s = sizeRef as! AXValue
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return Rect(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    private static func close(_ a: Rect, _ b: Rect, tolerance: Double) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func describe(_ r: Rect) -> String {
        "x=\(Int(r.x)) y=\(Int(r.y)) w=\(Int(r.width)) h=\(Int(r.height))"
    }

    private static func matchesVisible(_ info: [String: Any], pid: pid_t, frame: Rect) -> Bool {
        guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        let visibleFrame = Rect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        // AX and WindowServer may disagree around title bars/decorations. Keep a conservative
        // geometric match rather than requiring every edge to match within four points.
        return WindowGeometry.sameVisibleWindow(frame, visibleFrame)
    }
}

/// Notifications for creation/destruction/minimization, not moves/resizes: prevents feedback loops.
final class WindowEvents {
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: [pid_t: [AXUIElement]] = [:]
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?

    func synchronize() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let alive = Set(apps.map(\.processIdentifier))
        for pid in Array(observers.keys) where !alive.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            watchedWindows[pid] = nil
        }
        for app in apps where observers[app.processIdentifier] == nil {
            var observer: AXObserver?
            let status = AXObserverCreate(app.processIdentifier, { _, element, notification, context in
                guard let context else { return }
                let instance = Unmanaged<WindowEvents>.fromOpaque(context).takeUnretainedValue()
                if notification as String == kAXResizedNotification {
                    instance.onResize?()
                    return
                }
                if notification as String == kAXUIElementDestroyedNotification {
                    for pid in Array(instance.watchedWindows.keys) {
                        instance.watchedWindows[pid]?.removeAll { CFEqual($0, element) }
                    }
                }
                instance.onChange?()
            }, &observer)
            guard status == .success, let observer else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
            observers[app.processIdentifier] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func watch(_ windows: [ManagedWindow]) {
        let grouped = Dictionary(grouping: windows, by: \.pid)
        for (pid, observer) in observers {
            // Keep subscriptions when a window minimizes or changes Space, until destruction.
            let current = grouped[pid]?.map(\.element) ?? []
            let previous = watchedWindows[pid] ?? []
            let notifications = [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                                 kAXWindowDeminiaturizedNotification, kAXResizedNotification]
            for window in current where !previous.contains(where: { CFEqual($0, window) }) {
                for name in notifications {
                    _ = AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
            watchedWindows[pid] = previous + current.filter { window in !previous.contains { CFEqual($0, window) } }
        }
    }

    deinit {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
