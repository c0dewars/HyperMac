import Foundation

/// An exterior stroke with one point of spare canvas for antialiasing.
/// The owner can occlude the panel without hiding its straight border edges.
public struct BorderGeometry {
    public let panel: Rect
    public let stroke: Rect

    public static func outside(window: Rect, width: Double) -> BorderGeometry {
        let width = max(0, width)
        let margin = width + 1
        return BorderGeometry(
            panel: Rect(x: window.x - margin, y: window.y - margin,
                        width: window.width + 2 * margin, height: window.height + 2 * margin),
            stroke: Rect(x: 1 + width / 2, y: 1 + width / 2,
                         width: window.width + width, height: window.height + width))
    }
}
