import Foundation

public struct WindowDescriptor: Sendable {
    public var id: Int
    public var bundleID: String
    public var title: String
    public var frame: Rect
    public init(id: Int, bundleID: String, title: String, frame: Rect) {
        self.id = id; self.bundleID = bundleID; self.title = title; self.frame = frame
    }
}

public struct Move: Sendable {
    public var windowID: Int
    public var frame: Rect
    public init(windowID: Int, frame: Rect) { self.windowID = windowID; self.frame = frame }
}

public struct LayoutPlan: Sendable {
    public init() {}
    public var moves: [Move] = []
    public var messages: [String] = []
    public var missingWindows = false
}

public enum LayoutPlanner {
    public static func plan(_ layout: Layout, windows: [WindowDescriptor], displays: [Display], gap: Double, minimumSizes: [Int: Rect] = [:]) -> LayoutPlan {
        var plan = LayoutPlan()
        var assigned = Set<Int>()
        var screenWindows: [String: [Int]] = [:]
        for placement in layout.placements {
            guard let screen = Displays.resolve(placement.display, in: displays, fallback: layout.fallbackToPrimary) else {
                plan.messages.append("Display \(placement.display) is unavailable; skipped \(placement.bundleID).")
                continue
            }
            let candidates = windows.filter {
                $0.bundleID == placement.bundleID &&
                (placement.titleContains.isEmpty || $0.title.localizedCaseInsensitiveContains(placement.titleContains))
            }
            guard candidates.indices.contains(placement.windowIndex) else {
                plan.missingWindows = true
                plan.messages.append("No matching window for \(placement.bundleID); check its title rule, window index \(placement.windowIndex), and whether its window is open.")
                continue
            }
            let window = candidates[placement.windowIndex]
            guard assigned.insert(window.id).inserted else {
                plan.messages.append("Two placements select the same window of \(placement.bundleID); skipped duplicate.")
                continue
            }
            screenWindows[screen.id, default: []].append(window.id)
            plan.moves.append(Move(windowID: window.id, frame: placement.frame.resolved(in: screen.usable, gap: layout.applyGap ? gap : 0)))
        }
        if layout.adaptive {
            plan.moves = []
            for screen in displays {
                let ids = screenWindows[screen.id] ?? []
                guard !ids.isEmpty else { continue }
                let minima = ids.map { minimumSizes[$0] ?? Rect(x: 0, y: 0, width: 1, height: 1) }
                if let frames = Tiler.fittingFrames(minimumSizes: minima, screen: screen.usable,
                    algorithm: .adaptive, gap: layout.applyGap ? gap : 0) {
                    plan.moves += zip(ids, frames).map { Move(windowID: $0.0, frame: $0.1) }
                } else {
                    plan.messages.append("Open windows do not fit on \(screen.name); leaving their positions unchanged.")
                }
            }
        }
        return plan
    }
}
