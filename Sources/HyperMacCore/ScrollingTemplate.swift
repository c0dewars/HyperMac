import Foundation

/// Edits saved scrolling rules using the same column order as the live strip.
public enum ScrollingTemplate {
    public static func columns(_ placements: [Placement]) -> [[Int]] {
        var result: [[Int]] = []
        for i in placements.indices {
            if let group = placements[i].scrollColumn,
               let c = result.firstIndex(where: { placements[$0[0]].scrollColumn == group && placements[$0[0]].display == placements[i].display }) {
                result[c].append(i)
            } else { result.append([i]) }
        }
        return result
    }

    public static func frames(_ placements: [Placement]) -> [Int: Rect] {
        var result: [Int: Rect] = [:]
        var offsets: [String: Double] = [:]
        for column in columns(placements) {
            let display = placements[column[0]].display
            let x = offsets[display] ?? 0
            let width = placements[column[0]].frame.width
            for (row, index) in column.enumerated() {
                result[index] = Rect(x: x, y: Double(row) / Double(column.count),
                    width: width, height: 1 / Double(column.count))
            }
            offsets[display] = x + width
        }
        return result
    }

    public static func resize(_ placements: inout [Placement], index: Int, width: Double, snap: Bool) {
        guard placements.indices.contains(index), width.isFinite else { return }
        let value = min(1, max(0.2, snap ? (width * 20).rounded() / 20 : width))
        let group = placements[index].scrollColumn
        for i in placements.indices where i == index || (group != nil && placements[i].scrollColumn == group && placements[i].display == placements[index].display) {
            placements[i].frame.width = value
        }
    }

    /// Drop in a tile's lower third to stack; otherwise insert a separate column beside it.
    @discardableResult public static func move(_ placements: inout [Placement], index: Int, x: Double, y: Double) -> Int {
        guard placements.indices.contains(index), x.isFinite, y.isFinite else { return index }
        let geometry = frames(placements)
        let target = placements.indices.first { i in
            guard i != index, placements[i].display == placements[index].display, let frame = geometry[i] else { return false }
            return x >= frame.x && x <= frame.x + frame.width && y >= frame.y && y <= frame.y + frame.height
        }
        var item = placements[index]
        var insertion: Int
        if let target, let frame = geometry[target], y >= frame.y + frame.height * 0.65 {
            let group = placements[target].scrollColumn ?? ((placements.compactMap(\.scrollColumn).max() ?? -1) + 1)
            placements[target].scrollColumn = group
            item.scrollColumn = group
            item.frame.width = placements[target].frame.width
            insertion = target + 1
        } else {
            item.scrollColumn = nil
            let ordered = columns(placements).filter { placements[$0[0]].display == item.display }
            if let column = ordered.first(where: { column in
                let frame = geometry[column[0]]!
                return x < frame.x + frame.width / 2
            }) { insertion = column.min()! }
            else { insertion = (ordered.last?.max() ?? (placements.count - 1)) + 1 }
        }
        placements.remove(at: index)
        if index < insertion { insertion -= 1 }
        insertion = min(placements.count, max(0, insertion))
        placements.insert(item, at: insertion)
        return insertion
    }
}
