import Foundation

public enum LayoutScreenMode: String, Codable, CaseIterable, Sendable {
    case normal, adaptive, fixed, floating
    public var title: String {
        switch self {
        case .normal: return "Tile all windows"
        case .adaptive: return "Tile selected apps"
        case .fixed: return "Custom positions"
        case .floating: return "Leave unchanged"
        }
    }
}

public enum LayoutScreens {
    private static func selectors(on screen: Display, displays: [Display]) -> [String] {
        ["uuid:" + screen.id, "built-in"] + (1...max(1, displays.count)).map { "external-\($0)" } + ["primary"]
    }

    public static func mode(on screen: Display, layout: Layout, displays: [Display]) -> LayoutScreenMode {
        for key in selectors(on: screen, displays: displays) where Displays.resolve(key, in: displays, fallback: false)?.id == screen.id {
            if let value = layout.displayModes[key] { return value }
        }
        // A disconnected physical display is never silently redirected here.
        let hasApps = layout.placements.contains {
            Displays.resolve($0.display, in: displays, fallback: layout.fallbackToPrimary)?.id == screen.id
        }
        return hasApps ? (layout.adaptive ? .adaptive : .fixed) : layout.defaultScreenMode
    }

    public static func exclusions(on screen: Display, layout: Layout, displays: [Display]) -> Set<String> {
        var result = Set(layout.excludedBundleIDs)
        for key in selectors(on: screen, displays: displays) where Displays.resolve(key, in: displays, fallback: false)?.id == screen.id {
            result.formUnion(layout.displayExcludedBundleIDs[key] ?? [])
        }
        return result
    }

    public static func setMode(_ mode: LayoutScreenMode, on screen: Display, layout: inout Layout, displays: [Display]) {
        layout.displayModes["uuid:" + screen.id] = mode
    }

    public static func emptyLayout(name: String) -> Layout { Layout(name: name, placements: []) }
}
