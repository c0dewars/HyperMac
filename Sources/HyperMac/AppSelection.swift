import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTheme {
    static let cyan = Color(red: 0.12, green: 0.70, blue: 0.85)
    static let violet = Color(red: 0.57, green: 0.45, blue: 0.94)
    static let mint = Color(red: 0.65, green: 0.95, blue: 0.76)
    static let indigo = Color(red: 0.09, green: 0.12, blue: 0.29)
}

@MainActor
enum AppSelection {
    static let aliases: [String: (String, [String])] = [
        "@terminal": ("Preferred terminal", ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal"]),
        "@editor": ("Preferred editor", ["com.microsoft.VSCode", "com.apple.TextEdit"]),
        "@ai": ("AI assistant", ["com.openai.chat", "com.openai.codex"]),
        "@music": ("Music", ["com.spotify.client", "com.apple.Music"]),
        "@messenger": ("Messenger", ["org.whispersystems.signal-desktop", "net.whatsapp.WhatsApp", "com.apple.MobileSMS"]),
        "@notes": ("Notes", ["md.obsidian", "com.apple.Notes"]),
        "@passwords": ("Password manager", ["com.1password.1password", "com.nordpass.safari.app.password.manager", "com.apple.Passwords"])
    ]

    static func url(for target: String) -> URL? {
        if target == "@browser" {
            return NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        }
        return (aliases[target]?.1 ?? [target]).compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }.first
    }

    static func name(for target: String) -> String {
        if target.isEmpty { return "Choose an application" }
        if let url = url(for: target) { return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        if target == "com.apple.Safari" { return "Safari" }
        if target == "com.apple.Terminal" { return "Terminal" }
        return aliases[target]?.0 ?? (target == "@browser" ? "Default browser" : "Unavailable application")
    }

    static func choose(multiple: Bool = false, completion: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = multiple ? "Choose apps to keep floating" : "Choose an application"
        panel.prompt = multiple ? "Ignore selected apps" : "Choose app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple; panel.treatsFilePackagesAsDirectories = false
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            guard ids.count == panel.urls.count else {
                let alert = NSAlert()
                alert.messageText = "Choose a valid macOS application"
                alert.informativeText = "Each selected app needs an application identifier."
                alert.runModal(); return
            }
            completion(ids)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { panel.begin(completionHandler: finish) }
    }
}

struct AppIdentity: View {
    var target: String
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppSelection.url(for: target).map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppSelection.name(for: target)).fontWeight(.medium)
                if target.hasPrefix("@") {
                    Text(target == "@browser" ? "Follows your default browser" : "Automatically chooses an installed app")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.help(target)
    }
}
