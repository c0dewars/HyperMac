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
    public static func plan(_ layout: Layout, windows: [WindowDescriptor], displays: [Display], gap: Double,
                            minimumSizes: [Int: Rect] = [:], algorithm: TileAlgorithm = .adaptive) -> LayoutPlan {
        var plan = LayoutPlan()
        let assignments = LayoutAssignments.plan(layout, windows: windows, displays: displays)
        plan.messages = assignments.messages
        plan.missingWindows = assignments.missingWindows
        let spacing = layout.applyGap ? gap : 0
        for screen in displays {
            let mode = LayoutScreens.mode(on: screen, layout: layout, displays: displays)
            guard mode != .floating else { continue }
            let exclusions = LayoutScreens.exclusions(on: screen, layout: layout, displays: displays)
            if mode == .fixed {
                for index in layout.placements.indices {
                    guard let id = assignments.matches[index], assignments.destinations[id] == screen.id else { continue }
                    let rule = layout.placements[index]
                    let frame = rule.frame.resolved(in: screen.usable, gap: spacing)
                    if let minimum = minimumSizes[id], frame.width + 4 < minimum.width || frame.height + 4 < minimum.height {
                        plan.messages.append("\(rule.bundleID) needs more space on \(screen.name); adjust its rectangle.")
                        continue
                    }
                    plan.moves.append(Move(windowID: id, frame: frame))
                }
                continue
            }
            let ids: [Int]
            if mode == .normal {
                ids = windows.filter {
                    !exclusions.contains($0.bundleID) &&
                    (assignments.destinations[$0.id] ?? Displays.containing($0.frame, in: displays)?.id) == screen.id
                }.map(\.id).sorted()
            } else {
                ids = layout.placements.indices.compactMap { index in
                    guard let id = assignments.matches[index], assignments.destinations[id] == screen.id else { return nil }
                    return id
                }
            }
            guard !ids.isEmpty else { continue }
            let minima = ids.map { minimumSizes[$0] ?? Rect(x: 0, y: 0, width: 1, height: 1) }
            if let frames = Tiler.fittingFrames(minimumSizes: minima, screen: screen.usable,
                                               algorithm: mode == .normal ? algorithm : .adaptive, gap: spacing) {
                plan.moves += zip(ids, frames).map { Move(windowID: $0.0, frame: $0.1) }
            } else {
                plan.messages.append("Windows do not fit on \(screen.name) at their minimum sizes. Close a window or move one to another display.")
            }
        }
        return plan
    }
}
