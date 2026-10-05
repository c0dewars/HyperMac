import Foundation

@main
struct Benchmark {
    static func main() {
        let screen = Rect(x: 0, y: 0, width: 3440, height: 1440)
        for count in [5, 10, 20] {
            var tree = BSPTree()
            tree.reconcile(windowIDs: Array(1...count), screen: screen)
            let start = ProcessInfo.processInfo.systemUptime
            var completed = 0
            for _ in 0..<10_000 {
                let frames = tree.frames(screen: screen, gap: 12, minimumSizes: [:])
                precondition(frames?.count == count)
                completed += frames?.count ?? 0
            }
            let microseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000_000 / 10_000
            print("\(count) windows: \(String(format: "%.2f", microseconds)) µs per BSP plan (\(completed) frames). AX, rendering and event latency excluded.")
        }
    }
}
