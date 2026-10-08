import Foundation

public struct Configuration: Codable, Equatable, Sendable {
    public var version = 1
    public var automaticTiling = true
    public var algorithm: TileAlgorithm = .bsp
    public var gap: Double = 12
    public var monitorProfiles: [MonitorProfile] = []
    public var mouseResize = true
    public var animationDuration: Double = 0.18
    public var excludedBundleIDs: [String] = ["local.hypermac.app", "com.apple.systempreferences"]
    public var shortcuts: [Shortcut] = []
    public var layouts: [Layout] = []
    public var borderEnabled = true
    public var borderWidth: Double = 3
    public var borderColor = "#A6F3C2"
    public var appColors: [String: String] = [:]
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, automaticTiling, algorithm, gap, excludedBundleIDs, shortcuts, layouts
        case monitorProfiles, mouseResize
        case animationDuration
        case borderEnabled, borderWidth, borderColor, appColors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        automaticTiling = try c.decode(Bool.self, forKey: .automaticTiling)
        algorithm = try c.decode(TileAlgorithm.self, forKey: .algorithm)
        gap = try c.decode(Double.self, forKey: .gap)
        monitorProfiles = try c.decodeIfPresent([MonitorProfile].self, forKey: .monitorProfiles) ?? []
        mouseResize = try c.decodeIfPresent(Bool.self, forKey: .mouseResize) ?? true
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.18
        excludedBundleIDs = try c.decode([String].self, forKey: .excludedBundleIDs)
        shortcuts = try c.decode([Shortcut].self, forKey: .shortcuts)
        layouts = try c.decode([Layout].self, forKey: .layouts)
        // Existing 0.1.0 configurations keep working without a manual migration.
        borderEnabled = try c.decodeIfPresent(Bool.self, forKey: .borderEnabled) ?? true
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 3
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor) ?? "#A6F3C2"
        appColors = try c.decodeIfPresent([String: String].self, forKey: .appColors) ?? [:]
    }

    public func colorHex(for bundleID: String) -> String {
        if let color = appColors[bundleID] { return color }
        let palette = ["#59A6FF", "#51CDA3", "#D995FA", "#FFB45C", "#F77F9F", "#66CFE3"]
        let hash = bundleID.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    public func validate() throws {
        guard version == 1 else { throw ConfigError("Unsupported configuration version \(version).") }
        guard animationDuration.isFinite, (0...0.5).contains(animationDuration) else { throw ConfigError("Animation duration must be 0–0.5 seconds.") }
        guard borderWidth.isFinite, (1...10).contains(borderWidth) else { throw ConfigError("Border width must be 1–10 points.") }
        for hex in Array(appColors.values) + [borderColor] {
            guard hex.count == 7, hex.first == "#", UInt32(hex.dropFirst(), radix: 16) != nil else {
                throw ConfigError("App colors must use #RRGGBB format.")
            }
        }
        guard gap.isFinite, (0...80).contains(gap) else { throw ConfigError("Gap must be between 0 and 80 points.") }
        guard Set(layouts.map(\.name)).count == layouts.count else { throw ConfigError("Layout names must be unique.") }
        var topologies = Set<String>()
        for profile in monitorProfiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !profile.displayIDs.isEmpty, layouts.contains(where: { $0.name == profile.layoutName }) else {
                throw ConfigError("Monitor profiles need a name, displays and an existing layout.")
            }
            if profile.enabled, !topologies.insert(profile.displayIDs.sorted().joined(separator: "|")).inserted {
                throw ConfigError("Only one enabled profile can match a monitor setup.")
            }
        }
        for layout in layouts {
            guard !layout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigError("A layout needs a name.")
            }
            guard !layout.placements.isEmpty else { throw ConfigError("Layout '\(layout.name)' has no windows.") }
            for placement in layout.placements {
                guard !placement.bundleID.isEmpty, placement.windowIndex >= 0 else {
                    throw ConfigError("Each placement needs an application bundle ID and a nonnegative window index.")
                }
                let r = placement.frame
                guard [r.x, r.y, r.width, r.height].allSatisfy(\.isFinite),
                      r.x >= 0, r.y >= 0, r.width > 0, r.height > 0,
                      r.x + r.width <= 1.000001, r.y + r.height <= 1.000001 else {
                    throw ConfigError("Layout '\(layout.name)' has a rectangle outside 0…1 screen proportions.")
                }
                guard ["built-in", "primary", "external-1", "external-2"].contains(placement.display)
                        || (placement.display.hasPrefix("uuid:") && placement.display.count > 5) else {
                    throw ConfigError("Unknown display selector: \(placement.display).")
                }
            }
        }
        var used = Set<String>()
        for shortcut in shortcuts {
            let key = shortcut.key.lowercased()
            guard KeyMap.codes[key] != nil else { throw ConfigError("Unknown shortcut key: \(shortcut.key).") }
            let modifiers = Set(shortcut.modifiers)
            guard modifiers.count == shortcut.modifiers.count,
                  modifiers.isSubset(of: ["cmd", "ctrl", "alt", "shift"]),
                  modifiers.contains("cmd") || modifiers.contains("ctrl") else {
                throw ConfigError("Shortcuts need cmd or ctrl; valid modifiers are cmd, ctrl, alt, shift.")
            }
            guard used.insert(modifiers.sorted().joined(separator: "+") + "+" + key).inserted else {
                throw ConfigError("Duplicate shortcut for \(key).")
            }
            switch shortcut.action {
            case .layout:
                guard layouts.contains(where: { $0.name == shortcut.target }) else {
                    throw ConfigError("Shortcut refers to missing layout '\(shortcut.target)'.")
                }
            case .launch:
                guard !shortcut.target.isEmpty else { throw ConfigError("Launch shortcuts need an app bundle ID.") }
            case .focusWindow, .swapWindow:
                guard WindowDirection(rawValue: shortcut.target) != nil else { throw ConfigError("Window direction must be left, right, up, or down.") }
            case .resizeWindow:
                guard ["wider", "narrower", "taller", "shorter"].contains(shortcut.target) else { throw ConfigError("Resize target must be wider, narrower, taller, or shorter.") }
            case .maximizeWindow: break
            case .toggleTiling, .retile: break
            }
        }
    }

    public static func decode(_ data: Data) throws -> Configuration {
        let value = try JSONDecoder().decode(Configuration.self, from: data)
        try value.validate()
        return value
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static var starter: Configuration {
        var config = Configuration()
        config.layouts = [
            Layout(name: "Office", placements: [
                Placement(bundleID: "com.apple.Safari", display: "external-1", frame: Rect(x: 0, y: 0, width: 0.65, height: 1)),
                Placement(bundleID: "com.apple.Terminal", display: "external-1", frame: Rect(x: 0.65, y: 0, width: 0.35, height: 1)),
                Placement(bundleID: "com.apple.TextEdit", display: "built-in", frame: Rect(x: 0, y: 0, width: 1, height: 1))
            ]),
            Layout(name: "Home", placements: [
                Placement(bundleID: "com.apple.Safari", display: "external-1", frame: Rect(x: 0, y: 0, width: 0.5, height: 1)),
                Placement(bundleID: "com.apple.Terminal", display: "external-1", frame: Rect(x: 0.5, y: 0, width: 0.25, height: 1)),
                Placement(bundleID: "com.apple.TextEdit", display: "external-1", frame: Rect(x: 0.75, y: 0, width: 0.25, height: 1))
            ]),
            Layout(name: "Two externals", placements: [
                Placement(bundleID: "com.apple.Safari", display: "external-1", frame: Rect(x: 0, y: 0, width: 1, height: 1)),
                Placement(bundleID: "com.apple.Terminal", display: "external-2", frame: Rect(x: 0, y: 0, width: 1, height: 1)),
                Placement(bundleID: "com.apple.TextEdit", display: "built-in", frame: Rect(x: 0, y: 0, width: 1, height: 1))
            ])
        ]
        config.shortcuts = omarchyShortcuts
        return config
    }

    /// Retained only to recognize an untouched pre-Hyper default configuration.
    public static var legacyShortcuts: [Shortcut] {
        [
            Shortcut(key: "1", action: .layout, target: "Office"),
            Shortcut(key: "2", action: .layout, target: "Home"),
            Shortcut(key: "3", action: .layout, target: "Two externals"),
            Shortcut(key: "return", action: .launch, target: "com.apple.Terminal"),
            Shortcut(key: "t", action: .toggleTiling),
            Shortcut(key: "r", action: .retile)
        ]
    }

    public static var omarchyShortcuts: [Shortcut] {
        let hyper = ["ctrl", "alt", "cmd", "shift"]
        var shortcuts = [
            Shortcut(key: "return", action: .launch, target: "@terminal"),
            Shortcut(key: "return", modifiers: hyper, action: .launch, target: "@browser"),
            Shortcut(key: "b", modifiers: hyper, action: .launch, target: "@browser"),
            Shortcut(key: "f", modifiers: hyper, action: .launch, target: "com.apple.finder"),
            Shortcut(key: "m", modifiers: hyper, action: .launch, target: "@music"),
            Shortcut(key: "n", modifiers: hyper, action: .launch, target: "@editor"),
            Shortcut(key: "c", modifiers: hyper, action: .launch, target: "com.apple.iCal"),
            Shortcut(key: "e", modifiers: hyper, action: .launch, target: "com.apple.mail"),
            Shortcut(key: "a", modifiers: hyper, action: .launch, target: "@ai"),
            Shortcut(key: "g", modifiers: hyper, action: .launch, target: "@messenger"),
            Shortcut(key: "p", modifiers: hyper, action: .launch, target: "com.apple.Photos"),
            Shortcut(key: "s", modifiers: hyper, action: .launch, target: "com.apple.Maps"),
            Shortcut(key: "d", modifiers: hyper, action: .launch, target: "com.docker.docker"),
            Shortcut(key: "o", modifiers: hyper, action: .launch, target: "@notes"),
            Shortcut(key: "slash", modifiers: hyper, action: .launch, target: "@passwords"),
            Shortcut(key: "f", action: .maximizeWindow),
            Shortcut(key: "minus", action: .resizeWindow, target: "wider"),
            Shortcut(key: "equal", action: .resizeWindow, target: "narrower"),
            Shortcut(key: "minus", modifiers: hyper, action: .resizeWindow, target: "shorter"),
            Shortcut(key: "equal", modifiers: hyper, action: .resizeWindow, target: "taller"),
            Shortcut(key: "t", action: .toggleTiling),
            Shortcut(key: "r", action: .retile)
        ]
        for direction in WindowDirection.allCases {
            shortcuts.append(Shortcut(key: direction.rawValue, action: .focusWindow, target: direction.rawValue))
            shortcuts.append(Shortcut(key: direction.rawValue, modifiers: hyper, action: .swapWindow, target: direction.rawValue))
        }
        return shortcuts
    }

    /// Preserve customized keys/actions while making newly shipped actions available.
    @discardableResult
    public mutating func addMissingOmarchyShortcuts() -> Int {
        let originalCount = shortcuts.count
        for candidate in Self.omarchyShortcuts {
            let exists = shortcuts.contains {
                ($0.key.lowercased() == candidate.key.lowercased() && Set($0.modifiers) == Set(candidate.modifiers))
                    || ($0.action == candidate.action && $0.target == candidate.target)
            }
            if !exists { shortcuts.append(candidate) }
        }
        return shortcuts.count - originalCount
    }
}

public struct Layout: Codable, Equatable, Sendable {
    public var name: String
    public var adaptive = false
    public var fallbackToPrimary = false
    public var applyGap = true
    public var placements: [Placement]
    public init(name: String, placements: [Placement]) { self.name = name; self.placements = placements }
    private enum CodingKeys: String, CodingKey { case name, placements, fallbackToPrimary, applyGap, adaptive }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        placements = try c.decode([Placement].self, forKey: .placements)
        fallbackToPrimary = try c.decodeIfPresent(Bool.self, forKey: .fallbackToPrimary) ?? false
        applyGap = try c.decodeIfPresent(Bool.self, forKey: .applyGap) ?? true
        adaptive = try c.decodeIfPresent(Bool.self, forKey: .adaptive) ?? false
    }

}

public struct Placement: Codable, Equatable, Sendable {
    public var bundleID: String
    public var titleContains = ""
    public var windowIndex = 0
    public var display: String
    public var frame: Rect
    public init(bundleID: String, display: String, frame: Rect) {
        self.bundleID = bundleID; self.display = display; self.frame = frame
    }
}

public enum Action: String, Codable, CaseIterable, Sendable {
    case launch, layout, toggleTiling, retile, focusWindow, swapWindow, resizeWindow, maximizeWindow
}

public struct Shortcut: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [String]
    public var action: Action
    public var target: String
    public init(key: String, modifiers: [String] = ["ctrl", "alt", "cmd"], action: Action, target: String = "") {
        self.key = key; self.modifiers = modifiers; self.action = action; self.target = target
    }

    /// Called only by an explicit action-picker edit, never by a model refresh.
    public mutating func selectAction(_ next: Action) {
        guard next != action else { return }
        action = next
        switch next {
        case .focusWindow, .swapWindow:
            if WindowDirection(rawValue: target) == nil {
                target = WindowDirection(rawValue: key.lowercased())?.rawValue ?? "left"
            }
        case .resizeWindow:
            if !["wider", "narrower", "taller", "shorter"].contains(target) { target = "wider" }
        default: break
        }
    }
}

public struct ConfigError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Physical ANSI positions. The UI and README make this explicit for non-US layouts.
public enum KeyMap {
    public static let codes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "tab": 48, "space": 49, "escape": 53,
        "minus": 27, "equal": 24, "slash": 44,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]
}

public struct MonitorProfile: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var displayIDs: [String]
    public var layoutName: String
    public var enabled = true
    public init(name: String, displayIDs: [String], layoutName: String) {
        self.name = name; self.displayIDs = displayIDs.sorted(); self.layoutName = layoutName
    }
    public func matches(_ ids: [String]) -> Bool { enabled && Set(displayIDs) == Set(ids) }
}
