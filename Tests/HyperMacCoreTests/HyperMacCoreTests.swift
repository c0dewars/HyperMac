import XCTest
@testable import HyperMacCore

final class HyperMacCoreTests: XCTestCase {
    func testChangingActionPreservesAnExplicitDirection() {
        for direction in WindowDirection.allCases {
            var shortcut = Shortcut(key: "k", action: .focusWindow, target: direction.rawValue)
            shortcut.selectAction(.swapWindow)
            XCTAssertEqual(shortcut.target, direction.rawValue)
            shortcut.selectAction(.swapWindow)
            XCTAssertEqual(shortcut.target, direction.rawValue)
        }
    }

    func testNewDirectionalActionUsesArrowAndKeepsResizeTargets() {
        for direction in WindowDirection.allCases {
            var shortcut = Shortcut(key: direction.rawValue, action: .launch, target: "com.apple.finder")
            shortcut.selectAction(.swapWindow)
            XCTAssertEqual(shortcut.target, direction.rawValue)
        }
        var resize = Shortcut(key: "equal", action: .resizeWindow, target: "narrower")
        resize.selectAction(.resizeWindow)
        XCTAssertEqual(resize.target, "narrower")
        resize.selectAction(.focusWindow)
        XCTAssertEqual(resize.target, "left")
    }

    func testReplacingAndRemovingShortcutRowsPreservesPresetTargets() throws {
        var config = Configuration.starter
        config.shortcuts = Configuration.omarchyShortcuts
        let launcher = try XCTUnwrap(config.shortcuts.firstIndex { $0.action == .launch })
        config.shortcuts.remove(at: launcher)
        let loaded = try Configuration.decode(config.encoded())
        XCTAssertEqual(loaded.shortcuts, config.shortcuts)
        for shortcut in loaded.shortcuts where shortcut.action == .focusWindow || shortcut.action == .swapWindow {
            let expectedDirection = ["h": "left", "l": "right"][shortcut.key] ?? shortcut.key
            XCTAssertEqual(shortcut.target, expectedDirection)
        }
        XCTAssertEqual(loaded.shortcuts.first { $0.key == "h" && $0.action == .focusWindow }?.target, "left")
        XCTAssertEqual(loaded.shortcuts.first { $0.key == "l" && $0.action == .focusWindow }?.target, "right")
    }
    func testVisibleWindowMatchingAllowsSmallDecorationDifferences() {
        let ax = Rect(x: -1000, y: 30, width: 1000, height: 800)
        let decorated = Rect(x: -1000, y: 22, width: 1000, height: 808)
        XCTAssertTrue(WindowGeometry.sameVisibleWindow(ax, decorated))
        XCTAssertFalse(WindowGeometry.sameVisibleWindow(ax, Rect(x: 0, y: 30, width: 1000, height: 800)))
        XCTAssertFalse(WindowGeometry.sameVisibleWindow(ax, Rect(x: -1000, y: 30, width: 300, height: 200)))
    }
    func testLegacyConfigurationLoadsWithBorderDefaults() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Configuration.starter.encoded()) as? [String: Any])
        json.removeValue(forKey: "appColors"); json.removeValue(forKey: "borderEnabled"); json.removeValue(forKey: "borderWidth")
        json.removeValue(forKey: "borderColor")
        let legacy = try Configuration.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.borderEnabled)
        XCTAssertEqual(legacy.borderWidth, 3)
        XCTAssertEqual(legacy.borderColor, "#A6F3C2")
        XCTAssertEqual(legacy.layouts, Configuration.starter.layouts)
    }

    func testColorRoundTripAndValidation() throws {
        var config = Configuration.starter
        config.appColors["com.apple.Safari"] = "#AABBCC"
        XCTAssertEqual(try Configuration.decode(config.encoded()).colorHex(for: "com.apple.Safari"), "#AABBCC")
        config.appColors["bad"] = "#GGGGGG"
        XCTAssertThrowsError(try config.validate())
        config.appColors.removeValue(forKey: "bad"); config.borderWidth = .infinity
        XCTAssertThrowsError(try config.validate())
    }

    func testDraggedRectangleIsClampedAndSnappedOnNegativeDisplay() {
        let screen = display("external", x: -2000, y: -1000, w: 2000, h: 1000)
        let dragged = Rect(x: -2100, y: -970, width: 970, height: 1020)
        let placement = CanvasGeometry.placement(dragged, on: screen, snap: true)
        XCTAssertEqual(placement, Rect(x: 0, y: 0, width: 0.5, height: 1))
        let collapsed = CanvasGeometry.placement(Rect(x: 500, y: 500, width: -1, height: -1), on: screen, snap: false)
        XCTAssertEqual(collapsed.width, 0.05)
        XCTAssertEqual(collapsed.x, 0.95)
    }

    func testCanvasDragSelectsDestinationMonitor() {
        let screens = [display("laptop", builtIn: true), display("external", x: -1720)]
        XCTAssertEqual(CanvasGeometry.target(for: Rect(x: -1200, y: 10, width: 600, height: 500), displays: screens)?.id, "external")
    }
    private func display(_ id: String, x: Double = 0, y: Double = 0, w: Double = 1720,
                         h: Double = 720, builtIn: Bool = false, primary: Bool = false) -> Display {
        let frame = Rect(x: x, y: y, width: w, height: h)
        return Display(id: id, name: id, builtIn: builtIn, primary: primary, frame: frame, usable: frame)
    }

    func testStarterConfigRoundTrip() throws {
        let original = Configuration.starter
        XCTAssertEqual(try Configuration.decode(original.encoded()), original)
    }

    func testDuplicateShortcutsAreRejectedIgnoringModifierOrderAndCase() {
        var config = Configuration.starter
        config.shortcuts = [Shortcut(key: "t", modifiers: ["cmd", "ctrl"], action: .retile),
                            Shortcut(key: "T", modifiers: ["ctrl", "cmd"], action: .retile)]
        XCTAssertThrowsError(try config.validate())
    }

    func testInvalidBoundsAndMissingLayoutAreRejected() {
        var config = Configuration.starter
        config.layouts[0].placements[0].frame.width = 1.1
        XCTAssertThrowsError(try config.validate())
        config = .starter
        config.shortcuts = [Shortcut(key: "1", action: .layout, target: "No such layout")]
        XCTAssertThrowsError(try config.validate())
    }

    func testExternalRolesUsePhysicalOrderAndStableIDsIgnoreOrder() {
        let screens = [display("laptop", builtIn: true, primary: true),
                       display("right", x: 1720), display("left", x: -1720)]
        XCTAssertEqual(Displays.resolve("external-1", in: screens, fallback: false)?.id, "left")
        XCTAssertEqual(Displays.resolve("external-2", in: screens, fallback: false)?.id, "right")
        XCTAssertEqual(Displays.resolve("uuid:right", in: Array(screens.reversed()), fallback: false)?.id, "right")
    }

    func testMissingMonitorSkipsUnlessFallbackIsExplicit() {
        let screens = [display("laptop", builtIn: true, primary: true)]
        XCTAssertNil(Displays.resolve("external-1", in: screens, fallback: false))
        XCTAssertEqual(Displays.resolve("external-1", in: screens, fallback: true)?.id, "laptop")
    }

    func testProportionsSupportNegativeOriginsAndRetinaLogicalSizes() {
        let screen = Rect(x: -1720, y: -700, width: 1720, height: 700)
        let half = Rect(x: 0.5, y: 0, width: 0.5, height: 1)
        let result = half.resolved(in: screen, gap: 0)
        XCTAssertEqual(result, Rect(x: -860, y: -700, width: 860, height: 700))
        XCTAssertEqual(result.normalized(in: screen), half)
    }

    func testAlgorithmsNeverOverlapOrLeaveDisplayBounds() {
        for size in [(1512.0, 945.0), (3440, 1440), (5120, 1440), (1440, 2560)] {
            let screen = Rect(x: -size.0, y: -100, width: size.0, height: size.1)
            for algorithm in TileAlgorithm.allCases {
                for count in 1...20 {
                    let frames = Tiler.frames(count: count, screen: screen, algorithm: algorithm, gap: 12)
                    XCTAssertEqual(frames.count, count)
                    for (index, frame) in frames.enumerated() {
                        XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
                        XCTAssertGreaterThanOrEqual(frame.x, screen.x)
                        XCTAssertGreaterThanOrEqual(frame.y, screen.y)
                        XCTAssertLessThanOrEqual(frame.x + frame.width, screen.x + screen.width + 1)
                        XCTAssertLessThanOrEqual(frame.y + frame.height, screen.y + screen.height + 1)
                        for other in frames.dropFirst(index + 1) { XCTAssertEqual(frame.intersectionArea(other), 0) }
                    }
                }
            }
        }
    }

    func testPlannerDoesNotMoveSameWindowTwice() {
        let placement = Placement(bundleID: "app", display: "primary", frame: Rect(x: 0, y: 0, width: 1, height: 1))
        let layout = Layout(name: "Duplicate", placements: [placement, placement])
        let windows = [WindowDescriptor(id: 7, bundleID: "app", title: "Project", frame: placement.frame)]
        let plan = LayoutPlanner.plan(layout, windows: windows, displays: [display("main", primary: true)], gap: 0)
        XCTAssertEqual(plan.moves.count, 1)
        XCTAssertTrue(plan.messages.contains { $0.contains("Duplicate window rule") })
    }

    func testPlannerMatchesTitleAndIndexWithoutNeedingMissingDisplayWindow() {
        var placement = Placement(bundleID: "editor", display: "primary", frame: Rect(x: 0, y: 0, width: 1, height: 1))
        placement.titleContains = "project"; placement.windowIndex = 1
        let windows = ["Unrelated", "Project A", "Project B"].enumerated().map {
            WindowDescriptor(id: $0.offset, bundleID: "editor", title: $0.element, frame: placement.frame)
        }
        var layout = Layout(name: "Work", placements: [placement])
        var plan = LayoutPlanner.plan(layout, windows: windows, displays: [display("main", primary: true)], gap: 0)
        XCTAssertEqual(plan.moves.first?.windowID, 2)
        layout.placements[0].display = "external-2"
        plan = LayoutPlanner.plan(layout, windows: [], displays: [display("main", primary: true)], gap: 0)
        XCTAssertFalse(plan.missingWindows)
        XCTAssertTrue(plan.moves.isEmpty)
    }

    func testCapturedLayoutDoesNotApplyGapTwice() {
        let frame = Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        var layout = Layout(name: "Captured", placements: [Placement(bundleID: "app", display: "primary", frame: frame)])
        layout.applyGap = false
        let plan = LayoutPlanner.plan(layout, windows: [WindowDescriptor(id: 1, bundleID: "app", title: "", frame: frame)],
                                      displays: [display("main", w: 1000, h: 1000, primary: true)], gap: 40)
        XCTAssertEqual(plan.moves.first?.frame, Rect(x: 100, y: 100, width: 800, height: 800))
    }
}
