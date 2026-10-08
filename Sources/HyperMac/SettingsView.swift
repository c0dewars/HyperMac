import AppKit
import SwiftUI
import HyperMacCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: Configuration
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
    @discardableResult func save() -> Bool {
        do {
            guard original() == baseline else { throw ConfigError("Settings changed outside this window. Reload active settings before saving.") }
            try saveAction(draft); baseline = draft; message = "Settings saved. Use Tile now or Save & arrange to position windows."
            return true
        }
        catch { message = error.localizedDescription; return false }
    }
    @discardableResult func saveAndArrange(_ name: String) -> Bool {
        guard save() else { return false }; arrangeAction(name); return true
    }
    func reload() { draft = original(); baseline = draft; message = "Loaded active configuration."; displays = ScreenCatalog.current() }
    func capture() {
        Task {
            do {
                let name = captureName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !draft.layouts.contains(where: { $0.name == name }) else {
                    throw ConfigError("Choose a new, nonempty layout name.")
                }
                let layout = try await captureAction(name)
                draft.layouts.append(layout)
                message = "Captured. Review the Layouts tab, then Save. Capture pauses tiling."
            } catch { message = error.localizedDescription }
        }
    }
}

// Keep transient settings UI state in one observable object owned by SettingsView.
@MainActor
final class SettingsUIState: ObservableObject {
    @Published var section = "General"
    @Published var showDetails = false
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
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HyperMac").font(.title2.weight(.semibold))
                    Text("Your workspace, arranged.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            HStack(spacing: 6) {
                ForEach(sections, id: \.0) { name, symbol in
                    Button { section = name } label: {
                        Label(name, systemImage: symbol)
                            .font(.callout.weight(section == name ? .semibold : .regular))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(section == name ? AppTheme.cyan : Color.secondary)
                            .background(section == name ? AppTheme.cyan.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(section == name ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).padding(.bottom, 12)
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
                if !model.message.isEmpty {
                    Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(model.message)
                }
                HStack(spacing: 12) {
                    Menu("More") {
                        Button("Open config file") { NSWorkspace.shared.open(model.configURL) }
                        Button("Copy troubleshooting report") { model.copyDiagnostics() }
                    }.fixedSize()
                    Button("Reload") { model.reload() }.help("Discard draft changes and reload active settings")
                    Spacer()
                    if model.hasChanges {
                        Label("Unsaved changes", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(AppTheme.violet)
                    }
                    Button("Save changes") { model.save() }.keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent).disabled(!model.hasChanges)
                }
            }.padding(.horizontal, 24).padding(.vertical, 14)
                .background(.background)
        }
        .tint(AppTheme.cyan)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 820, minHeight: 620)
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
                Toggle("Mouse resizing adjusts Dynamic splits", isOn: $model.draft.mouseResize)
                Text("Drag a window edge or corner in automatic Dynamic splits mode. Neighbors adjust when you release the mouse.").font(.caption).foregroundStyle(.secondary)
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
                Toggle("Outline all tiled windows", isOn: $model.draft.borderEnabled)
                ColorPicker("Border color", selection: Binding(
                    get: { Color(nsColor: AppColor.nsColor(model.draft.borderColor)) },
                    set: { model.draft.borderColor = AppColor.hex($0) }), supportsOpacity: false)
                HStack {
                    Text("Border width")
                    Slider(value: $model.draft.borderWidth, in: 1...10, step: 1)
                    Text("\(Int(model.draft.borderWidth)) pt").monospacedDigit()
                }
                Text("A light-green outline is shared by all tiled apps. Borders disappear when tiling is paused; ignored apps stay floating without borders.")
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
                Text("HyperMac's own settings, dialogs and native fullscreen windows are always left alone. Save settings to apply your list.")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your shortcuts").font(.title2.bold())
                    Spacer()
                    TextField("Search apps or actions", text: $model.shortcutSearch)
                        .textFieldStyle(.roundedBorder).frame(width: 250)
                }
                Text("Omarchy: Super = Ctrl–Option–Command; Super+Shift = Hyper (all four modifiers, including your Karabiner Caps Lock). Hyper+arrows swaps windows; Ctrl–Option–Command+arrows focuses. In Dynamic splits mode, swaps and resizing keep automatic tiling active.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Add missing Omarchy shortcuts") {
                        let count = model.draft.addMissingOmarchyShortcuts()
                        model.message = "Added \(count) shortcuts. Existing bindings were preserved. Save settings to apply."
                    }
                    Button("Use Omarchy / Hyper defaults") { model.draft.shortcuts = Configuration.omarchyShortcuts }
                }
                Text("\(model.draft.shortcuts.count) editable shortcuts · Change the modifiers, key, action, and target below, then Save settings.")
                    .font(.headline)
                Text("Choose an app from Applications, then set its key and modifiers. Use defaults replaces this draft; adding missing shortcuts preserves your choices. Keys use physical US/ANSI positions.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.draft.shortcuts.indices, id: \.self) { index in
                    let shortcut = model.draft.shortcuts[index]
                    if model.shortcutSearch.isEmpty || "\(AppSelection.name(for: shortcut.target)) \(shortcut.action.rawValue) \(shortcut.target) \(shortcut.key)".localizedCaseInsensitiveContains(model.shortcutSearch) {
                        ShortcutEditor(shortcut: $model.draft.shortcuts[index]) {
                            model.draft.shortcuts.remove(at: index)
                        }
                        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.violet.opacity(0.16)))
                    }
                }
                Button("Add app shortcut…", systemImage: "plus") {
                    AppSelection.choose { ids in
                        guard let id = ids.first else { return }
                        model.draft.shortcuts.append(Shortcut(key: "", modifiers: ["ctrl", "alt", "cmd", "shift"], action: .launch, target: id))
                        model.shortcutSearch = ""
                        model.message = "App added. Choose a key for its shortcut before saving."
                    }
                }
            }.padding(16)
        }
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
                        Text("Save changes to enable profiles. Create a separate profile while each monitor setup is connected.").font(.caption)
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
private struct ShortcutEditor: View {
    @Binding var shortcut: Shortcut
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ShortcutRecorder(shortcut: $shortcut).frame(width: 180, height: 28)
                Spacer()
            }
            HStack {
                Button("Hyper") { shortcut.modifiers = ["ctrl", "alt", "cmd", "shift"] }
                    .help("Control + Option + Command + Shift, including Caps Lock mapped by Karabiner")
                ForEach(["ctrl", "alt", "cmd", "shift"], id: \.self) { modifier in
                    Toggle(modifier, isOn: Binding(get: { shortcut.modifiers.contains(modifier) }, set: { enabled in
                        shortcut.modifiers.removeAll { $0 == modifier }
                        if enabled { shortcut.modifiers.append(modifier) }
                    }))
                }
                TextField("Key", text: $shortcut.key).frame(width: 70)
                Spacer()
                Button("Remove", role: .destructive, action: remove)
            }
            HStack {
                Picker("Action", selection: Binding(get: { shortcut.action }, set: { shortcut.selectAction($0) })) {
                    Text("Launch/focus app").tag(Action.launch)
                    Text("Apply layout").tag(Action.layout)
                    Text("Toggle tiling").tag(Action.toggleTiling)
                    Text("Retile").tag(Action.retile)
                    Text("Focus window in direction").tag(Action.focusWindow)
                    Text("Swap window in direction").tag(Action.swapWindow)
                    Text("Resize focused window").tag(Action.resizeWindow)
                    Text("Maximize / restore window").tag(Action.maximizeWindow)
                }.frame(width: 250)
                if shortcut.action == .launch {
                    AppIdentity(target: shortcut.target)
                    Spacer()
                    Button("Choose app…", systemImage: "folder") {
                        AppSelection.choose { ids in if let id = ids.first { shortcut.target = id } }
                    }
                } else if shortcut.action == .layout {
                    TextField("Exact layout name", text: $shortcut.target)
                } else if shortcut.action == .focusWindow || shortcut.action == .swapWindow {
                    Picker("Direction", selection: $shortcut.target) {
                        ForEach(WindowDirection.allCases, id: \.rawValue) { direction in
                            Text(direction.rawValue.capitalized).tag(direction.rawValue)
                        }
                    }
                } else if shortcut.action == .resizeWindow {
                    Picker("Resize", selection: $shortcut.target) {
                        ForEach(["wider", "narrower", "taller", "shorter"], id: \.self) { target in
                            Text(target.capitalized).tag(target)
                        }
                    }
                }
            }
        }
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
    func windowWillClose(_ notification: Notification) { onClose?() }
}
