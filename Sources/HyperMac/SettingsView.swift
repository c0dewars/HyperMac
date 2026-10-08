import AppKit
import SwiftUI
import HyperMacCore

@MainActor
final class SettingsModel: ObservableObject {
    let layoutEditor = LayoutEditorState()
    @Published var draft: Configuration { didSet { scheduleSave() } }
    private var pendingSave: Task<Void, Never>?
    private var loading = false
    @Published var saving = false
    @Published var message = ""
    @Published var runtimeStatus = ""
    @Published var displays = ScreenCatalog.current()
    @Published var captureName = "My layout"
    @Published var shortcutSearch = ""
    private let original: () -> Configuration
    private var baseline: Configuration
    private let saveAction: (Configuration) throws -> Void
    private let captureAction: (String) async throws -> HyperMacCore.Layout
    private let arrangeAction: (String) -> Void
    let previewAction: (HyperMacCore.Layout, Double) async -> ArrangementPreview
    let undoAction: () -> Void
    let redoAction: () -> Void
    let canRedo: () -> Bool
    let canUndo: () -> Bool
    let tileAction: () -> Void
    let pauseAction: () -> Void
    let copyDiagnostics: () -> Void
    var readDiagnostics: () -> String = { "" }
    var navigateScrolling: (String, String, String?) -> Void = { _, _, _ in }
    let configURL: URL

    init(config: Configuration, url: URL, original: @escaping () -> Configuration,
         save: @escaping (Configuration) throws -> Void, capture: @escaping (String) async throws -> HyperMacCore.Layout,
         preview: @escaping (HyperMacCore.Layout, Double) async -> ArrangementPreview,
         undo: @escaping () -> Void, canUndo: @escaping () -> Bool,
         redo: @escaping () -> Void, canRedo: @escaping () -> Bool,
         arrange: @escaping (String) -> Void, tile: @escaping () -> Void,
         pause: @escaping () -> Void, diagnostics: @escaping () -> Void) {
        draft = config; baseline = config; configURL = url; self.original = original; saveAction = save; captureAction = capture
        previewAction = preview; undoAction = undo; self.canUndo = canUndo; redoAction = redo; self.canRedo = canRedo
        arrangeAction = arrange
        tileAction = tile; pauseAction = pause; copyDiagnostics = diagnostics
    }
    var hasChanges: Bool { draft != baseline }
    private func scheduleSave() {
        pendingSave?.cancel()
        guard !loading else { return }
        guard hasChanges else { saving = false; message = "All changes saved."; return }
        saving = true
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            _ = self.save()
        }
    }
    func setBlurEnabled(_ enabled: Bool) {
        // The off switch must work even while an unrelated shortcut is incomplete.
        draft.blurUnfocusedWindows = enabled
        do {
            guard original() == baseline else { throw ConfigError("Settings changed outside this window. Reload before editing.") }
            var next = baseline; next.blurUnfocusedWindows = enabled
            try saveAction(next); baseline = next
            message = enabled ? "Blur enabled." : "Blur is off."
            scheduleSave()
        } catch { message = error.localizedDescription }
    }
    @discardableResult func save() -> Bool {
        pendingSave?.cancel()
        saving = false
        guard hasChanges else { return true }
        do {
            guard original() == baseline else { throw ConfigError("Settings changed outside this window. Reload active settings before saving.") }
            try saveAction(draft); baseline = draft; message = "Saved automatically."
            return true
        }
        catch { message = error.localizedDescription; return false }
    }
    @discardableResult func saveAndArrange(_ name: String) -> Bool {
        guard save() else { return false }; arrangeAction(name); return true
    }
    func reload() {
        loading = true; pendingSave?.cancel(); saving = false
        draft = original(); baseline = draft; loading = false
        message = "Loaded saved settings."; displays = ScreenCatalog.current()
    }
    func capture() {
        Task {
            do {
                let name = captureName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !draft.layouts.contains(where: { $0.name == name }) else {
                    throw ConfigError("Choose a new, nonempty layout name.")
                }
                let layout = try await captureAction(name)
                draft.layouts.append(layout)
                message = "Captured. Review the Layouts tab to arrange windows. Capture pauses tiling."
            } catch { message = error.localizedDescription }
        }
    }
}

// Keep transient settings UI state in one observable object owned by SettingsView.
@MainActor
final class SettingsUIState: ObservableObject {
    @Published var section = "General"
    @Published var showDetails = false
    @Published var showReport = false
    @Published var report = ""
    @Published var shortcutCategory = "All"
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    @StateObject private var ui = SettingsUIState()
    private var section: String {
        get { ui.section }
        nonmutating set { ui.section = newValue }
    }
    private var showDetails: Bool {
        get { ui.showDetails }
        nonmutating set { ui.showDetails = newValue }
    }
    private let sections = [("General", "slider.horizontal.3"), ("Shortcuts", "keyboard"),
                            ("Layouts", "rectangle.split.3x1"), ("Displays", "display.2")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable().frame(width: 32, height: 32)
                    Text("HyperMac").font(.headline)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(sections, id: \.0) { name, symbol in
                        Button { section = name } label: {
                            Label(name, systemImage: symbol)
                                .font(.callout.weight(section == name ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(section == name ? AppTheme.cyan : Color.secondary)
                                .background(section == name ? AppTheme.cyan.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityAddTraits(section == name ? .isSelected : [])
                    }
                }
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            Group {
                switch section {
                case "Shortcuts": shortcuts
                case "Layouts": layouts
                case "Displays": displays
                default: general
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "rectangle.3.group").foregroundStyle(AppTheme.cyan)
                    Text(model.runtimeStatus.components(separatedBy: " — ").first ?? "Ready")
                        .font(.callout).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button(showDetails ? "Hide details" : "Details") { showDetails.toggle() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if showDetails {
                    ScrollView { Text(model.runtimeStatus).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 65)
                }
                if !model.message.isEmpty && !["Saved automatically.", "All changes saved."].contains(model.message) {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(model.message)
                }
                HStack(spacing: 12) {
                    Menu("More") {
                        Button("Open config file") { NSWorkspace.shared.open(model.configURL) }
                        Button("View troubleshooting report") { ui.report = model.readDiagnostics(); ui.showReport = true }
                        Button("Copy troubleshooting report") { model.copyDiagnostics() }
                    }.fixedSize()
                    Button("Reload") { model.reload() }.help("Reload saved settings and discard incomplete edits")
                    Spacer()
                    Label(model.saving ? "Saving…" : model.hasChanges ? "Changes need attention" : "All changes saved",
                          systemImage: model.hasChanges ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.caption).foregroundStyle(model.hasChanges ? AppTheme.violet : Color.secondary)
                    if model.hasChanges && !model.saving { Button("Retry save") { model.save() } }

                }
            }.padding(.horizontal, 24).padding(.vertical, 14)
                .background(.background)
        }
        .tint(AppTheme.cyan)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 820, minHeight: 620)
        .sheet(isPresented: $ui.showReport) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Troubleshooting report").font(.title2.bold())
                Text("Window identities, placement and navigation timing. Document titles are omitted.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(ui.report).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button("Refresh report") { ui.report = model.readDiagnostics() }
                    Button("Copy report") { model.copyDiagnostics() }
                    Spacer()
                    Button("Done") { ui.showReport = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 760, height: 560)
        }
    }

    private var general: some View {
        Form {
            Section("Window management") {
                HStack {
                    Button("Tile now") { if model.save() { model.tileAction() } }.buttonStyle(.borderedProminent)
                    Button("Pause") { model.pauseAction() }
                    Button("Copy troubleshooting report") { model.copyDiagnostics() }
                }
                Toggle("Start automatic tiling when HyperMac launches", isOn: $model.draft.automaticTiling)
                Toggle("Mouse resizing adjusts tiles and scrolling columns", isOn: $model.draft.mouseResize)
                Text("Drag a window edge or corner in Dynamic splits or horizontal scrolling. Neighbors adjust when you release the mouse.").font(.caption).foregroundStyle(.secondary)
                Picker("Tiling algorithm", selection: $model.draft.algorithm) {
                    Text("Dynamic splits (BSP)").tag(TileAlgorithm.bsp)
                    Text("Adaptive grid").tag(TileAlgorithm.adaptive)
                    Text("Equal columns").tag(TileAlgorithm.columns)
                    Text("Main window + stack").tag(TileAlgorithm.masterStack)
                }
                HStack {
                    Text("Gap (points)")
                    Slider(value: $model.draft.gap, in: 0...80, step: 1)
                    Text("\(Int(model.draft.gap))").monospacedDigit().frame(width: 35)
                }
                HStack {
                    Text("Transition duration")
                    Slider(value: $model.draft.animationDuration, in: 0...0.5, step: 0.02)
                    Text(model.draft.animationDuration == 0 ? "Off" : "\(Int(model.draft.animationDuration * 1000)) ms")
                        .monospacedDigit().frame(width: 60)
                }
                Text("Smooth transitions respect macOS Reduce Motion. Set to Off for instant placement.")
                    .foregroundStyle(.secondary)
                Text("Applying a saved layout switches out of automatic tiling. Use Toggle tiling or Retile to return.")
                    .foregroundStyle(.secondary)
            }
            Section("Tiled-window borders") {
                Toggle("Window borders", isOn: $model.draft.borderEnabled)
                Toggle("Only outline the focused window", isOn: $model.draft.focusedBorderOnly)
                Toggle("Blur unfocused windows", isOn: Binding(get: { model.draft.blurUnfocusedWindows }, set: { model.setBlurEnabled($0) }))
                Text(model.draft.blurUnfocusedWindows ? "Blur is on · changes apply automatically." : "Off · no blur overlays are shown.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Blur intensity")
                    Slider(value: $model.draft.blurIntensity, in: 0...1, step: 0.05)
                        .disabled(!model.draft.blurUnfocusedWindows)
                    Text("\(Int((model.draft.blurIntensity * 100).rounded()))%").monospacedDigit().frame(width: 48)
                }
                Text("Adjusts the strength of the native blur overlay; macOS controls its blur radius.")
                    .font(.caption).foregroundStyle(.secondary)
                ColorPicker("Border color", selection: Binding(
                    get: { Color(nsColor: AppColor.nsColor(model.draft.borderColor)) },
                    set: { model.draft.borderColor = AppColor.hex($0) }), supportsOpacity: false)
                HStack {
                    Text("Border width")
                    Slider(value: $model.draft.borderWidth, in: 1...10, step: 1)
                    Text("\(Int(model.draft.borderWidth)) pt").monospacedDigit()
                }
                Text("The border uses each app’s custom color, falling back to the default below. Optional blur applies to unfocused windows across active layouts and tiling, including centered scrolling. Effects disappear when paused or an ignored app is focused. Blur respects Reduce Transparency.")
                    .foregroundStyle(.secondary)
            }
            Section("Capture your arrangement") {
                TextField("Layout name", text: $model.captureName)
                Button("Capture visible windows") { model.capture() }
                Text("Capture stores display IDs and window-title rules. Change them to portable display roles or shorter title rules in Layouts.")
                    .foregroundStyle(.secondary)
            }
            Section("Floating apps · ignored by tiling") {
                Text("All supported app windows tile automatically. Choose exceptions below to leave their position and size alone.")
                    .foregroundStyle(.secondary)
                ForEach(model.draft.excludedBundleIDs.filter { $0 != "local.hypermac.app" }, id: \.self) { id in
                    HStack {
                        AppIdentity(target: id)
                        Spacer()
                        Button("Allow tiling", systemImage: "minus.circle") { model.draft.excludedBundleIDs.removeAll { $0 == id } }
                    }
                }
                Button("Choose apps to ignore…", systemImage: "plus.app") {
                    AppSelection.choose(multiple: true) { ids in
                        for id in ids where !model.draft.excludedBundleIDs.contains(id) { model.draft.excludedBundleIDs.append(id) }
                    }
                }
                Text("HyperMac's own settings, dialogs and native fullscreen windows are always left alone. Changes save automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                Button("Request Accessibility access") { _ = Accessibility.requestPermission() }
                HStack {
                    Button("Show this app in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    Button("Copy app path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Bundle.main.bundleURL.path, forType: .string)
                        model.message = "App path copied. In the Accessibility + dialog press Command-Shift-G, paste it, then Open."
                    }
                }
                Text(Bundle.main.bundleURL.path).font(.caption).textSelection(.enabled)
                Text("In System Settings → Privacy & Security → Accessibility, click +, then Command-Shift-G and paste the app path. Enable HyperMac, then click Tile now. If rebuilding leaves a stale entry, remove it and add this installed app again.")
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keyboard shortcuts").font(.title2.weight(.semibold))
                    Text("Click a key combination to record your own. Changes save automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Window action…") {
                        model.draft.shortcuts.append(Shortcut(key: "", modifiers: ["ctrl", "alt", "cmd", "shift"], action: .groupPrevious))
                        ui.shortcutCategory = "All"; model.shortcutSearch = ""
                    }
                    Button("Application…") {
                        AppSelection.choose { ids in
                            guard let id = ids.first else { return }
                            model.draft.shortcuts.append(Shortcut(key: "", modifiers: ["ctrl", "alt", "cmd", "shift"], action: .launch, target: id))
                            ui.shortcutCategory = "All"; model.shortcutSearch = ""
                        }
                    }
                } label: { Label("Add shortcut", systemImage: "plus") }
                .fixedSize()
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search actions, apps or keys", text: $model.shortcutSearch).textFieldStyle(.plain)
                Picker("Filter", selection: $ui.shortcutCategory) {
                    ForEach(["All", "Windows", "Apps", "Layouts"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
            }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.draft.shortcuts.indices, id: \.self) { index in
                        let shortcut = model.draft.shortcuts[index]
                        let category = shortcut.action == .launch ? "Apps" : shortcut.action == .layout ? "Layouts" : "Windows"
                        if (ui.shortcutCategory == "All" || ui.shortcutCategory == category) &&
                            (model.shortcutSearch.isEmpty || "\(shortcut.friendlyTitle) \(shortcut.target) \(shortcut.key)".localizedCaseInsensitiveContains(model.shortcutSearch)) {
                            ShortcutEditor(shortcut: $model.draft.shortcuts[index], layouts: model.draft.layouts.map(\.name)) {
                                model.draft.shortcuts.remove(at: index)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .top) {
                Text("Hyper = ⌃ ⌥ ⌘ ⇧ · your Karabiner Caps Lock\nHyper + H / L moves focus left / right. Hyper + arrows swaps windows.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Defaults") {
                    Button("Add missing Hyper shortcuts") { _ = model.draft.addMissingOmarchyShortcuts() }
                    Button("Restore all Hyper defaults") { model.draft.shortcuts = Configuration.omarchyShortcuts }
                }.fixedSize()
            }
        }.padding(20)
    }

    private var layouts: some View {
        LayoutDesigner(model: model)
    }

    private var displays: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Automatic monitor profiles") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save a layout for this exact connected-monitor setup. HyperMac applies it at startup and after docking or undocking settles.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(model.draft.monitorProfiles.indices, id: \.self) { i in
                            VStack(alignment: .leading) {
                                HStack {
                                    Toggle("Enabled", isOn: $model.draft.monitorProfiles[i].enabled)
                                    TextField("Profile name", text: $model.draft.monitorProfiles[i].name)
                                    Picker("Layout", selection: $model.draft.monitorProfiles[i].layoutName) {
                                        ForEach(model.draft.layouts, id: \.name) { Text($0.name).tag($0.name) }
                                    }
                                    Button("Remove") { model.draft.monitorProfiles.remove(at: i) }
                                }
                                Text("\(model.draft.monitorProfiles[i].displayIDs.count) displays · " +
                                    (model.draft.monitorProfiles[i].matches(model.displays.map(\.id)) ? "Matches now" : "Not active"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Add current monitor setup") {
                            guard let layout = model.draft.layouts.first else { return }
                            model.draft.monitorProfiles.append(MonitorProfile(name: "Setup \(model.draft.monitorProfiles.count + 1)",
                                displayIDs: model.displays.map(\.id), layoutName: layout.name))
                        }.disabled(model.draft.layouts.isEmpty || model.displays.isEmpty)
                        Text("Profiles save automatically. Create a separate profile while each monitor setup is connected.").font(.caption)
                    }.padding(8)
                }
                Button("Refresh displays") { model.displays = ScreenCatalog.current() }
                ForEach(model.displays) { display in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(display.name + (display.builtIn ? " · built-in" : " · external")).font(.headline)
                            Text("Usable: \(Int(display.usable.width)) × \(Int(display.usable.height)) logical points")
                            Text("Selector: uuid:\(display.id)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                Text("Logical points may differ from physical resolution because of macOS scaling. Missing displays are skipped unless a layout enables fallback to primary; fallback can cause overlap.")
                    .foregroundStyle(.secondary)
            }.padding(16)
        }
    }
}

@MainActor
private extension Shortcut {
    var friendlyTitle: String {
        switch action {
        case .launch: return "Open " + AppSelection.name(for: target)
        case .layout: return "Apply " + (target.isEmpty ? "layout" : target)
        case .focusWindow: return "Focus " + target
        case .swapWindow: return "Move window " + target
        case .resizeWindow: return "Resize " + target
        case .maximizeWindow: return "Maximize / restore"
        case .toggleTiling: return "Pause / resume tiling"
        case .retile: return "Arrange windows"
        case .groupPrevious: return "Stack in previous column"
        case .groupNext: return "Stack in next column"
        case .ungroupWindow: return "Separate into a column"
        case .centerColumn: return "Center focused column"
        }
    }
}

@MainActor
private struct ShortcutEditor: View {
    @Binding var shortcut: Shortcut
    let layouts: [String]
    var remove: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if shortcut.action == .launch, let url = AppSelection.url(for: shortcut.target) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                } else {
                    Image(systemName: "rectangle.split.3x1").foregroundStyle(AppTheme.cyan).frame(width: 28)
                }
                Text(shortcut.friendlyTitle).font(.callout.weight(.medium))
                Spacer()
                ShortcutRecorder(shortcut: $shortcut).frame(width: 190, height: 30)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Edit action")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Remove shortcut")
            }
            if expanded {
                Divider()
                HStack {
                    Picker("Action", selection: Binding(get: { shortcut.action }, set: { shortcut.selectAction($0) })) {
                        Text("Open app").tag(Action.launch)
                        Text("Apply layout").tag(Action.layout)
                        Text("Pause / resume tiling").tag(Action.toggleTiling)
                        Text("Arrange windows").tag(Action.retile)
                        Text("Stack in previous column").tag(Action.groupPrevious)
                        Text("Stack in next column").tag(Action.groupNext)
                        Text("Separate into a column").tag(Action.ungroupWindow)
                        Text("Center column").tag(Action.centerColumn)
                        Text("Focus window").tag(Action.focusWindow)
                        Text("Move window").tag(Action.swapWindow)
                        Text("Resize window").tag(Action.resizeWindow)
                        Text("Maximize / restore").tag(Action.maximizeWindow)
                    }.frame(maxWidth: 300)
                    if shortcut.action == .launch {
                        Button("Choose app…", systemImage: "folder") {
                            AppSelection.choose { ids in if let id = ids.first { shortcut.target = id } }
                        }
                    } else if shortcut.action == .layout {
                        Picker("Layout", selection: $shortcut.target) {
                            Text("Choose layout").tag("")
                            ForEach(layouts, id: \.self) { Text($0).tag($0) }
                        }
                    } else if shortcut.action == .focusWindow || shortcut.action == .swapWindow {
                        Picker("Direction", selection: $shortcut.target) {
                            ForEach(WindowDirection.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                        }
                    } else if shortcut.action == .resizeWindow {
                        Picker("Size", selection: $shortcut.target) {
                            ForEach(["wider", "narrower", "taller", "shorter"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    }
                }
                Text("Click the key combination, press your shortcut, then release. Escape cancels. Keys use physical US/ANSI positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.cyan.opacity(expanded ? 0.4 : 0.08)))
    }
}

@MainActor
struct PlacementEditor: View {
    @Binding var placement: Placement
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("App bundle ID", text: $placement.bundleID)
                TextField("Display role or uuid:…", text: $placement.display)
                Button("Remove", role: .destructive, action: remove)
            }
            HStack {
                TextField("Title contains (optional)", text: $placement.titleContains)
                Text("Window index")
                TextField("0", value: $placement.windowIndex, format: .number).frame(width: 50)
            }
            HStack {
                percent("X", $placement.frame.x)
                percent("Y", $placement.frame.y)
                percent("Width", $placement.frame.width)
                percent("Height", $placement.frame.height)
            }
        }
    }
    private func percent(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            TextField("%", value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }), format: .number)
                .frame(width: 65)
            Text("%")
        }
    }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let model: SettingsModel
    init(model: SettingsModel) {
        self.model = model
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
            width: max(820, min(1080, available.width - 48)),
            height: max(620, min(820, available.height - 100))),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "HyperMac Settings"
        window.contentMinSize = NSSize(width: 820, height: 620)
        window.titlebarAppearsTransparent = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.save() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
