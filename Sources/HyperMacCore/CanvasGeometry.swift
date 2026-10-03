import Foundation

public enum CanvasGeometry {
    /// Convert a dragged global rectangle back to a bounded proportional placement.
    public static func placement(_ global: Rect, on display: Display, snap: Bool) -> Rect {
        var r = global.normalized(in: display.usable)
        if snap {
            func roundGrid(_ value: Double) -> Double { (value * 20).rounded() / 20 }
            r.x = roundGrid(r.x); r.y = roundGrid(r.y)
            r.width = roundGrid(r.width); r.height = roundGrid(r.height)
        }
        r.width = min(1, max(0.05, r.width)); r.height = min(1, max(0.05, r.height))
        r.x = min(1 - r.width, max(0, r.x)); r.y = min(1 - r.height, max(0, r.y))
        return r
    }

    public static func target(for rect: Rect, displays: [Display]) -> Display? {
        let cx = rect.x + rect.width / 2; let cy = rect.y + rect.height / 2
        return displays.first {
            cx >= $0.usable.x && cx <= $0.usable.x + $0.usable.width &&
            cy >= $0.usable.y && cy <= $0.usable.y + $0.usable.height
        } ?? displays.max { rect.intersectionArea($0.usable) < rect.intersectionArea($1.usable) }
    }
}
