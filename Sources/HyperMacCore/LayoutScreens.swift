import Foundation

/// One mode per screen. Legacy layouts keep their behavior until a mode is edited.
public enum LayoutScreenMode: String, CaseIterable, Sendable {
    case horizontal, normal, adaptive, fixed, floating

    public var title: String {
        switch self {
        case .horizontal: return "Horizontal scroll"
        case .normal: return "Automatic tiles"
        case .adaptive: return "Tile saved apps"
        case .fixed: return "Custom positions"
        case .floating: return "Leave unchanged"
        }
    }
}

public enum LayoutScreens {
    public static func mode(on screen: Display, layout: Layout, displays: [Display]) -> LayoutScreenMode {
        guard let options = layout.scrolling else {
            let hasApps = layout.placements.contains {
                Displays.resolve($0.display, in: displays, fallback: layout.fallbackToPrimary)?.id == screen.id
            }
            return hasApps ? (layout.adaptive ? .adaptive : .fixed) : .floating
        }
        // A physical screen choice wins over a portable role.
        for key in ["uuid:" + screen.id, "built-in", "external-1", "external-2", "primary"] {
            if Displays.resolve(key, in: displays, fallback: false)?.id == screen.id,
               let value = options.displayModes[key], let mode = LayoutScreenMode(rawValue: value) { return mode }
        }
        let selected = options.display == "all" || (options.display != "none" &&
            Displays.resolve(options.display, in: displays, fallback: layout.fallbackToPrimary)?.id == screen.id)
        return selected ? .horizontal : options.tileOtherDisplays ? .normal : .floating
    }

    public static func setMode(_ mode: LayoutScreenMode, on screen: Display, layout: inout Layout, displays: [Display]) {
        if layout.scrolling == nil {
            let previous = layout
            var options = ScrollingOptions()
            options.display = "none"
            options.allWindows = false
            options.tileOtherDisplays = false
            // Retain portable assignments, including disconnected screens.
            for placement in previous.placements {
                options.displayModes[placement.display] = previous.adaptive ? "adaptive" : "fixed"
            }
            for connected in displays {
                options.displayModes["uuid:" + connected.id] = self.mode(on: connected, layout: previous, displays: displays).rawValue
            }
            layout.scrolling = options
            layout.adaptive = false
        }
        layout.scrolling?.displayModes["uuid:" + screen.id] = mode.rawValue
    }

    public static func emptyLayout(name: String) -> Layout {
        var layout = Layout(name: name, placements: [])
        var options = ScrollingOptions()
        options.display = "none"
        options.tileOtherDisplays = false
        layout.scrolling = options
        return layout
    }

    /// Saved-app modes in mixed layouts operate on the selected screen's windows.
    public static func templatePlan(on screen: Display, layout: Layout, windows: [WindowDescriptor],
                                    displays: [Display], gap: Double, minimumSizes: [Int: Rect] = [:]) -> LayoutPlan {
        let mode = mode(on: screen, layout: layout, displays: displays)
        guard mode == .fixed || mode == .adaptive else { return LayoutPlan() }
        var local = ScrollingSession.layout(layout, on: screen, displays: displays)
        local.scrolling = nil
        local.adaptive = mode == .adaptive
        return LayoutPlanner.plan(local, windows: windows.filter { Displays.containing($0.frame, in: displays)?.id == screen.id },
                                  displays: displays, gap: gap, minimumSizes: minimumSizes)
    }
}
