import Foundation

/// Applying a saved layout assigns its matching windows before tiling each screen.
/// Normal navigation/reflow remains local to the screen after that assignment.
public struct LayoutAssignmentPlan: Sendable {
    public var destinations: [Int: String] = [:]
    public var matches: [Int: Int] = [:]
    public var messages: [String] = []
    public var missingWindows = false
}

public enum LayoutAssignments {
    public static func plan(_ layout: Layout, windows: [WindowDescriptor], displays: [Display]) -> LayoutAssignmentPlan {
        var result = LayoutAssignmentPlan()
        let windows = windows.sorted { $0.id < $1.id }
        var targets: [Int: Display] = [:]
        for (index, rule) in layout.placements.enumerated() {
            guard let screen = Displays.resolve(rule.display, in: displays, fallback: layout.fallbackToPrimary) else {
                result.messages.append("Display \(rule.display) is unavailable; skipped \(rule.bundleID).")
                continue
            }
            let mode = LayoutScreens.mode(on: screen, layout: layout, displays: displays)
            guard mode != .floating, mode != .normal else { continue }
            guard !LayoutScreens.exclusions(on: screen, layout: layout, displays: displays).contains(rule.bundleID) else { continue }
            targets[index] = screen
        }
        func candidates(_ rule: Placement) -> [WindowDescriptor] {
            windows.filter { $0.bundleID == rule.bundleID &&
                (rule.titleContains.isEmpty || $0.title.localizedCaseInsensitiveContains(rule.titleContains)) }
        }
        // Reserve local matches on every screen first. A rule on one screen must
        // not steal the window already satisfying another screen's rule.
        for index in layout.placements.indices {
            guard let screen = targets[index] else { continue }
            let rule = layout.placements[index]
            let local = candidates(rule).filter { Displays.containing($0.frame, in: displays)?.id == screen.id }
            guard local.indices.contains(rule.windowIndex) else { continue }
            let id = local[rule.windowIndex].id
            guard result.destinations[id] == nil else { continue }
            result.destinations[id] = screen.id
            result.matches[index] = id
        }
        for index in layout.placements.indices where result.matches[index] == nil {
            guard let screen = targets[index] else { continue }
            let rule = layout.placements[index]
            let matching = candidates(rule)
            let local = matching.filter {
                (result.destinations[$0.id] ?? Displays.containing($0.frame, in: displays)?.id) == screen.id
            }
            // A duplicate local rule stays unresolved instead of taking another window.
            guard !local.indices.contains(rule.windowIndex) else {
                result.messages.append("Duplicate window rule for \(rule.bundleID) on \(screen.name); skipped.")
                continue
            }
            let available = matching.filter { result.destinations[$0.id] == nil &&
                Displays.containing($0.frame, in: displays)?.id != screen.id }
            let offset = rule.windowIndex - local.count
            guard available.indices.contains(offset) else {
                result.missingWindows = true
                result.messages.append("No matching open window for \(rule.bundleID) on \(screen.name).")
                continue
            }
            let id = available[offset].id
            result.destinations[id] = screen.id
            result.matches[index] = id
        }
        return result
    }

    /// Virtual membership only: actual AX writes still use the original windows
    /// and move directly to the final tiling frame, never through an intermediate hop.
    public static func projected(_ windows: [WindowDescriptor], destinations: [Int: String], displays: [Display]) -> [WindowDescriptor] {
        windows.map { window in
            guard let id = destinations[window.id], let screen = displays.first(where: { $0.id == id }),
                  Displays.containing(window.frame, in: displays)?.id != id else { return window }
            var result = window
            result.frame = Rect(x: screen.usable.x + screen.usable.width / 4,
                y: screen.usable.y + screen.usable.height / 4,
                width: screen.usable.width / 2, height: screen.usable.height / 2)
            return result
        }
    }

    /// Window indices are screen-local after transfer; retain the exact selected
    /// windows even when moving an indexed or title-matched rule changes its ordinal.
    public static func localized(_ layout: Layout, windows: [WindowDescriptor], displays: [Display], matches: [Int: Int]) -> Layout {
        var result = layout
        for index in result.placements.indices {
            guard let id = matches[index], let screen = Displays.resolve(result.placements[index].display,
                in: displays, fallback: layout.fallbackToPrimary) else { continue }
            let rule = result.placements[index]
            let candidates = windows.filter { $0.bundleID == rule.bundleID &&
                (rule.titleContains.isEmpty || $0.title.localizedCaseInsensitiveContains(rule.titleContains)) &&
                Displays.containing($0.frame, in: displays)?.id == screen.id }.sorted { $0.id < $1.id }
            if let ordinal = candidates.firstIndex(where: { $0.id == id }) { result.placements[index].windowIndex = ordinal }
        }
        return result
    }
}
