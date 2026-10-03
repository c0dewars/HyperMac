import AppKit
import ApplicationServices
import HyperMacCore

@main
struct HyperMacApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let hotKeys = HotKeys()
    private var engine: Engine!
    private let focusBorder = FocusBorder()
    private var configuration = Configuration.starter
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindow?
    private var status = "Starting…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.hypermac.app").count > 1 {
            NSApplication.shared.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "HyperMac")
        var startupError: String?
        do { configuration = try store.load() }
        catch { startupError = "Configuration was not loaded: \(error.localizedDescription)" }
        engine = Engine(config: configuration)
        engine.onTransition = { [weak self] active in self?.focusBorder.setTransitioning(active) }
        engine.onModeChange = { [weak self] active in self?.focusBorder.setActive(active) }
        engine.onStatus = { [weak self] status in
            self?.status = status
            self?.settingsWindow?.model.runtimeStatus = status
            self?.focusBorder.schedule()
            self?.rebuildMenu()
        }
        hotKeys.onError = { [weak self] message in self?.showError(message) }
        hotKeys.onAction = { [weak self] shortcut in self?.engine.run(shortcut) }
        do { try hotKeys.replace(with: configuration.shortcuts) }
        catch { startupError = error.localizedDescription }
        store.onChange = { [weak self] result in
            guard let self else { return }
            do { try self.apply(result.get(), persist: false) }
            catch { self.status = "Config rejected: \(error.localizedDescription)"; self.rebuildMenu() }
        }
        store.startWatching()
        engine.start()
        focusBorder.start(config: configuration)
        focusBorder.setActive(engine.mode != .paused)
        rebuildMenu()
        // Standard edit menu allows Cmd+C/V/X/A in the native settings window.
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        if !AXIsProcessTrusted() { _ = Accessibility.requestPermission(); showSettings() }
        if let startupError { showError(startupError) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func apply(_ next: Configuration, persist: Bool) throws {
        try next.validate()
        try hotKeys.replace(with: next.shortcuts)
        do { if persist { try store.save(next) } }
        catch { try? hotKeys.replace(with: configuration.shortcuts); throw error }
        configuration = next
        engine.update(next)
        focusBorder.update(next)
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard statusItem != nil else { return }
        statusItem.button?.toolTip = status
        let menu = NSMenu()
        let statusRow = NSMenuItem(title: String(status.prefix(110)), action: nil, keyEquivalent: "")
        statusRow.isEnabled = false; menu.addItem(statusRow)
        menu.addItem(.separator())
        add("Resume / automatic tiling", action: #selector(resume), to: menu)
        add("Pause", action: #selector(pause), to: menu)
        let layouts = NSMenu()
        for layout in configuration.layouts {
            let item = NSMenuItem(title: layout.name, action: #selector(applyLayout(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = layout.name; layouts.addItem(item)
        }
        let row = NSMenuItem(title: "Apply layout", action: nil, keyEquivalent: "")
        row.submenu = layouts; menu.addItem(row)
        menu.addItem(.separator())
        add("Settings & capture…", action: #selector(showSettings), to: menu)
        add("Reload configuration", action: #selector(reload), to: menu)
        add("Copy troubleshooting report", action: #selector(copyDiagnostics), to: menu)
        add("Quit HyperMac", action: #selector(quit), to: menu)
        statusItem.menu = menu
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }

    @objc private func resume() { engine.retile(); focusBorder.schedule() }
    @objc private func pause() { engine.pause() }
    @objc private func applyLayout(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { engine.applyLayout(name) }
    }
    @objc private func reload() {
        do { try apply(store.load(), persist: false) }
        catch { showError(error.localizedDescription) }
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.diagnosticReport, forType: .string)
        settingsWindow?.model.message = "Troubleshooting report copied. It contains app IDs and window geometry, not document titles."
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(config: configuration, url: store.url, original: { [unowned self] in self.configuration },
                save: { [unowned self] in try self.apply($0, persist: true) },
                capture: { [unowned self] in try await self.engine.capture(name: $0) },
                preview: { [unowned self] in await self.engine.preview($0, gap: $1) },
                undo: { [unowned self] in self.engine.undoArrangement() },
                canUndo: { [unowned self] in self.engine.canUndo },
                redo: { [unowned self] in self.engine.redoArrangement() },
                canRedo: { [unowned self] in self.engine.canRedo },
                arrange: { [unowned self] in self.engine.applyLayout($0) },
                tile: { [unowned self] in self.resume() }, pause: { [unowned self] in self.pause() },
                diagnostics: { [unowned self] in self.copyDiagnostics() })
            model.runtimeStatus = status
            settingsWindow = SettingsWindow(model: model)
            settingsWindow?.onClose = { [weak self] in self?.settingsWindow = nil }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
    }

    private func showError(_ message: String) {
        status = message; rebuildMenu()
        let alert = NSAlert()
        alert.messageText = "HyperMac"
        alert.informativeText = message
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) { engine?.stop(); focusBorder.stop() }
}
