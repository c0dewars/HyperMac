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
                message = "Captured. Review and apply the arrangement in Layouts."
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

    @ObservedObject var ui: SettingsUIState
    private var section: String {
        get { ui.section }
        nonmutating set { ui.section = newValue }
    }
    private var showDetails: Bool {
        get { ui.showDetails }
        nonmutating set { ui.showDetails = newValue }
    }
    var body: some View {
        VStack(spacing: 0) {
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
                        .buttonStyle(.bordered)
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
        .buttonStyle(.bordered)
        .controlSize(.large)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.displays = ScreenCatalog.current()
        }
        .sheet(isPresented: $ui.showReport) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Troubleshooting report").font(.title2.bold())
                Text("Window identities, placement results and timing. Document titles are omitted.")
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
                Toggle("Resize neighboring tiles with the mouse", isOn: $model.draft.mouseResize)
                Text("In Tile all windows with Dynamic splits, drag a window edge or corner. Neighbors adjust when you release the mouse.").font(.caption).foregroundStyle(.secondary)
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
                Text("A saved layout controls each display separately. Tile now returns all displays to automatic tiling.")
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
                Text("App colors set in Layouts override the default border color. Effects disappear when paused or an ignored app is focused. Blur respects Reduce Transparency.")
                    .foregroundStyle(.secondary)
            }
            Section("Capture your arrangement") {
                TextField("Layout name", text: $model.captureName)
                Button("Capture visible windows") { model.capture() }
                Text("Capture remembers each display and window’s position. You can edit the arrangement and window matching in Layouts.")
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
            Section("About HyperMac") {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HyperMac").font(.headline)
                        Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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

    private func matchesShortcut(_ shortcut: Shortcut) -> Bool {
        let category = shortcut.action == .launch ? "Apps" : shortcut.action == .layout ? "Layouts" : "Windows"
        return (ui.shortcutCategory == "All" || ui.shortcutCategory == category) &&
            (model.shortcutSearch.isEmpty || "\(shortcut.friendlyTitle) \(shortcut.target) \(shortcut.key)".localizedCaseInsensitiveContains(model.shortcutSearch))
    }

    private func shortcutBinding(_ index: Int) -> Binding<Shortcut> {
        let saved = model.draft.shortcuts[index]
        return Binding(get: { model.draft.shortcuts.indices.contains(index) ? model.draft.shortcuts[index] : saved },
                       set: { if model.draft.shortcuts.indices.contains(index) { model.draft.shortcuts[index] = $0 } })
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
                        model.draft.shortcuts.append(Shortcut(key: "", modifiers: ["ctrl", "alt", "cmd", "shift"], action: .focusWindow, target: "left"))
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
                TextField("Search actions, apps or keys", text: $model.shortcutSearch).textFieldStyle(.plain).accessibilityLabel("Search shortcuts")
                Picker("Filter", selection: $ui.shortcutCategory) {
                    ForEach(["All", "Windows", "Apps", "Layouts"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
            }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !model.draft.shortcuts.contains(where: matchesShortcut) {
                        VStack(spacing: 8) {
                            Image(systemName: "keyboard").font(.largeTitle)
                            Text("No matching shortcuts").font(.headline)
                            Text("Try another search or add a shortcut.")
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40)
                    }
                    ForEach(model.draft.shortcuts.indices, id: \.self) { index in
                        let shortcut = model.draft.shortcuts[index]
                        let category = shortcut.action == .launch ? "Apps" : shortcut.action == .layout ? "Layouts" : "Windows"
                        if (ui.shortcutCategory == "All" || ui.shortcutCategory == category) &&
                            (model.shortcutSearch.isEmpty || "\(shortcut.friendlyTitle) \(shortcut.target) \(shortcut.key)".localizedCaseInsensitiveContains(model.shortcutSearch)) {
                            ShortcutEditor(shortcut: shortcutBinding(index), layouts: model.draft.layouts.map(\.name)) {
                                if model.draft.shortcuts.indices.contains(index) { model.draft.shortcuts.remove(at: index) }
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

    private func profileBinding(_ index: Int) -> Binding<MonitorProfile> {
        let saved = model.draft.monitorProfiles[index]
        return Binding(get: { model.draft.monitorProfiles.indices.contains(index) ? model.draft.monitorProfiles[index] : saved },
                       set: { if model.draft.monitorProfiles.indices.contains(index) { model.draft.monitorProfiles[index] = $0 } })
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
                                    Toggle("Enabled", isOn: profileBinding(i).enabled)
                                    TextField("Profile name", text: profileBinding(i).name)
                                    Picker("Layout", selection: profileBinding(i).layoutName) {
                                        ForEach(model.draft.layouts, id: \.name) { Text($0.name).tag($0.name) }
                                    }
                                    Button("Remove") { if model.draft.monitorProfiles.indices.contains(i) { model.draft.monitorProfiles.remove(at: i) } }
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
                        }.disabled(model.draft.layouts.isEmpty || model.displays.isEmpty || model.draft.monitorProfiles.contains { Set($0.displayIDs) == Set(model.displays.map(\.id)) })
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
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "slider.horizontal.3").frame(width: 24, height: 24) }
                    .buttonStyle(.bordered).help("Edit action").accessibilityLabel("Edit action")
                Button(role: .destructive, action: remove) { Image(systemName: "trash").frame(width: 24, height: 24) }
                    .buttonStyle(.bordered).help("Remove shortcut").accessibilityLabel("Remove shortcut")
            }
            if expanded {
                Divider()
                HStack {
                    Picker("Action", selection: Binding(get: { shortcut.action }, set: { shortcut.selectAction($0) })) {
                        Text("Open app").tag(Action.launch)
                        Text("Apply layout").tag(Action.layout)
                        Text("Pause / resume tiling").tag(Action.toggleTiling)
                        Text("Arrange windows").tag(Action.retile)
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
    let displays: [Display]
    var editCoordinates = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Display", selection: $placement.display) {
                ForEach(displays) { Text($0.name + " · this display").tag("uuid:" + $0.id) }
                Text("Primary display · follows macOS").tag("primary")
                Text("Built-in display").tag("built-in")
                ForEach(1...max(1, displays.filter { !$0.builtIn }.count), id: \.self) { Text("External display \($0) · by position").tag("external-\($0)") }
                if Displays.resolve(placement.display, in: displays, fallback: false) == nil,
                   !["primary", "built-in", "external-1"].contains(placement.display) {
                    Text("Disconnected display").tag(placement.display)
                }
            }
            TextField("Window title contains", text: $placement.titleContains, prompt: Text("Optional"))
            Stepper("Window \(placement.windowIndex + 1) on this display", value: $placement.windowIndex, in: 0...99)
            if editCoordinates {
                HStack {
                    percent("X", $placement.frame.x)
                    percent("Y", $placement.frame.y)
                    percent("Width", $placement.frame.width)
                    percent("Height", $placement.frame.height)
                }
            }
        }.textFieldStyle(.roundedBorder)
    }
    private func percent(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField("%", value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }), format: .number)
                .frame(width: 55).accessibilityLabel(label + " percent")
            Text("%")
        }
    }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?
    let model: SettingsModel
    private let ui = SettingsUIState()
    private let sections = [("General", "slider.horizontal.3"), ("Shortcuts", "keyboard"),
                            ("Layouts", "rectangle.split.2x2"), ("Displays", "display.2")]
    init(model: SettingsModel) {
        self.model = model
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
            width: min(1360, available.width - 48), height: min(940, available.height - 110)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "HyperMac Settings"
        window.contentMinSize = NSSize(width: min(980, available.width - 48), height: min(680, available.height - 110))
        window.toolbarStyle = .preference
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model, ui: ui))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "HyperMacSettings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("General")
        window.toolbar = toolbar
        window.delegate = self
        // Hosting the SwiftUI form changes AppKit's initial fitting size. Apply
        // our larger default after attaching it, then honor the user's saved size.
        window.setContentSize(NSSize(width: min(1360, available.width - 48), height: min(940, available.height - 110)))
        window.center()
        window.setFrameAutosaveName("HyperMacNormalSettingsV2")
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        sections.map { NSToolbarItem.Identifier($0.0) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = sections.first(where: { $0.0 == id.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = section.0
        item.image = NSImage(systemSymbolName: section.1, accessibilityDescription: section.0)
        item.target = self; item.action = #selector(selectSection(_:))
        return item
    }
    @objc private func selectSection(_ sender: NSToolbarItem) {
        ui.section = sender.itemIdentifier.rawValue
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.save() { return true }
        let alert = NSAlert()
        alert.messageText = "Some changes couldn’t be saved"
        alert.informativeText = model.message
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
