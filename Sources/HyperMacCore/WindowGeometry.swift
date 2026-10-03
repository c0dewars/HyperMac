import Foundation

public enum WindowGeometry {
    public static func sameVisibleWindow(_ ax: Rect, _ server: Rect) -> Bool {
        guard ax.area > 0, server.area > 0 else { return false }
        let overlap = ax.intersectionArea(server) / max(ax.area, server.area)
        return overlap >= 0.85 && abs(ax.x - server.x) <= 48 && abs(ax.y - server.y) <= 48
            && abs(ax.width - server.width) <= 96 && abs(ax.height - server.height) <= 96
    }
}
