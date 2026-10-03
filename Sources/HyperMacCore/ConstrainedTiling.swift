import Foundation

extension Tiler {
    /// Keep the selected layout when it fits. Otherwise redistribute contiguous
    /// groups into columns with enough room for the sizes the apps actually accept.
    public static func fittingFrames(minimumSizes: [Rect], screen: Rect,
                                     algorithm: TileAlgorithm, gap: Double) -> [Rect]? {
        let count = minimumSizes.count
        guard count > 0 else { return [] }
        let gap = max(0, gap)
        let preferred = frames(count: count, screen: screen, algorithm: algorithm, gap: gap)
        func fits(_ frames: [Rect]) -> Bool {
            frames.count == count && zip(frames, minimumSizes).allSatisfy {
                $0.width + 0.5 >= $1.width && $0.height + 0.5 >= $1.height
            }
        }
        if fits(preferred) { return preferred }
        var best: [Rect]?
        var bestScore = Double.infinity
        var visited = 0
        func evaluate(_ groups: [Range<Int>]) {
            let widths = groups.map { group in group.map { minimumSizes[$0].width + gap }.max() ?? 0 }
            let widthSum = widths.reduce(0, +)
            guard widthSum <= screen.width else { return }
            var result = Array(repeating: Rect(x: 0, y: 0, width: 0, height: 0), count: count)
            var x = screen.x
            for (column, group) in groups.enumerated() {
                let heightSum = group.reduce(0.0) { $0 + minimumSizes[$1].height + gap }
                guard heightSum <= screen.height else { return }
                let width = widths[column] + (screen.width - widthSum) / Double(groups.count)
                var y = screen.y
                for index in group {
                    let height = minimumSizes[index].height + gap + (screen.height - heightSum) / Double(group.count)
                    result[index] = Rect(x: x + gap / 2, y: y + gap / 2,
                                         width: width - gap, height: height - gap)
                    y += height
                }
                x += width
            }
            // Prefer shapes closest to the selected algorithm, without overlap.
            let score = zip(result, preferred).reduce(0.0) { sum, pair in
                let (a, b) = pair
                return sum + abs(a.width - b.width) + abs(a.height - b.height)
                    + 0.25 * (abs(a.x - b.x) + abs(a.y - b.y))
            }
            if score < bestScore { best = result; bestScore = score }
        }
        // Include balanced choices for large window counts before bounded search.
        for columns in 1...count {
            var groups: [Range<Int>] = []
            var start = 0
            for column in 0..<columns {
                let rows = (count - start + columns - column - 1) / (columns - column)
                groups.append(start..<(start + rows)); start += rows
            }
            evaluate(groups)
        }
        func search(_ start: Int, _ groups: [Range<Int>], _ usedWidth: Double) {
            guard visited < 4096 else { return }
            visited += 1
            if start == count { evaluate(groups); return }
            var height = 0.0
            var width = 0.0
            for end in (start + 1)...count {
                height += minimumSizes[end - 1].height + gap
                width = max(width, minimumSizes[end - 1].width + gap)
                if height > screen.height { break }
                if usedWidth + width <= screen.width {
                    search(end, groups + [start..<end], usedWidth + width)
                }
            }
        }
        search(0, [], 0)
        return best
    }
}
