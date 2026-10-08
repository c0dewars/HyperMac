// Run with Command Line Tools (no XCTest required):
// swiftc Sources/HyperMacCore/*.swift scripts/check-shortcuts.swift -o /tmp/hypermac-shortcut-checks
// /tmp/hypermac-shortcut-checks
import Foundation

@main
enum ShortcutChecks {
    static func main() throws {
        for direction in WindowDirection.allCases {
            var shortcut = Shortcut(key: direction.rawValue, action: .launch, target: "com.apple.finder")
            shortcut.selectAction(.swapWindow)
            precondition(shortcut.target == direction.rawValue)
            shortcut.selectAction(.focusWindow)
            precondition(shortcut.target == direction.rawValue)
        }
        var customDirection = Shortcut(key: "k", action: .focusWindow, target: "up")
        customDirection.selectAction(.swapWindow)
        precondition(customDirection.target == "up")
        var customResize = Shortcut(key: "equal", action: .resizeWindow, target: "narrower")
        customResize.selectAction(.resizeWindow)
        precondition(customResize.target == "narrower")
        print("Passed: action editing preserves directions and custom resize targets; arrow actions choose their own direction.")
        let start = Rect(x: -500, y: 40, width: 800, height: 600)
        let end = Rect(x: 200, y: 90, width: 400, height: 900)
        precondition(WindowTransition.frame(from: start, to: end, progress: 0) == start)
        precondition(WindowTransition.frame(from: start, to: end, progress: 1) == end)
        var previous = start
        for tick in 1...60 {
            let frame = WindowTransition.frame(from: start, to: end, progress: Double(tick) / 60)
            precondition(frame.x >= previous.x && frame.width <= previous.width && frame.height >= previous.height)
            precondition(frame.x <= end.x && frame.width >= end.width && frame.height <= end.height)
            previous = frame
        }
        let display = Display(id: "laptop", name: "Laptop", builtIn: true, primary: true,
            frame: Rect(x: 0, y: 0, width: 1200, height: 800), usable: Rect(x: 0, y: 20, width: 1200, height: 780))
        let leftPlacement = Placement(bundleID: "one", display: "primary", frame: Rect(x: 0, y: 0, width: 0.5, height: 1))
        let rightPlacement = Placement(bundleID: "two", display: "primary", frame: Rect(x: 0.5, y: 0, width: 0.5, height: 1))
        var adaptive = Layout(name: "Adaptive check", placements: [leftPlacement, rightPlacement])
        let one = WindowDescriptor(id: 1001, bundleID: "one", title: "", frame: display.usable)
        let two = WindowDescriptor(id: 1002, bundleID: "two", title: "", frame: display.usable)
        let fixed = LayoutPlanner.plan(adaptive, windows: [one], displays: [display], gap: 12)
        precondition(fixed.moves[0].frame.width == 588, "Fixed layout retains empty slots")
        adaptive.adaptive = true
        for windows in [[one, two], [one], [one, two], [], [two]] {
            let plan = LayoutPlanner.plan(adaptive, windows: windows, displays: [display], gap: 12)
            precondition(plan.moves.count == windows.count)
            if windows.count == 1 { precondition(plan.moves[0].frame.width == 1188 && plan.moves[0].frame.height == 768) }
            if windows.count == 2 { precondition(plan.moves[0].frame.intersectionArea(plan.moves[1].frame) == 0) }
        }
        adaptive.placements[1].display = "external-1"
        precondition(LayoutPlanner.plan(adaptive, windows: [one,two], displays: [display], gap: 12).moves.count == 1)
        adaptive.fallbackToPrimary = true
        precondition(LayoutPlanner.plan(adaptive, windows: [one,two], displays: [display], gap: 12).moves.count == 2)
        adaptive.placements.append(leftPlacement)
        precondition(LayoutPlanner.plan(adaptive, windows: [one,two], displays: [display], gap: 12).moves.count == 2)
        let impossible = LayoutPlanner.plan(adaptive, windows: [one], displays: [display], gap: 12,
            minimumSizes: [one.id: Rect(x: 0, y: 0, width: 2000, height: 100)])
        precondition(impossible.moves.isEmpty && !impossible.messages.isEmpty)
        print("Passed: adaptive 2→1→2→0→1 reflow, fixed-slot preservation, missing-display fallback, duplicate rules and impossible fit.")
        var mouseTree = BSPTree()
        let mouseScreen = Rect(x: 0, y: 0, width: 1200, height: 800)
        mouseTree.reconcile(windowIDs: [1,2], screen: mouseScreen)
        let beforeMouse = mouseTree.frames(screen: mouseScreen, gap: 12)!
        let mouseFrame = beforeMouse[1]!
        var dragged = mouseFrame; dragged.width += 120
        mouseTree.resizeToFrame(1, from: mouseFrame, to: dragged, screen: mouseScreen, gap: 12)
        let afterMouse = mouseTree.frames(screen: mouseScreen, gap: 12)!
        precondition(abs(afterMouse[1]!.width - dragged.width) < 1)
        precondition(afterMouse[1]!.intersectionArea(afterMouse[2]!) == 0)
        precondition(afterMouse[2]!.width < beforeMouse[2]!.width)
        let profile = MonitorProfile(name: "Dock", displayIDs: ["internal", "external"], layoutName: "Office")
        precondition(profile.matches(["external", "internal"]))
        precondition(!profile.matches(["internal"]) && !profile.matches(["internal", "external", "extra"]))
        var disabledProfile = profile; disabledProfile.enabled = false
        precondition(!disabledProfile.matches(["external", "internal"]))
        print("Passed: mouse split resizing preserves neighbor geometry; monitor profiles match exact unordered topology and respect disable.")
        let starter = Configuration.starter
        var invalidAnimation = starter
        invalidAnimation.animationDuration = -1
        do { try invalidAnimation.validate(); fatalError("Negative duration accepted") } catch is ConfigError {}
        print("Passed: eased transitions have exact endpoints, monotonic motion, no overshoot, and validated duration.")
        precondition(starter.automaticTiling && starter.borderEnabled)
        precondition(starter.borderColor == "#A6F3C2")
        precondition(starter.excludedBundleIDs == ["local.hypermac.app", "com.apple.systempreferences"])
        var oldJSON = try JSONSerialization.jsonObject(with: starter.encoded()) as! [String: Any]
        oldJSON.removeValue(forKey: "borderColor")
        oldJSON["automaticTiling"] = false
        let oldConfig = try Configuration.decode(JSONSerialization.data(withJSONObject: oldJSON))
        precondition(!oldConfig.automaticTiling && oldConfig.borderColor == "#A6F3C2")
        var badBorder = starter
        badBorder.borderColor = "#NOTHEX"
        do { try badBorder.validate(); fatalError("Invalid border colors must be rejected") }
        catch is ConfigError {}
        try starter.validate() // Also checks every physical key and duplicate modifier combination.
        var profileConfig = starter
        profileConfig.monitorProfiles = [MonitorProfile(name: "Laptop", displayIDs: ["one"], layoutName: starter.layouts[0].name)]
        try profileConfig.validate()
        let decodedProfile = try Configuration.decode(profileConfig.encoded())
        precondition(decodedProfile == profileConfig)
        profileConfig.monitorProfiles.append(profileConfig.monitorProfiles[0])
        do { try profileConfig.validate(); fatalError("Duplicate enabled topology accepted") } catch is ConfigError {}
        profileConfig.monitorProfiles.removeLast()
        profileConfig.monitorProfiles[0].layoutName = "Missing layout"
        do { try profileConfig.validate(); fatalError("Missing profile layout accepted") } catch is ConfigError {}
        let decoded = try Configuration.decode(starter.encoded())
        precondition(decoded == starter, "Shortcut configuration must round-trip")
        let example = try Configuration.decode(Data(contentsOf: URL(fileURLWithPath: "examples/config.json")))
        precondition(example.shortcuts == starter.shortcuts, "Example must match the shipped shortcut preset")
        let hyper: Set<String> = ["ctrl", "alt", "cmd", "shift"]
        let base: Set<String> = ["ctrl", "alt", "cmd"]
        for direction in WindowDirection.allCases {
            precondition(starter.shortcuts.contains {
                $0.key == direction.rawValue && Set($0.modifiers) == hyper && $0.action == .swapWindow
            })
            precondition(starter.shortcuts.contains {
                $0.key == direction.rawValue && Set($0.modifiers) == base && $0.action == .focusWindow
            })
        }
        precondition(starter.shortcuts.contains { $0.key == "return" && Set($0.modifiers) == hyper && $0.target == "@browser" })
        precondition(starter.shortcuts.contains { $0.key == "return" && Set($0.modifiers) == base && $0.target == "@terminal" })
        var invalid = starter
        invalid.shortcuts.append(Shortcut(key: "left", modifiers: Array(base.reversed()), action: .focusWindow, target: "left"))
        do { try invalid.validate(); fatalError("Duplicate modifiers in a different order must be rejected") }
        catch is ConfigError {}
        for action in [Action.focusWindow, .swapWindow, .resizeWindow] {
            invalid = starter
            invalid.shortcuts = [Shortcut(key: "a", action: action, target: "invalid")]
            do { try invalid.validate(); fatalError("Invalid window target must be rejected") }
            catch is ConfigError {}
        }
        var legacy = starter
        legacy.shortcuts = Configuration.legacyShortcuts
        let decodedLegacy = try Configuration.decode(legacy.encoded())
        precondition(decodedLegacy.shortcuts == Configuration.legacyShortcuts)
        var customized = legacy
        customized.shortcuts[0].modifiers.append("shift")
        let preserved = customized.shortcuts
        let added = customized.addMissingOmarchyShortcuts()
        precondition(added > 0 && Array(customized.shortcuts.prefix(preserved.count)) == preserved)
        precondition(customized.addMissingOmarchyShortcuts() == 0, "Adding missing shortcuts must be idempotent")
        try customized.validate()

        func window(_ id: Int, _ x: Double, _ y: Double) -> WindowDescriptor {
            WindowDescriptor(id: id, bundleID: "test", title: "", frame: Rect(x: x, y: y, width: 200, height: 200))
        }
        let source = window(1, -1000, -500)
        let left = window(2, -1300, -500), right = window(3, -700, -500)
        let up = window(4, -1000, -800), down = window(5, -1000, -200)
        let windows = [source, left, right, up, down]
        for (direction, expected) in [(WindowDirection.left, 2), (.right, 3), (.up, 4), (.down, 5)] {
            precondition(WindowNavigation.neighbor(of: source, among: windows, direction: direction)?.id == expected)
        }
        precondition(WindowNavigation.neighbor(of: source, among: [source], direction: .left) == nil)
        let aligned = window(6, 0, -500), diagonal = window(7, -700, -200)
        precondition(WindowNavigation.neighbor(of: source, among: [diagonal, aligned], direction: .right)?.id == 6)
        let tie = window(8, -700, -500)
        precondition(WindowNavigation.neighbor(of: source, among: [tie, right], direction: .right)?.id == 3)

        let bounds = Rect(x: -1600, y: -900, width: 1600, height: 900)
        let frame = Rect(x: -300, y: -250, width: 300, height: 250)
        precondition(WindowNavigation.resized(frame, in: bounds, target: "wider") == Rect(x: -400, y: -250, width: 400, height: 250))
        precondition(WindowNavigation.resized(frame, in: bounds, target: "shorter").height == 150)
        precondition(WindowNavigation.clamped(frame, in: bounds) == frame)
        let oversized = Rect(x: 500, y: 500, width: 3000, height: 2000)
        precondition(WindowNavigation.clamped(oversized, in: bounds) == bounds)
        for (width, height) in [(1512.0, 945.0), (3440.0, 1440.0), (5120.0, 1440.0), (1440.0, 2560.0)] {
            let screen = Rect(x: -width, y: -100, width: width, height: height)
            for algorithm in TileAlgorithm.allCases {
                for count in 1...20 {
                    let frames = Tiler.frames(count: count, screen: screen, algorithm: algorithm, gap: 12)
                    precondition(frames.count == count)
                    for (index, frame) in frames.enumerated() {
                        precondition(frame.width > 0 && frame.height > 0)
                        precondition(frame.x >= screen.x && frame.y >= screen.y)
                        precondition(frame.x + frame.width <= screen.x + screen.width + 1)
                        precondition(frame.y + frame.height <= screen.y + screen.height + 1)
                        for other in frames.dropFirst(index + 1) { precondition(frame.intersectionArea(other) == 0) }
                    }
                }
            }
        }
        // Reflow on open/close with apps that refuse half-height tiles.
        let desktop = Rect(x: -1800, y: 40, width: 1800, height: 1130)
        let requirements = [
            Rect(x: 0, y: 0, width: 500, height: 600),
            Rect(x: 0, y: 0, width: 400, height: 300),
            Rect(x: 0, y: 0, width: 540, height: 600),
            Rect(x: 0, y: 0, width: 400, height: 300)
        ]
        for count in [1, 2, 3, 4, 3, 2, 1] {
            let minima = Array(requirements.prefix(count))
            for algorithm in TileAlgorithm.allCases {
                guard let frames = Tiler.fittingFrames(minimumSizes: minima, screen: desktop, algorithm: algorithm, gap: 12) else {
                    fatalError("Feasible constrained layout rejected")
                }
                precondition(frames.count == count)
                for (index, frame) in frames.enumerated() {
                    precondition(frame.width >= minima[index].width && frame.height >= minima[index].height)
                    precondition(frame.x >= desktop.x && frame.y >= desktop.y)
                    precondition(frame.x + frame.width <= desktop.x + desktop.width + 0.01)
                    precondition(frame.y + frame.height <= desktop.y + desktop.height + 0.01)
                    for other in frames.dropFirst(index + 1) { precondition(frame.intersectionArea(other) < 0.01) }
                }
            }
        }
        precondition(Tiler.fittingFrames(minimumSizes: [Rect(x: 0, y: 0, width: 2000, height: 1200)],
            screen: desktop, algorithm: .adaptive, gap: 12) == nil)
        var tree = BSPTree()
        tree.reconcile(windowIDs: [10, 20], screen: desktop)
        let pair = tree.frames(screen: desktop, gap: 12)!
        tree.reconcile(windowIDs: [10, 20, 30], screen: desktop)
        let triple = tree.frames(screen: desktop, gap: 12)!
        precondition(triple.count == 3)
        precondition([10, 20].contains { triple[$0] == pair[$0] })
        tree.reconcile(windowIDs: [10, 20], screen: desktop)
        precondition(tree.frames(screen: desktop, gap: 12)! == pair)
        precondition(tree.swap(10, 20))
        precondition(tree.frames(screen: desktop, gap: 12)![10] == pair[20])
        precondition(tree.resize(10, target: "wider"))
        precondition(tree.frames(screen: desktop, gap: 12)![10]!.width > pair[20]!.width)
        let resized = tree.frames(screen: desktop, gap: 12)!
        tree.reconcile(windowIDs: [20, 10], screen: desktop)
        precondition(tree.frames(screen: desktop, gap: 12)! == resized)
        precondition(!tree.swap(10, 999))
        for count in Array(1...20) + Array((1...19).reversed()) {
            tree.reconcile(windowIDs: Array(1...count), screen: desktop)
            let frames = Array(tree.frames(screen: desktop, gap: 12)!.values)
            precondition(frames.count == count)
            for (i, frame) in frames.enumerated() {
                precondition(frame.x >= desktop.x && frame.y >= desktop.y)
                precondition(frame.x + frame.width <= desktop.x + desktop.width + 1)
                precondition(frame.y + frame.height <= desktop.y + desktop.height + 1)
                for other in frames.dropFirst(i + 1) { precondition(frame.intersectionArea(other) == 0) }
            }
        }
        tree.reconcile(windowIDs: [], screen: desktop)
        precondition(tree.windowIDs.isEmpty)
        var persisted = Configuration.starter
        persisted.algorithm = .bsp
        let decodedBSP = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(persisted))
        precondition(decodedBSP == persisted)
        print("Passed: persistent BSP insertion/removal, sibling expansion, swaps, split resizing, stable ordering and 39 window transitions.")
        for width in [1.0, 3.0, 6.0, 12.0] {
            for window in [Rect(x: 0, y: 39, width: 888, height: 553),
                           Rect(x: -1500, y: -600, width: 700, height: 1000)] {
                let border = BorderGeometry.outside(window: window, width: width)
                let stroke = border.stroke
                precondition(stroke.x - width / 2 >= 1)
                precondition(stroke.y - width / 2 >= 1)
                precondition(stroke.x + stroke.width + width / 2 <= border.panel.width - 1)
                precondition(stroke.y + stroke.height + width / 2 <= border.panel.height - 1)
                precondition(border.panel.x + stroke.x + width / 2 == window.x)
                precondition(border.panel.y + stroke.y + width / 2 == window.y)
                precondition(border.panel.x + stroke.x + stroke.width - width / 2 == window.x + window.width)
                precondition(border.panel.y + stroke.y + stroke.height - width / 2 == window.y + window.height)
            }
        }
        print("Passed: all four border edges outside owner bounds, unclipped canvas, widths 1–12 and negative display origins.")
        print("Passed: constrained layouts through 1→4→1 window transitions, all algorithms, and impossible-size detection.")
        print("Passed: 320 tiling scenarios across all algorithms, 1–20 windows, ultrawide/portrait displays and negative origins.")
        print("Passed: preset validation, Hyper/base bindings, round-trip, legacy compatibility, invalid targets, directional selection, resize and restore bounds.")
    }
}
