import Foundation

/// All coordinates are logical points in a global top-left coordinate system.
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var area: Double { max(0, width) * max(0, height) }
    public func intersectionArea(_ other: Rect) -> Double {
        max(0, min(x + width, other.x + other.width) - max(x, other.x)) *
        max(0, min(y + height, other.y + other.height) - max(y, other.y))
    }

    public func normalized(in screen: Rect) -> Rect {
        Rect(x: (x - screen.x) / screen.width, y: (y - screen.y) / screen.height,
             width: width / screen.width, height: height / screen.height)
    }

    public func resolved(in screen: Rect, gap: Double) -> Rect {
        let raw = Rect(x: screen.x + x * screen.width, y: screen.y + y * screen.height,
                       width: width * screen.width, height: height * screen.height)
        let inset = max(0, min(gap / 2, min(raw.width, raw.height) / 4))
        return Rect(x: (raw.x + inset).rounded(), y: (raw.y + inset).rounded(),
                    width: max(1, (raw.width - inset * 2).rounded()),
                    height: max(1, (raw.height - inset * 2).rounded()))
    }
}

public struct Display: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var builtIn: Bool
    public var primary: Bool
    public var frame: Rect
    public var usable: Rect

    public init(id: String, name: String, builtIn: Bool, primary: Bool, frame: Rect, usable: Rect) {
        self.id = id; self.name = name; self.builtIn = builtIn; self.primary = primary
        self.frame = frame; self.usable = usable
    }
}

public enum Displays {
    /// Roles are portable. External numbering follows physical left-to-right order.
    public static func resolve(_ selector: String, in displays: [Display], fallback: Bool) -> Display? {
        let externals = displays.filter { !$0.builtIn }.sorted {
            if $0.frame.x != $1.frame.x { return $0.frame.x < $1.frame.x }
            if $0.frame.y != $1.frame.y { return $0.frame.y < $1.frame.y }
            return $0.id < $1.id
        }
        let found: Display?
        switch selector {
        case "built-in": found = displays.first { $0.builtIn }
        case "primary": found = displays.first { $0.primary }
        case "external-1": found = externals.first
        case "external-2": found = externals.count > 1 ? externals[1] : nil
        default: found = displays.first { "uuid:" + $0.id == selector }
        }
        return found ?? (fallback ? displays.first { $0.primary } ?? displays.first : nil)
    }

    public static func containing(_ rect: Rect, in displays: [Display]) -> Display? {
        displays.max { rect.intersectionArea($0.frame) < rect.intersectionArea($1.frame) }
    }
}

public enum TileAlgorithm: String, Codable, CaseIterable, Sendable {
    case bsp, adaptive, columns, masterStack
}

public enum Tiler {
    public static func frames(count: Int, screen: Rect, algorithm: TileAlgorithm, gap: Double) -> [Rect] {
        guard count > 0, screen.width > 0, screen.height > 0 else { return [] }
        if count == 1 { return [Rect(x: 0, y: 0, width: 1, height: 1).resolved(in: screen, gap: gap)] }
        if algorithm == .bsp {
            var tree = BSPTree()
            tree.reconcile(windowIDs: Array(0..<count), screen: screen)
            if let result = tree.frames(screen: screen, gap: gap) { return (0..<count).compactMap { result[$0] } }
        }
        if algorithm == .masterStack {
            var result = [Rect(x: 0, y: 0, width: 0.6, height: 1)]
            for i in 0..<(count - 1) {
                result.append(Rect(x: 0.6, y: Double(i) / Double(count - 1),
                                   width: 0.4, height: 1 / Double(count - 1)))
            }
            return result.map { $0.resolved(in: screen, gap: gap) }
        }
        let columns = algorithm == .columns ? count : min(count, max(1,
            Int((sqrt(Double(count) * screen.width / screen.height / 1.5)).rounded())))
        var result: [Rect] = []
        var remaining = count
        for column in 0..<columns {
            let rows = (remaining + (columns - column) - 1) / (columns - column)
            for row in 0..<rows {
                result.append(Rect(x: Double(column) / Double(columns), y: Double(row) / Double(rows),
                                   width: 1 / Double(columns), height: 1 / Double(rows))
                    .resolved(in: screen, gap: gap))
            }
            remaining -= rows
        }
        return result
    }
}

/// Cubic ease-out with exact endpoints; frame coordinates stay in logical points.
public enum WindowTransition {
    public static func frame(from start: Rect, to end: Rect, progress: Double) -> Rect {
        let t = min(1, max(0, progress))
        let eased = 1 - pow(1 - t, 3)
        func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * eased }
        return Rect(x: blend(start.x, end.x), y: blend(start.y, end.y),
                    width: blend(start.width, end.width), height: blend(start.height, end.height))
    }
}
