import Foundation

public struct ScrollingOptions: Codable, Equatable, Sendable {
    public var display = "primary"
    public var hyperScroll = false
    public var allWindows = true
    public var tileOtherDisplays = true
    public var displayModes: [String: String] = [:]
    public var displayExcludedBundleIDs: [String: [String]] = [:]
    public var neighborPreview: Double = 120
    public var excludedBundleIDs: [String] = []
    public var width: Double = 0.5
    public var centerFocus = false
    public var wrap = false
    public var animationDuration: Double = 0.22
    public init() {}
    private enum CodingKeys: String, CodingKey { case display, hyperScroll, allWindows, tileOtherDisplays, displayModes, displayExcludedBundleIDs, neighborPreview, width, centerFocus, wrap, animationDuration, excludedBundleIDs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? "primary"
        hyperScroll = try c.decodeIfPresent(Bool.self, forKey: .hyperScroll) ?? false
        allWindows = try c.decodeIfPresent(Bool.self, forKey: .allWindows) ?? true
        tileOtherDisplays = try c.decodeIfPresent(Bool.self, forKey: .tileOtherDisplays) ?? true
        displayModes = try c.decodeIfPresent([String: String].self, forKey: .displayModes) ?? [:]
        displayExcludedBundleIDs = try c.decodeIfPresent([String: [String]].self, forKey: .displayExcludedBundleIDs) ?? [:]
        neighborPreview = try c.decodeIfPresent(Double.self, forKey: .neighborPreview) ?? 120
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.5
        centerFocus = try c.decodeIfPresent(Bool.self, forKey: .centerFocus) ?? false
        wrap = try c.decodeIfPresent(Bool.self, forKey: .wrap) ?? false
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.22
    }
}

/// Logical strip geometry is independent of the desktop's finite coordinate space.
public struct ScrollingStrip: Sendable {
    public struct Column: Equatable, Sendable {
        public var windows: [Int]
        public var width: Double
        public var weights: [Int: Double] = [:]
    }
    public private(set) var columns: [Column] = []
    public private(set) var offset: Double = 0
    private var centeredID: Int?
    public private(set) var focused: Int?
    public init() {}
    public var ids: [Int] { columns.flatMap(\.windows) }
    public func column(of id: Int) -> Int? { columns.firstIndex { $0.windows.contains(id) } }

    public mutating func reconcile(_ live: [Int], width: Double, groups: [Int: Int] = [:], widths: [Int: Double] = [:]) {
        let liveSet = Set(live)
        let oldIndex = focused.flatMap { ids.firstIndex(of: $0) } ?? 0
        for index in columns.indices {
            columns[index].windows.removeAll { !liveSet.contains($0) }
            columns[index].weights = columns[index].weights.filter { liveSet.contains($0.key) }
        }
        columns.removeAll { $0.windows.isEmpty }
        var known = Set(ids)
        var insertionAnchor = focused
        for id in live where known.insert(id).inserted {
            if let group = groups[id], let index = columns.firstIndex(where: { $0.windows.contains { groups[$0] == group } }) {
                columns[index].windows.append(id)
            } else {
                let index = insertionAnchor.flatMap { column(of: $0).map { $0 + 1 } } ?? columns.count
                columns.insert(Column(windows: [id], width: widths[id] ?? width), at: index)
                insertionAnchor = id
            }
        }
        if focused == nil || !liveSet.contains(focused!) {
            focused = ids.isEmpty ? nil : ids[min(oldIndex, ids.count - 1)]
        }
        if columns.isEmpty { offset = 0 }
    }

    public mutating func focus(_ id: Int) {
        if column(of: id) != nil {
            if focused != id { centeredID = nil }
            focused = id
        }
    }
    public func neighbor(_ id: Int, direction: WindowDirection, wrap: Bool) -> Int? {
        guard let c = column(of: id), let row = columns[c].windows.firstIndex(of: id) else { return nil }
        if direction == .up || direction == .down {
            let target = row + (direction == .up ? -1 : 1)
            return columns[c].windows.indices.contains(target) ? columns[c].windows[target] : nil
        }
        var target = c + (direction == .left ? -1 : 1)
        if wrap { target = (target + columns.count) % columns.count }
        guard columns.indices.contains(target), target != c else { return nil }
        return columns[target].windows[min(row, columns[target].windows.count - 1)]
    }
    public mutating func swap(_ id: Int, direction: WindowDirection) {
        guard let c = column(of: id), let other = neighbor(id, direction: direction, wrap: false),
              let d = column(of: other), let row = columns[c].windows.firstIndex(of: id),
              let otherRow = columns[d].windows.firstIndex(of: other) else { return }
        if c == d { columns[c].windows.swapAt(row, otherRow) }
        else { columns.swapAt(c, d) }
    }
    public mutating func group(_ id: Int, next: Bool) {
        guard let c = column(of: id) else { return }
        let target = c + (next ? 1 : -1)
        guard columns.indices.contains(target) else { return }
        columns[target].windows.append(id)
        columns[c].windows.removeAll { $0 == id }
        columns[c].weights[id] = nil
        columns.removeAll { $0.windows.isEmpty }
    }
    public mutating func ungroup(_ id: Int) {
        guard let c = column(of: id), columns[c].windows.count > 1 else { return }
        columns[c].windows.removeAll { $0 == id }
        columns[c].weights[id] = nil
        columns.insert(Column(windows: [id], width: columns[c].width), at: c + 1)
    }
    /// Drop a moved window in the lower third of another visible tile.
    @discardableResult
    public mutating func dropBelow(_ id: Int, old: Rect, new: Rect, pointerX: Double, pointerY: Double,
                                   frames: [Int: Rect], screen: Rect) -> Bool {
        guard column(of: id) != nil,
              abs(old.width - new.width) < 6, abs(old.height - new.height) < 6,
              abs(old.x - new.x) > 12 || abs(old.y - new.y) > 12 else { return false }
        let candidates = frames.filter { target, frame in
            target != id && column(of: target) != nil && frame.intersectionArea(screen) > frame.area * 0.8 &&
            pointerX >= max(frame.x + frame.width * 0.15, screen.x) &&
            pointerX <= min(frame.x + frame.width * 0.85, screen.x + screen.width) &&
            pointerY >= frame.y + frame.height * 0.65 && pointerY <= min(frame.y + frame.height, screen.y + screen.height)
        }
        guard let target = candidates.sorted(by: { $0.key < $1.key }).first?.key else { return false }
        stack(id, below: target)
        return true
    }
    public mutating func stack(_ id: Int, below target: Int) {
        guard id != target, let source = column(of: id), column(of: target) != nil else { return }
        columns[source].windows.removeAll { $0 == id }
        columns[source].weights[id] = nil
        columns.removeAll { $0.windows.isEmpty }
        guard let destination = column(of: target), let row = columns[destination].windows.firstIndex(of: target) else { return }
        columns[destination].windows.insert(id, at: row + 1)
        columns[destination].weights = [:]
        focus(id)
    }
    public mutating func resize(_ id: Int, target: String) {
        guard let c = column(of: id) else { return }
        if target == "wider" || target == "narrower" {
            columns[c].width = min(1, max(0.2, columns[c].width + (target == "wider" ? 0.05 : -0.05)))
        } else if columns[c].windows.count > 1 {
            columns[c].weights[id] = min(5, max(0.2, (columns[c].weights[id] ?? 1) + (target == "taller" ? 0.2 : -0.2)))
        }
    }
    public mutating func resizeToFrame(_ id: Int, old: Rect, new: Rect, screen: Rect, gap: Double) {
        guard let c = column(of: id) else { return }
        if abs(old.width - new.width) > 6 {
            columns[c].width = min(1, max(0.2, (new.width + gap) / screen.width))
        }
        if columns[c].windows.count > 1, abs(old.height - new.height) > 6 {
            let others = columns[c].windows.filter { $0 != id }.reduce(0.0) { $0 + (columns[c].weights[$1] ?? 1) }
            let available = max(1, screen.height - gap * Double(columns[c].windows.count + 1))
            let fraction = min(0.85, max(0.1, new.height / available))
            columns[c].weights[id] = others * fraction / (1 - fraction)
        }
    }

    /// Returns nil when app size constraints cannot be satisfied, rather than overlapping a group.
    public mutating func frames(screen: Rect, gap: Double, center: Bool, minimumSizes: [Int: Rect] = [:]) -> [Int: Rect]? {
        let gap = min(max(0, gap), min(screen.width, screen.height) / 10)
        let availableWidth = screen.width - 2 * gap
        var positions: [(Double, Double)] = []
        var x = gap
        for column in columns {
            let minimum = column.windows.map { minimumSizes[$0]?.width ?? 1 }.max() ?? 1
            let width = max(minimum, min(availableWidth, screen.width * column.width - gap))
            guard width <= availableWidth else { return nil }
            positions.append((x, width)); x += width + gap
        }
        if center { centeredID = focused }
        let centered = focused != nil && centeredID == focused
        if let focused, let c = column(of: focused) {
            let (left, width) = positions[c]
            if centered { offset = left + width / 2 - screen.width / 2 }
            else if left < offset + gap { offset = left - gap }
            else if left + width > offset + screen.width - gap { offset = left + width - screen.width + gap }
        }
        if !centered { offset = max(0, min(offset, max(0, x - screen.width))) }
        var result: [Int: Rect] = [:]
        for (c, column) in columns.enumerated() {
            let available = screen.height - gap * Double(column.windows.count + 1)
            let minima = column.windows.map { max(1, minimumSizes[$0]?.height ?? 1) }
            guard minima.reduce(0,+) <= available else { return nil }
            let extra = available - minima.reduce(0,+)
            let totalWeight = column.windows.reduce(0.0) { $0 + (column.weights[$1] ?? 1) }
            var y = screen.y + gap
            for (row, id) in column.windows.enumerated() {
                let height = minima[row] + extra * (column.weights[id] ?? 1) / totalWeight
                result[id] = Rect(x: screen.x + positions[c].0 - offset, y: y, width: positions[c].1, height: height)
                y += height + gap
            }
        }
        return result
    }

    /// macOS needs a visible edge for parked windows. Never use this projection across displays.
    public static func desktopFrame(_ frame: Rect, screen: Rect, peek: Double = 32) -> Rect {
        var result = frame
        result.x = min(screen.x + screen.width - peek, max(screen.x - frame.width + peek, frame.x))
        return result
    }
}

public struct ScrollingPlan: Sendable {
    public init() {}
    public var logicalFrames: [Int: Rect] = [:]
    public var moves: [Move] = []
    public var parked: Set<Int> = []
    public var visible: Set<Int> = []
    public var messages: [String] = []
}

public struct ScrollingSession: Sendable {
    public var strip = ScrollingStrip()
    public init() {}
    public static func mode(on screen: Display, layout: Layout, displays: [Display]) -> String {
        LayoutScreens.mode(on: screen, layout: layout, displays: displays).rawValue
    }
    public static func targets(layout: Layout, displays: [Display]) -> [Display] {
        displays.filter { mode(on: $0, layout: layout, displays: displays) == "horizontal" && hasSafeEdge(on: $0, displays: displays) }
    }
    public static func target(layout: Layout, displays: [Display]) -> Display? { targets(layout: layout, displays: displays).first }
    private static func hasSafeEdge(on screen: Display, displays: [Display]) -> Bool {
        let r = screen.usable
        let others = displays.filter { $0.id != screen.id }
        let left = Rect(x: r.x - r.width + 32, y: r.y, width: r.width, height: r.height)
        let right = Rect(x: r.x + r.width - 32, y: r.y, width: r.width, height: r.height)
        return [left, right].contains(where: { candidate in others.allSatisfy { candidate.intersectionArea($0.frame) == 0 } })
    }
    /// Template matching and window indices are local to this display.
    public static func layout(_ layout: Layout, on screen: Display, displays: [Display]) -> Layout {
        var local = layout
        local.scrolling?.display = "uuid:" + screen.id
        local.scrolling?.displayModes = [:]
        local.scrolling?.tileOtherDisplays = false
        local.scrolling?.excludedBundleIDs += layout.scrolling?.displayExcludedBundleIDs["uuid:" + screen.id] ?? []
        local.scrolling?.displayExcludedBundleIDs = [:]
        local.placements = layout.placements.filter {
            Displays.resolve($0.display, in: displays, fallback: layout.fallbackToPrimary)?.id == screen.id
        }
        return local
    }
    /// A neighboring display forces overflow to the opposite edge. That mapping
    /// is discontinuous and cannot be animated as a coherent horizontal strip.
    public static func supportsContinuousMotion(on screen: Display, displays: [Display]) -> Bool {
        let r = screen.usable
        let probes = [Rect(x: r.x - r.width + 32, y: r.y, width: r.width, height: r.height),
                      Rect(x: r.x + r.width - 32, y: r.y, width: r.width, height: r.height)]
        return probes.allSatisfy { probe in
            displays.filter { $0.id != screen.id }.allSatisfy { probe.intersectionArea($0.frame) == 0 }
        }
    }
    /// Keep the 32-point parked edges (and their shadows) outside usable tiles.
    public static func viewport(on screen: Display, neighborPreview: Double = 120) -> Rect {
        let inset = min(48.0 + max(0, neighborPreview), screen.usable.width / 4)
        return Rect(x: screen.usable.x + inset, y: screen.usable.y,
                    width: screen.usable.width - 2 * inset, height: screen.usable.height)
    }
    public static func project(_ frame: Rect, onto screen: Display, displays: [Display]) -> Rect {
        let natural = ScrollingStrip.desktopFrame(frame, screen: screen.usable)
        let others = displays.filter { $0.id != screen.id }
        let r = screen.usable
        let leftEdge = Rect(x: r.x - r.width + 32, y: r.y, width: r.width, height: r.height)
        let rightEdge = Rect(x: r.x + r.width - 32, y: r.y, width: r.width, height: r.height)
        let leftSafe = others.allSatisfy { leftEdge.intersectionArea($0.frame) == 0 }
        let rightSafe = others.allSatisfy { rightEdge.intersectionArea($0.frame) == 0 }
        if (natural.x >= r.x || leftSafe) && (natural.x + natural.width <= r.x + r.width || rightSafe) { return natural }
        // Choose the edge for the whole column, not each row's height. Otherwise
        // an upper row can park left of a staggered monitor while its lower row
        // parks right, and the group re-enters from opposite sides.
        var parked = natural
        if leftSafe { parked.x = r.x - frame.width + 32 }
        else if rightSafe { parked.x = r.x + r.width - 32 }
        return parked
    }
    public mutating func plan(layout: Layout, windows: [WindowDescriptor], displays: [Display], gap: Double,
                              focused: Int?, minimumSizes: [Int: Rect] = [:], center: Bool = false) -> ScrollingPlan {
        var result = ScrollingPlan()
        guard let options = layout.scrolling else { return result }
        guard let screen = Self.target(layout: layout, displays: displays) else {
            result.messages = ["The scrolling display is missing or has no safe outside edge for parked windows. No windows were moved."]
            return result
        }
        if !Self.supportsContinuousMotion(on: screen, displays: displays), options.animationDuration > 0 {
            result.messages.append("Instant navigation: a neighboring display blocks a scrolling edge. Arrange displays vertically to enable sideways animation.")
        }
        // A strip owns one display. Template rules supply widths/groups, not
        // permission to pull matching apps away from another display.
        let windows = windows.filter {
            !options.excludedBundleIDs.contains($0.bundleID) &&
            $0.frame.intersectionArea(screen.frame) > 0 &&
            Displays.containing($0.frame, in: displays)?.id == screen.id
        }
        var template = layout; template.scrolling = nil; template.adaptive = false
        // A strip has one display; stale fixed-layout assignments must not
        // prevent its width/group rules from matching windows.
        for index in template.placements.indices { template.placements[index].display = "uuid:" + screen.id }
        let matches = LayoutPlanner.plan(template, windows: windows, displays: displays, gap: 0)
        var ids = matches.moves.map(\.windowID)
        if options.allWindows { ids += windows.map(\.id).filter { !ids.contains($0) } }
        var groups: [Int: Int] = [:]
        var widths: [Int: Double] = [:]
        // A plain app rule also supplies the width for additional windows of
        // that app; explicit indexed/title rules below take precedence.
        for window in windows where ids.contains(window.id) {
            if let rule = layout.placements.first(where: { $0.bundleID == window.bundleID && $0.titleContains.isEmpty && $0.windowIndex == 0 }) {
                widths[window.id] = max(0.2, min(1, rule.frame.width))
            }
        }
        for placement in layout.placements {
            let candidates = windows.filter { $0.bundleID == placement.bundleID && (placement.titleContains.isEmpty || $0.title.localizedCaseInsensitiveContains(placement.titleContains)) }
            guard candidates.indices.contains(placement.windowIndex) else { continue }
            let id = candidates[placement.windowIndex].id
            guard ids.contains(id) else { continue }
            groups[id] = placement.scrollColumn
            widths[id] = max(0.2, min(1, placement.frame.width))
        }
        strip.reconcile(ids, width: options.width, groups: groups, widths: widths)
        if let focused { strip.focus(focused) }
        let viewport = Self.viewport(on: screen, neighborPreview: options.neighborPreview)
        var frames = strip.frames(screen: viewport, gap: layout.applyGap ? gap : 0,
                                  center: center || options.centerFocus, minimumSizes: minimumSizes)
        if frames == nil, strip.columns.contains(where: { $0.windows.count > 1 }) {
            for id in strip.ids { strip.ungroup(id) }
            frames = strip.frames(screen: viewport, gap: layout.applyGap ? gap : 0,
                                  center: center || options.centerFocus, minimumSizes: minimumSizes)
            result.messages.append("A group exceeded app minimum sizes; its windows were separated into columns.")
        }
        guard let frames else {
            result.messages = ["This scrolling group does not fit the app minimum sizes. Ungroup windows or increase available space."]
            return result
        }
        result.logicalFrames = frames
        for id in strip.ids {
            guard let frame = frames[id] else { continue }
            if frame.x < screen.usable.x || frame.x + frame.width > screen.usable.x + screen.usable.width {
                result.parked.insert(id)
            }
            let desktop = Self.project(frame, onto: screen, displays: displays)
            // Partially visible neighbors still belong above fully parked windows.
            if desktop.intersectionArea(screen.usable) > 33 * min(desktop.height, screen.usable.height) {
                result.visible.insert(id)
            }
            result.moves.append(Move(windowID: id, frame: desktop))
        }
        return result
    }
}

/// Interpolate the logical strip before parking it, so visible columns share one
/// translation instead of crossing each other from their collapsed parked positions.
public struct ScrollingMotion: Sendable {
    public let starts: [Int: Rect]
    public let ends: [Int: Rect]
    public let screen: Display
    public let displays: [Display]
    private var windowScreens: [Int: Display] = [:]
    public init(starts: [Int: Rect], ends: [Int: Rect], screen: Display, displays: [Display]) {
        self.starts = starts; self.ends = ends; self.screen = screen; self.displays = displays
    }
    public init(parts: [ScrollingMotion]) {
        precondition(!parts.isEmpty)
        starts = parts.reduce(into: [:]) { $0.merge($1.starts) { _, new in new } }
        ends = parts.reduce(into: [:]) { $0.merge($1.ends) { _, new in new } }
        screen = parts[0].screen; displays = parts[0].displays
        for part in parts { for id in part.ends.keys { windowScreens[id] = part.screen } }
    }
    public func logicalFrames(progress: Double) -> [Int: Rect] {
        Dictionary(uniqueKeysWithValues: ends.map { id, end in
            (id, starts[id].map { WindowTransition.frame(from: $0, to: end, progress: progress) } ?? end)
        })
    }
    public func frame(for id: Int, progress: Double) -> Rect? {
        guard let start = starts[id], let end = ends[id] else { return nil }
        let logical = WindowTransition.frame(from: start, to: end, progress: progress)
        return ScrollingSession.project(logical, onto: windowScreens[id] ?? screen, displays: displays)
    }
}
