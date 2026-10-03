import AppKit
import SwiftUI

struct InstalledApp: Identifiable, Sendable {
    var id: String
    var name: String
    var path: String
}

@MainActor
final class AppLibrary: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    private var icons: [String: NSImage] = [:]

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            let found = await Task.detached(priority: .utility) { () -> [InstalledApp] in
                Self.scanInstalledApps()
            }.value
            apps = found; loading = false
        }
    }

    // Directory enumeration is synchronous; run it on the utility task without suspending.
    nonisolated private static func scanInstalledApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [String: InstalledApp] = [:]
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, found[id] == nil else { continue }
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
                found[id] = InstalledApp(id: id, name: name, path: url.path)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func name(_ id: String) -> String { apps.first { $0.id == id }?.name ?? AppSelection.name(for: id) }
    func icon(_ id: String) -> NSImage {
        if let icon = icons[id] { return icon }
        let path = apps.first { $0.id == id }?.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
        let icon = path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        icons[id] = icon
        return icon
    }
}

enum AppColor {
    static func nsColor(_ hex: String) -> NSColor {
        let number = UInt32(hex.dropFirst(), radix: 16) ?? 0x59A6FF
        return NSColor(srgbRed: CGFloat((number >> 16) & 255) / 255,
                       green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
