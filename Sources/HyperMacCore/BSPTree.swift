import Foundation

/// Session-local split topology. Existing branches survive insertion and removal.
public struct BSPTree: Sendable {
    private indirect enum Node: Sendable {
        case leaf(Int)
        case split(Bool, Double, Node, Node) // true: left/right; false: top/bottom

        var ids: [Int] {
            switch self {
            case .leaf(let id): return [id]
            case .split(_, _, let a, let b): return a.ids + b.ids
            }
        }
        func retaining(_ live: Set<Int>) -> Node? {
            switch self {
            case .leaf(let id): return live.contains(id) ? self : nil
            case .split(let axis, let ratio, let a, let b):
                let left = a.retaining(live), right = b.retaining(live)
                if let left, let right { return .split(axis, ratio, left, right) }
                return left ?? right
            }
        }
        func inserting(_ id: Int, at target: Int, horizontal: Bool) -> Node {
            switch self {
            case .leaf(let old): return old == target ? .split(horizontal, 0.5, self, .leaf(id)) : self
            case .split(let axis, let ratio, let a, let b):
                return .split(axis, ratio, a.inserting(id, at: target, horizontal: horizontal),
                              b.inserting(id, at: target, horizontal: horizontal))
            }
        }
        func swapping(_ first: Int, _ second: Int) -> Node {
            switch self {
            case .leaf(let id): return .leaf(id == first ? second : id == second ? first : id)
            case .split(let axis, let ratio, let a, let b):
                return .split(axis, ratio, a.swapping(first, second), b.swapping(first, second))
            }
        }
        func resizing(_ id: Int, horizontal: Bool, delta: Double) -> (Node, Bool) {
            guard case .split(let axis, let ratio, let a, let b) = self else { return (self, false) }
            let inFirst = a.ids.contains(id)
            let child = (inFirst ? a : b).resizing(id, horizontal: horizontal, delta: delta)
            if child.1 { return (.split(axis, ratio, inFirst ? child.0 : a, inFirst ? b : child.0), true) }
            guard axis == horizontal, ids.contains(id) else { return (self, false) }
            let next = min(0.9, max(0.1, ratio + (inFirst ? delta : -delta)))
            return (.split(axis, next, a, b), true)
        }
        func dragging(_ id: Int, horizontal: Bool, boundary: Double, delta: Double,
                      area: Rect, gap: Double, sizes: [Int: Rect]) -> Node {
            guard case .split(let axis, let ratio, let a, let b) = self else { return self }
            let am = a.minimum(sizes, gap: gap), bm = b.minimum(sizes, gap: gap)
            let extent = axis ? area.width : area.height
            let cut = min(extent - (axis ? bm.0 : bm.1), max(axis ? am.0 : am.1, extent * ratio))
            let position = (axis ? area.x : area.y) + cut
            if axis == horizontal, ids.contains(id), abs(position - boundary) <= 5 {
                return .split(axis, min(0.9, max(0.1, (cut + delta) / extent)), a, b)
            }
            var first = area, second = area
            if axis { first.width = cut; second.x += cut; second.width -= cut }
            else { first.height = cut; second.y += cut; second.height -= cut }
            return .split(axis, ratio,
                a.dragging(id, horizontal: horizontal, boundary: boundary, delta: delta, area: first, gap: gap, sizes: sizes),
                b.dragging(id, horizontal: horizontal, boundary: boundary, delta: delta, area: second, gap: gap, sizes: sizes))
        }
        func minimum(_ sizes: [Int: Rect], gap: Double) -> (Double, Double) {
            switch self {
            case .leaf(let id): return ((sizes[id]?.width ?? 1) + gap, (sizes[id]?.height ?? 1) + gap)
            case .split(let axis, _, let a, let b):
                let x = a.minimum(sizes, gap: gap), y = b.minimum(sizes, gap: gap)
                return axis ? (x.0 + y.0, max(x.1, y.1)) : (max(x.0, y.0), x.1 + y.1)
            }
        }
        func render(_ area: Rect, gap: Double, sizes: [Int: Rect], into result: inout [Int: Rect]) -> Bool {
            let required = minimum(sizes, gap: gap)
            guard required.0 <= area.width + 0.001, required.1 <= area.height + 0.001 else { return false }
            switch self {
            case .leaf(let id):
                result[id] = Rect(x: 0, y: 0, width: 1, height: 1).resolved(in: area, gap: gap)
                return true
            case .split(let axis, let ratio, let a, let b):
                let am = a.minimum(sizes, gap: gap), bm = b.minimum(sizes, gap: gap)
                let extent = axis ? area.width : area.height
                let cut = min(extent - (axis ? bm.0 : bm.1), max(axis ? am.0 : am.1, extent * ratio))
                var first = area, second = area
                if axis { first.width = cut; second.x += cut; second.width -= cut }
                else { first.height = cut; second.y += cut; second.height -= cut }
                return a.render(first, gap: gap, sizes: sizes, into: &result)
                    && b.render(second, gap: gap, sizes: sizes, into: &result)
            }
        }
    }
    private var root: Node?
    public init() {}
    public var windowIDs: [Int] { root?.ids ?? [] }

    public mutating func reconcile(windowIDs: [Int], screen: Rect) {
        root = root?.retaining(Set(windowIDs))
        for id in windowIDs where !(root?.ids.contains(id) ?? false) {
            guard let node = root else { root = .leaf(id); continue }
            let regions = frames(screen: screen, gap: 0) ?? [:]
            let target = node.ids.max { (regions[$0]?.area ?? 0) < (regions[$1]?.area ?? 0) } ?? node.ids[0]
            let area = regions[target] ?? screen
            root = node.inserting(id, at: target, horizontal: area.width >= area.height)
        }
    }
    public func frames(screen: Rect, gap: Double, minimumSizes: [Int: Rect] = [:]) -> [Int: Rect]? {
        guard let root else { return [:] }
        var result: [Int: Rect] = [:]
        return root.render(screen, gap: max(0, gap), sizes: minimumSizes, into: &result) ? result : nil
    }
    public mutating func resizeToFrame(_ id: Int, from old: Rect, to new: Rect, screen: Rect,
                                       gap: Double, minimumSizes: [Int: Rect] = [:]) {
        let edges: [(Bool, Double, Double)] = [
            (true, old.x - gap / 2, new.x - old.x),
            (true, old.x + old.width + gap / 2, new.x + new.width - old.x - old.width),
            (false, old.y - gap / 2, new.y - old.y),
            (false, old.y + old.height + gap / 2, new.y + new.height - old.y - old.height)]
        for (horizontal, boundary, delta) in edges where abs(delta) > 6 {
            root = root?.dragging(id, horizontal: horizontal, boundary: boundary, delta: delta,
                                 area: screen, gap: gap, sizes: minimumSizes)
        }
    }
    @discardableResult public mutating func swap(_ first: Int, _ second: Int) -> Bool {
        guard windowIDs.contains(first), windowIDs.contains(second) else { return false }
        root = root?.swapping(first, second)
        return true
    }
    @discardableResult public mutating func resize(_ id: Int, target: String) -> Bool {
        guard let root, ["wider", "narrower", "taller", "shorter"].contains(target) else { return false }
        let (next, changed) = root.resizing(id, horizontal: target == "wider" || target == "narrower",
            delta: target == "wider" || target == "taller" ? 0.05 : -0.05)
        self.root = next
        return changed
    }
}
