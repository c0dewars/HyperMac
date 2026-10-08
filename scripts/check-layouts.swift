import Foundation

@main enum LayoutChecks {
    static func screen(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, builtIn: Bool = false, primary: Bool = false) -> Display {
        Display(id: id, name: id, builtIn: builtIn, primary: primary,
                frame: Rect(x: x, y: y, width: w, height: h), usable: Rect(x: x, y: y + 30, width: w, height: h - 60))
    }
    static func window(_ id: Int, _ app: String, on screen: Display, title: String = "") -> WindowDescriptor {
        WindowDescriptor(id: id, bundleID: app, title: title, frame: screen.usable)
    }
    static func rule(_ app: String, _ display: String, index: Int = 0) -> Placement {
        var p = Placement(bundleID: app, display: display, frame: Rect(x: 0, y: 0, width: 0.5, height: 1))
        p.windowIndex = index; return p
    }
    static func destination(_ id: Int, _ plan: LayoutPlan, _ displays: [Display]) -> String? {
        plan.moves.first { $0.windowID == id }.flatMap { Displays.containing($0.frame, in: displays)?.id }
    }
    static func checkBounds(_ plan: LayoutPlan, _ screens: [Display], overlap: Bool = false) {
        precondition(Set(plan.moves.map(\.windowID)).count == plan.moves.count, "Window moved twice")
        for (i, move) in plan.moves.enumerated() {
            guard let s = Displays.containing(move.frame, in: screens) else { fatalError("No screen") }
            let f = move.frame
            precondition(f.width > 0 && f.height > 0 && f.x >= s.usable.x - 1 && f.y >= s.usable.y - 1)
            precondition(f.x + f.width <= s.usable.x + s.usable.width + 1 && f.y + f.height <= s.usable.y + s.usable.height + 1)
            if !overlap { for other in plan.moves.dropFirst(i + 1) { precondition(f.intersectionArea(other.frame) <= 1, "Overlapping tiles") } }
        }
    }
    static func main() throws {
        setbuf(stdout, nil)
        let laptop = screen("laptop", 0, 0, 1800, 1200, builtIn: true, primary: true)
        let wide = screen("wide", -5120, -350, 5120, 1440)
        let portrait = screen("portrait", 1800, -100, 1080, 1920)
        let upper = screen("upper", 0, -2400, 3840, 2160)
        let far = screen("far", 2880, 50, 2560, 1440)
        let screens = [laptop, wide, portrait, upper, far]
        precondition(Displays.resolve("external-4", in: screens, fallback: false)?.id == "far")
        for key in ["external-0", "external--1", "external-01", "all", "none", "uuid:"] { precondition(!Displays.validSelector(key)) }
        for key in ["built-in", "primary", "external-12", "uuid:future"] { precondition(Displays.validSelector(key)) }

        var sameApp = Layout(name: "Same app on two screens", placements: [rule("browser", "uuid:wide"), rule("browser", "built-in")])
        sameApp.adaptive = true
        let pair = [window(1, "browser", on: laptop), window(2, "browser", on: wide)]
        for windows in [pair, pair.reversed().map { $0 }] {
            let plan = LayoutPlanner.plan(sameApp, windows: windows, displays: screens, gap: 12)
            precondition(destination(1, plan, screens) == "laptop" && destination(2, plan, screens) == "wide")
            checkBounds(plan, screens)
        }
        let transfer = Layout(name: "Move to saved monitor", placements: [rule("browser", "uuid:wide")])
        precondition(destination(1, LayoutPlanner.plan(transfer, windows: [pair[0]], displays: screens, gap: 12), screens) == "wide")
        var disconnected = transfer
        let absent = LayoutPlanner.plan(disconnected, windows: [pair[0]], displays: [laptop], gap: 12)
        precondition(absent.moves.isEmpty && !absent.messages.isEmpty && !absent.missingWindows)
        disconnected.fallbackToPrimary = true
        precondition(destination(1, LayoutPlanner.plan(disconnected, windows: [pair[0]], displays: [laptop], gap: 12), [laptop]) == "laptop")
        print("Passed: physical monitor identity, arbitrary external roles, same-app local priority, explicit transfers and disconnected-display policy.")

        var mixed = Layout(name: "Mixed", placements: [rule("editor", "uuid:portrait"), rule("browser", "uuid:wide")])
        mixed.displayModes = ["uuid:laptop": .normal, "uuid:wide": .adaptive, "uuid:portrait": .fixed, "uuid:upper": .floating]
        let mixedWindows = [window(1, "terminal", on: laptop), window(2, "browser", on: laptop), window(3, "editor", on: portrait), window(4, "untouched", on: upper)]
        let mixedPlan = LayoutPlanner.plan(mixed, windows: mixedWindows, displays: screens, gap: 12)
        precondition(mixedPlan.moves.count == 3 && destination(2, mixedPlan, screens) == "wide")
        precondition(mixedPlan.moves.first { $0.windowID == 1 }!.frame.width == laptop.usable.width - 12)
        checkBounds(mixedPlan, screens)
        mixed.displayExcludedBundleIDs["uuid:laptop"] = ["terminal"]
        precondition(LayoutPlanner.plan(mixed, windows: mixedWindows, displays: screens, gap: 12).moves.count == 2)
        mixed.excludedBundleIDs = ["browser"]
        precondition(LayoutPlanner.plan(mixed, windows: mixedWindows, displays: screens, gap: 12).moves.count == 1)
        var precedence = mixed
        precedence.displayModes["primary"] = .fixed
        precondition(LayoutScreens.mode(on: laptop, layout: precedence, displays: screens) == .normal)
        precondition(LayoutScreens.mode(on: far, layout: mixed, displays: screens) == .floating)
        mixed.defaultScreenMode = .normal
        precondition(LayoutScreens.mode(on: far, layout: mixed, displays: screens) == .normal)
        print("Passed: mixed modes, no cross-screen duplicates, per-display exclusions, physical identity precedence and future-screen defaults.")

        var automatic = Layout(name: "All", placements: []); automatic.defaultScreenMode = .normal
        var cases = 0
        for monitors in [[laptop], [wide, laptop], [portrait, laptop, upper], screens] {
            for algorithm in TileAlgorithm.allCases {
                for count in Array(0...14) + Array((0...13).reversed()) {
                    let windows = monitors.enumerated().flatMap { offset, monitor in
                        (0..<count).map { window(offset * 100 + $0, "app\($0)", on: monitor) }
                    }
                    let p = LayoutPlanner.plan(automatic, windows: windows, displays: monitors, gap: 12, algorithm: algorithm)
                    precondition(p.moves.count == windows.count)
                    checkBounds(p, monitors)
                    for w in windows { precondition(destination(w.id, p, monitors) == Displays.containing(w.frame, in: monitors)?.id) }
                    cases += 1
                }
            }
        }
        let impossible = LayoutPlanner.plan(automatic, windows: [pair[0]], displays: [laptop], gap: 12,
            minimumSizes: [1: Rect(x: 0, y: 0, width: 4000, height: 800)])
        precondition(impossible.moves.isEmpty && !impossible.messages.isEmpty)
        let rotated = screen("laptop", -1200, -1800, 1200, 1800, builtIn: true, primary: true)
        let resized = LayoutPlanner.plan(sameApp, windows: [pair[0]], displays: [rotated], gap: 12)
        checkBounds(resized, [rotated])
        print("Passed: \(cases) lifecycle/topology/algorithm scenarios, up to 70 windows across five displays; rotation, negative origins and impossible-fit handling.")

        var legacy = try JSONSerialization.jsonObject(with: Configuration.starter.encoded()) as! [String: Any]
        let rules: [[String: Any]] = [["bundleID": "browser", "display": "uuid:wide", "titleContains": "work", "windowIndex": 1,
            "scrollColumn": 4, "frame": ["x": 0, "y": 0, "width": 0.75, "height": 1]]]
        legacy["layouts"] = [["name": "My old workspace", "placements": rules,
            "scrolling": ["display": "uuid:wide", "allWindows": false, "tileOtherDisplays": false,
                          "displayModes": ["uuid:wide": "horizontal", "built-in": "normal", "uuid:future": "fixed"],
                          "excludedBundleIDs": ["ignore"], "displayExcludedBundleIDs": ["uuid:wide": ["float"]]]]]
        legacy["shortcuts"] = [["key": "h", "modifiers": ["cmd", "ctrl"], "action": "focusWindow", "target": "left"],
                               ["key": "j", "modifiers": ["cmd", "ctrl"], "action": "groupNext", "target": ""]]
        let migrated = try Configuration.decode(JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.layouts.count == 1 && migrated.layouts[0].name == "My old workspace")
        precondition(migrated.layouts[0].placements[0].titleContains == "work" && migrated.layouts[0].placements[0].windowIndex == 1)
        precondition(migrated.layouts[0].displayModes["uuid:wide"] == .adaptive)
        precondition(migrated.layouts[0].displayModes["uuid:future"] == .fixed)
        precondition(migrated.shortcuts.count == 1 && migrated.shortcuts[0].target == "left")
        precondition(LayoutScreens.exclusions(on: wide, layout: migrated.layouts[0], displays: screens) == Set(["ignore", "float"]))
        let data = try migrated.encoded()
        let text = String(decoding: data, as: UTF8.self)
        precondition(!text.contains("scrolling") && !text.contains("scrollColumn") && !text.contains("groupNext"))
        let roundTrip = try Configuration.decode(data)
        precondition(roundTrip == migrated)
        var draft = Configuration.starter
        draft.layouts.append(LayoutScreens.emptyLayout(name: "Empty draft"))
        try draft.validate()
        if CommandLine.arguments.contains("--write-example") {
            try Configuration.starter.encoded().write(to: URL(fileURLWithPath: "examples/config.json"))
        }
        if let configPath = CommandLine.arguments.dropFirst().first, configPath != "--write-example" {
            let config = try Configuration.decode(Data(contentsOf: URL(fileURLWithPath: configPath)))
            let userRoundTrip = try Configuration.decode(config.encoded())
            precondition(userRoundTrip == config)
            print("Passed: existing user configuration migrates and round-trips (\(config.layouts.count) layouts, \(config.shortcuts.count) shortcuts).")
        }
        print("Passed: lossless app-rule/name migration, obsolete-action removal, normal-only encoding and empty draft autosave.")
    }
}
