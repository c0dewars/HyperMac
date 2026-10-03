import Foundation

public enum WindowDirection: String, CaseIterable, Sendable { case left, right, up, down }

public enum WindowNavigation {
    /// Prefer windows in the same row/column, then the nearest center. Stable IDs break ties.
    public static func neighbor(of source: WindowDescriptor, among windows: [WindowDescriptor],
                                direction: WindowDirection) -> WindowDescriptor? {
        let a = source.frame
        let horizontal = direction == .left || direction == .right
        let candidates = windows.filter { window in
            guard window.id != source.id else { return false }
            let b = window.frame
            switch direction {
            case .left: return b.x + b.width / 2 < a.x + a.width / 2 - 1
            case .right: return b.x + b.width / 2 > a.x + a.width / 2 + 1
            case .up: return b.y + b.height / 2 < a.y + a.height / 2 - 1
            case .down: return b.y + b.height / 2 > a.y + a.height / 2 + 1
            }
        }
        func score(_ window: WindowDescriptor) -> (Int, Double, Int) {
            let b = window.frame
            let overlap = horizontal
                ? min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                : min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
            let dx = b.x + b.width / 2 - a.x - a.width / 2
            let dy = b.y + b.height / 2 - a.y - a.height / 2
            return (overlap > 0 ? 0 : 1, dx * dx + dy * dy, window.id)
        }
        return candidates.min { score($0) < score($1) }
    }

    public static func resized(_ frame: Rect, in bounds: Rect, target: String) -> Rect {
        var result = frame
        switch target {
        case "wider": result.width += 100
        case "narrower": result.width -= 100
        case "taller": result.height += 100
        case "shorter": result.height -= 100
        default: return frame
        }
        result.width = max(100, result.width)
        result.height = max(100, result.height)
        return clamped(result, in: bounds)
    }

    public static func clamped(_ frame: Rect, in bounds: Rect) -> Rect {
        var result = frame
        result.width = min(bounds.width, max(1, result.width))
        result.height = min(bounds.height, max(1, result.height))
        result.x = max(bounds.x, min(result.x, bounds.x + bounds.width - result.width))
        result.y = max(bounds.y, min(result.y, bounds.y + bounds.height - result.height))
        return result
    }
}
