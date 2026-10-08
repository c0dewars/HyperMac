import AppKit
import SwiftUI
import HyperMacCore

@MainActor
final class LayoutEditorState: ObservableObject {
    @Published var layoutIndex = 0
    @Published var editingDisplayID: String?
    @Published var selected: Int?
    @Published var search = ""
    @Published var snap = true
    @Published var preview: ArrangementPreview?
    @Published var previewLayout: HyperMacCore.Layout?
    @Published var showingPreview = false
    @Published var previewLoading = false
    @Published var confirmingDelete = false
}
@MainActor
private final class RectangleDragState: ObservableObject {
    @Published var offset = CGSize.zero
    @Published var resize = CGSize.zero
}

@MainActor
struct LayoutDesigner: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var library = AppLibrary()
    @ObservedObject private var editor: LayoutEditorState
    init(model: SettingsModel) { self.model = model; editor = model.layoutEditor }
    private var index: Int { editor.layoutIndex }
    private var valid: Bool { model.draft.layouts.indices.contains(index) }
    private var layout: HyperMacCore.Layout { valid ? model.draft.layouts[index] : HyperMacCore.Layout(name: "", placements: []) }
    private var screen: Display? { model.displays.first { $0.id == editor.editingDisplayID } ?? model.displays.first }
    private var mode: LayoutScreenMode { screen.map { LayoutScreens.mode(on: $0, layout: layout, displays: model.displays) } ?? .floating }
    private var indices: [Int] {
        guard let screen else { return [] }
        return layout.placements.indices.filter { Displays.resolve(layout.placements[$0].display, in: model.displays, fallback: false)?.id == screen.id }
    }
    private var disconnected: [Int] { layout.placements.indices.filter { Displays.resolve(layout.placements[$0].display, in: model.displays, fallback: false) == nil } }
    private var canEditApps: Bool { mode == .fixed || mode == .adaptive }
    private var displayPlacements: [Placement] {
        guard let screen else { return [] }
        let frames = Tiler.frames(count: indices.count, screen: screen.usable, algorithm: .adaptive, gap: 0)
        return indices.enumerated().map { local, global in
            var rule = layout.placements[global]
            rule.display = "uuid:" + screen.id
            if mode == .adaptive { rule.frame = frames[local].normalized(in: screen.usable) }
            return rule
        }
    }
    private var selection: Binding<Int?> {
        Binding(get: { editor.selected.flatMap { indices.firstIndex(of: $0) } },
                set: { editor.selected = $0.flatMap { indices.indices.contains($0) ? indices[$0] : nil } })
    }
    private var binding: Binding<HyperMacCore.Layout> {
        let saved = layout, i = index
        return Binding(get: { model.draft.layouts.indices.contains(i) ? model.draft.layouts[i] : saved },
                       set: { if model.draft.layouts.indices.contains(i) { model.draft.layouts[i] = $0 } })
    }
    private func ruleBinding(_ i: Int) -> Binding<Placement> {
        let saved = layout.placements[i], li = index
        return Binding(get: {
            guard model.draft.layouts.indices.contains(li), model.draft.layouts[li].placements.indices.contains(i) else { return saved }
            return model.draft.layouts[li].placements[i]
        }, set: {
            guard model.draft.layouts.indices.contains(li), model.draft.layouts[li].placements.indices.contains(i) else { return }
            model.draft.layouts[li].placements[i] = $0
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            if valid {
                screenPicker
                HStack(alignment: .top, spacing: 0) {
                    sidebar.frame(width: 230).padding(.trailing, 20)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let screen {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label(screen.name, systemImage: screen.builtIn ? "laptopcomputer" : "display").font(.title3.weight(.semibold))
                                        Spacer()
                                        Picker("Arrange this display", selection: Binding(get: { mode }, set: { value in
                                            var next = layout
                                            LayoutScreens.setMode(value, on: screen, layout: &next, displays: model.displays)
                                            model.draft.layouts[index] = next
                                        })) {
                                            ForEach(LayoutScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
                                        }.labelsHidden().frame(width: 215).accessibilityLabel("Arrangement for \(screen.name)")
                                    }
                                    Text(modeDescription).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                if canEditApps {
                                    MonitorCanvas(placements: displayPlacements, displays: [screen], config: model.draft,
                                        library: library, selected: selection, snap: editor.snap, readOnly: mode != .fixed,
                                        change: { local, frame, target in
                                            guard indices.indices.contains(local), mode == .fixed else { return }
                                            model.draft.layouts[index].placements[indices[local]].frame = CanvasGeometry.placement(frame, on: target, snap: editor.snap)
                                        }, add: { id, target, point in add(id, on: target, point: point) })
                                        .frame(height: 280)
                                    if indices.isEmpty {
                                        Label("Choose apps from the sidebar to build this display’s layout.", systemImage: "plus.app")
                                            .foregroundStyle(.secondary)
                                    } else if mode == .fixed {
                                        Toggle("Snap to 5% grid", isOn: $editor.snap).toggleStyle(.checkbox)
                                    }
                                    inspector
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: mode == .normal ? "rectangle.split.2x2" : "rectangle.on.rectangle")
                                            .font(.system(size: 42, weight: .light)).foregroundStyle(AppTheme.cyan)
                                        Text(mode == .normal ? "Every eligible window, on this display" : "Your windows stay where you put them").font(.headline)
                                        Text(mode == .normal ? "Opening, closing or minimizing a window adjusts the other tiles. Use Preview & apply to see the current windows." : "This layout won’t move or resize windows on this display.")
                                            .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
                                    }.frame(maxWidth: .infinity, minHeight: 240)
                                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                                }
                                exceptions(on: screen)
                            } else {
                                Text("No display is available. Connect a display to edit its arrangement.").foregroundStyle(.secondary)
                            }
                            if !disconnected.isEmpty { disconnectedRules }
                            Divider()
                            options
                        }.padding(.leading, 20).padding(.bottom, 12)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Create your first layout").font(.title3)
                    Text("Choose how each display arranges your apps.").foregroundStyle(.secondary)
                    Button("New layout", action: newLayout)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(24)
            .task { library.refresh() }
            .onChange(of: editor.layoutIndex) { _, _ in editor.selected = nil }
            .onChange(of: editor.editingDisplayID) { _, _ in editor.selected = nil }
            .sheet(isPresented: $editor.showingPreview) { previewSheet }
            .confirmationDialog("Delete “\(layout.name)”?", isPresented: $editor.confirmingDelete, titleVisibility: .visible) {
                Button("Delete layout", role: .destructive, action: deleteLayout)
            } message: { Text("Shortcuts and monitor profiles using this layout will also be removed.") }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Layout", selection: $editor.layoutIndex) {
                ForEach(model.draft.layouts.indices, id: \.self) { Text(model.draft.layouts[$0].name).tag($0) }
            }.frame(maxWidth: 300)
            Button("New layout", systemImage: "plus", action: newLayout)
            Menu {
                Button("Duplicate layout", action: duplicateLayout)
                Divider()
                Button("Delete layout…", role: .destructive) { editor.confirmingDelete = true }
            } label: { Image(systemName: "ellipsis").frame(width: 20) }.fixedSize().disabled(!valid).help("Layout actions").accessibilityLabel("Layout actions")
            Spacer()
            Button { model.undoAction() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 20, height: 20) }
                .help("Undo arrangement").accessibilityLabel("Undo arrangement").disabled(!model.canUndo())
            Button { model.redoAction() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 20, height: 20) }
                .help("Redo arrangement").accessibilityLabel("Redo arrangement").disabled(!model.canRedo())
            Button("Preview & apply", action: previewLayout).buttonStyle(.borderedProminent).disabled(!valid || model.displays.isEmpty)
        }
    }
    private var screenPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAYS IN THIS LAYOUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.displays) { display in
                        Button {
                            editor.editingDisplayID = display.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: display.builtIn ? "laptopcomputer" : "display").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(display.name).font(.callout.weight(.semibold))
                                    Text(LayoutScreens.mode(on: display, layout: layout, displays: model.displays).title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: screen?.id == display.id ? "checkmark.circle.fill" : "circle").foregroundStyle(screen?.id == display.id ? AppTheme.cyan : .secondary)
                            }.padding(14).frame(minWidth: 220, maxWidth: 290, alignment: .leading)
                                .background(screen?.id == display.id ? AppTheme.cyan.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(screen?.id == display.id ? AppTheme.cyan : .secondary.opacity(0.2)))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(screen?.id == display.id ? .isSelected : [])
                    }
                }.padding(2)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private var modeDescription: String {
        switch mode {
        case .normal: return "Tile all eligible windows already on this display. Other displays keep their own arrangement."
        case .adaptive: return "Choose apps for this display. Their open windows share the space automatically; the diagram is a template."
        case .fixed: return "Drag an app to move it. Select it and drag the corner to resize. Positions scale with this display’s usable area."
        case .floating: return "Leave this display unchanged when the layout is active."
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPS FOR THIS DISPLAY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if canEditApps {
                Button("Choose applications…", systemImage: "plus.app") {
                    guard let screen else { return }
                    AppSelection.choose(multiple: true) { ids in for id in ids { add(id, on: screen, point: nil) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
                TextField("Search app library", text: $editor.search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(library.apps.filter { editor.search.isEmpty || $0.name.localizedCaseInsensitiveContains(editor.search) }) { app in
                            Button { if let screen { add(app.id, on: screen, point: nil) } } label: {
                                HStack(spacing: 9) {
                                    Image(nsImage: library.icon(app.id)).resizable().frame(width: 24, height: 24)
                                    Text(app.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "plus").foregroundStyle(.secondary)
                                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Add \(app.name) to \(screen?.name ?? "this display")")
                                .draggable(app.id)
                        }
                    }
                }.frame(minHeight: 90, maxHeight: 220)
                Divider()
                Text("SELECTED APPS · \(indices.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(indices, id: \.self) { i in
                            let rule = layout.placements[i]
                            HStack(spacing: 4) {
                                Button { editor.selected = i } label: {
                                    HStack(spacing: 8) {
                                        Image(nsImage: library.icon(rule.bundleID)).resizable().frame(width: 24, height: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(library.name(rule.bundleID)).lineLimit(1)
                                            Text("Window \(rule.windowIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(8).frame(maxWidth: .infinity).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { remove(i) } label: { Image(systemName: "minus.circle").frame(width: 24, height: 28) }
                                    .buttonStyle(.borderless).help("Remove \(library.name(rule.bundleID)) from this layout")
                                    .accessibilityLabel("Remove \(library.name(rule.bundleID))")
                            }.background(editor.selected == i ? AppTheme.cyan.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(minHeight: 60)
            } else {
                Text(mode == .normal ? "All eligible apps are included. To choose specific apps, change the display to Tile selected apps." : "Choose a tiling mode above to add apps.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    @ViewBuilder private var inspector: some View {
        if let i = editor.selected, indices.contains(i) {
            let rule = layout.placements[i]
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        AppIdentity(target: rule.bundleID)
                        Spacer()
                        ColorPicker("Border color", selection: Binding(get: { Color(nsColor: AppColor.nsColor(model.draft.appColors[rule.bundleID] ?? model.draft.borderColor)) },
                            set: { model.draft.appColors[rule.bundleID] = AppColor.hex($0) }), supportsOpacity: false)
                        Button("Reset color") { model.draft.appColors[rule.bundleID] = nil }.disabled(model.draft.appColors[rule.bundleID] == nil)
                    }
                    if mode == .fixed {
                        HStack {
                            Button("Left half") { setFrame(i, Rect(x: 0, y: 0, width: 0.5, height: 1)) }
                            Button("Right half") { setFrame(i, Rect(x: 0.5, y: 0, width: 0.5, height: 1)) }
                            Button("Fill display") { setFrame(i, Rect(x: 0, y: 0, width: 1, height: 1)) }
                            Spacer()
                            Text("\(Int(rule.frame.width * 100))% × \(Int(rule.frame.height * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Menu("Move to display") {
                            ForEach(model.displays.filter { $0.id != screen?.id }) { target in
                                Button(target.name) { move(i, to: target) }
                            }
                        }.fixedSize().disabled(model.displays.count < 2)
                        Spacer()
                        Button("Remove app", role: .destructive) { remove(i) }
                    }
                    DisclosureGroup("Window matching and coordinates") {
                        PlacementEditor(placement: ruleBinding(i), displays: model.displays, editCoordinates: mode == .fixed)
                            .padding(.top, 8)
                    }
                }.padding(8)
            }
        } else if !indices.isEmpty {
            Text("Select an app in the diagram or sidebar to edit its settings.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private func exceptions(on screen: Display) -> some View {
        let excluded = LayoutScreens.exclusions(on: screen, layout: layout, displays: model.displays).sorted()
        return DisclosureGroup("Apps excluded on this display\(excluded.isEmpty ? "" : " · \(excluded.count)")") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        AppIdentity(target: id); Spacer()
                        Button("Include app") {
                            model.draft.layouts[index].excludedBundleIDs.removeAll { $0 == id }
                            for key in Array(layout.displayExcludedBundleIDs.keys) where Displays.resolve(key, in: model.displays, fallback: false)?.id == screen.id {
                                model.draft.layouts[index].displayExcludedBundleIDs[key]?.removeAll { $0 == id }
                            }
                        }
                    }
                }
                Button("Choose excluded apps…") {
                    AppSelection.choose(multiple: true) { ids in
                        let key = "uuid:" + screen.id
                        model.draft.layouts[index].displayExcludedBundleIDs[key] = Array(Set((layout.displayExcludedBundleIDs[key] ?? []) + ids)).sorted()
                    }
                }
                Text("Global exclusions in General also apply.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
    }
    private var disconnectedRules: some View {
        GroupBox("Apps assigned to disconnected displays") {
            VStack(spacing: 8) {
                ForEach(disconnected, id: \.self) { i in
                    HStack {
                        AppIdentity(target: layout.placements[i].bundleID)
                        Spacer()
                        Menu("Move to…") { ForEach(model.displays) { target in Button(target.name) { move(i, to: target) } } }.fixedSize()
                        Button("Remove", role: .destructive) { remove(i) }
                    }
                }
                Text("These rules stay saved for when their displays reconnect.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
    private var options: some View {
        DisclosureGroup("Layout options") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: Binding(get: { layout.name }, set: { name in
                    let old = layout.name
                    model.draft.layouts[index].name = name
                    for i in model.draft.shortcuts.indices where model.draft.shortcuts[i].action == .layout && model.draft.shortcuts[i].target == old { model.draft.shortcuts[i].target = name }
                    for i in model.draft.monitorProfiles.indices where model.draft.monitorProfiles[i].layoutName == old { model.draft.monitorProfiles[i].layoutName = name }
                }))
                Toggle("Apply window gaps", isOn: binding.applyGap)
                Picker("New or unassigned displays", selection: binding.defaultScreenMode) {
                    Text("Leave unchanged").tag(LayoutScreenMode.floating)
                    Text("Tile all windows").tag(LayoutScreenMode.normal)
                    if layout.defaultScreenMode == .adaptive { Text("Tile selected apps").tag(LayoutScreenMode.adaptive) }
                    if layout.defaultScreenMode == .fixed { Text("Custom positions").tag(LayoutScreenMode.fixed) }
                }.frame(maxWidth: 450)
                Toggle("Move missing-display rules to the primary display", isOn: binding.fallbackToPrimary)
                Text("Off by default. Keeping this off prevents an unplugged monitor’s apps from being rearranged on another screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

    private func uniqueName(_ base: String) -> String {
        var name = base, n = 2
        while model.draft.layouts.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }
    private func newLayout() {
        var next = LayoutScreens.emptyLayout(name: uniqueName("New layout"))
        if let screen { next.displayModes["uuid:" + screen.id] = .adaptive }
        model.draft.layouts.append(next); editor.layoutIndex = model.draft.layouts.count - 1
    }
    private func duplicateLayout() {
        guard valid else { return }
        var next = layout; next.name = uniqueName(layout.name + " copy")
        model.draft.layouts.append(next); editor.layoutIndex = model.draft.layouts.count - 1
    }
    private func deleteLayout() {
        guard valid else { return }
        let name = layout.name
        model.draft.layouts.remove(at: index)
        model.draft.shortcuts.removeAll { $0.action == .layout && $0.target == name }
        model.draft.monitorProfiles.removeAll { $0.layoutName == name }
        editor.selected = nil; editor.layoutIndex = max(0, min(index, model.draft.layouts.count - 1))
    }
    private func remove(_ i: Int) {
        guard valid, layout.placements.indices.contains(i) else { return }
        model.draft.layouts[index].placements.remove(at: i); editor.selected = nil
    }
    private func setFrame(_ i: Int, _ frame: Rect) { model.draft.layouts[index].placements[i].frame = frame }
    private func move(_ i: Int, to target: Display) {
        guard valid, layout.placements.indices.contains(i) else { return }
        var next = layout
        next.placements[i].display = "uuid:" + target.id
        let others = next.placements.enumerated().filter { $0.offset != i && $0.element.bundleID == next.placements[i].bundleID && $0.element.titleContains == next.placements[i].titleContains && Displays.resolve($0.element.display, in: model.displays, fallback: false)?.id == target.id }
        let used = Set(others.map { $0.element.windowIndex })
        next.placements[i].windowIndex = 0
        while used.contains(next.placements[i].windowIndex) { next.placements[i].windowIndex += 1 }
        if LayoutScreens.mode(on: target, layout: layout, displays: model.displays) == .floating || LayoutScreens.mode(on: target, layout: layout, displays: model.displays) == .normal { next.displayModes["uuid:" + target.id] = .adaptive }
        model.draft.layouts[index] = next
        editor.editingDisplayID = target.id; editor.selected = i
    }
    private func add(_ id: String, on target: Display, point: CGPoint?) {
        guard valid, canEditApps else { return }
        var rule = Placement(bundleID: id, display: "uuid:" + target.id, frame: Rect(x: 0, y: 0, width: 0.5, height: 1))
        if let point, mode == .fixed { rule.frame.x = min(0.5, max(0, (point.x - target.usable.x) / target.usable.width - 0.25)) }
        let used = Set(layout.placements.filter { $0.bundleID == id && $0.titleContains.isEmpty && Displays.resolve($0.display, in: model.displays, fallback: false)?.id == target.id }.map(\.windowIndex))
        while used.contains(rule.windowIndex) { rule.windowIndex += 1 }
        model.draft.layouts[index].placements.append(rule)
        editor.selected = model.draft.layouts[index].placements.count - 1
    }
    private func previewLayout() {
        guard valid, model.save() else { return }
        let requested = layout, gap = model.draft.gap
        editor.previewLayout = requested; editor.preview = nil
        editor.previewLoading = true; editor.showingPreview = true
        Task {
            let preview = await model.previewAction(requested, gap)
            guard editor.previewLayout == requested else { return }
            editor.preview = preview; editor.previewLoading = false
        }
    }
    private func topology(_ screens: [Display]) -> [String] { screens.map { "\($0.id):\($0.usable)" }.sorted() }
    private var previewSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview “\(editor.previewLayout?.name ?? "Layout")”").font(.title2.weight(.semibold))
            Text("Current open windows are shown below. Applying also launches closed apps assigned to selected-app or custom modes.")
                .font(.callout).foregroundStyle(.secondary)
            if editor.previewLoading { ProgressView("Reading windows…").frame(maxWidth: .infinity, minHeight: 240) }
            if let preview = editor.preview, let requested = editor.previewLayout {
                ForEach(preview.displays) { target in
                    HStack {
                        Label(target.name, systemImage: target.builtIn ? "laptopcomputer" : "display")
                        Spacer()
                        Text(LayoutScreens.mode(on: target, layout: requested, displays: preview.displays).title).foregroundStyle(.secondary)
                    }
                }
                MonitorCanvas(placements: preview.placements, displays: preview.displays, config: model.draft,
                    library: library, selected: .constant(nil), snap: false, readOnly: true, change: { _, _, _ in }, add: { _, _, _ in })
                    .frame(height: 300).allowsHitTesting(false)
                Text("\(preview.count) open windows to arrange").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(preview.messages.enumerated()), id: \.offset) { _, message in
                            Label(message, systemImage: "exclamationmark.triangle").font(.caption)
                        }
                        if topology(preview.displays) != topology(model.displays) { Text("Displays changed. Close this preview and preview again.").foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 100)
            }
            Text("Undo arrangement restores surviving windows and pauses tiling.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { editor.showingPreview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply layout") {
                    guard let requested = editor.previewLayout, let preview = editor.preview,
                          model.draft.layouts.contains(requested), topology(preview.displays) == topology(ScreenCatalog.current()) else { return }
                    if model.saveAndArrange(requested.name) { editor.showingPreview = false }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(editor.previewLoading || editor.preview == nil || editor.preview.map { topology($0.displays) != topology(model.displays) } == true)
            }
        }.padding(24).frame(width: 740)
    }
}

@MainActor
private struct MonitorCanvas: View {
    let placements: [Placement]
    let displays: [Display]
    let config: Configuration
    @ObservedObject var library: AppLibrary
    @Binding var selected: Int?
    let snap: Bool
    var readOnly = false
    let change: (Int, Rect, Display) -> Void
    let add: (String, Display, CGPoint?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let map = CanvasMap(displays: displays, size: proxy.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                ForEach(displays) { screen in
                    let frame = map.viewRect(screen.usable)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                        .overlay(alignment: .topLeading) {
                            Text(screen.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).offset(y: -18)
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
                ForEach(placements.indices, id: \.self) { index in
                    if let screen = Displays.resolve(placements[index].display, in: displays, fallback: false) {
                        let global = placements[index].frame.resolved(in: screen.usable, gap: 0)
                        let frame = map.viewRect(global)
                        AppRectangle(name: library.name(placements[index].bundleID), icon: library.icon(placements[index].bundleID),
                            color: Color(nsColor: AppColor.nsColor(config.colorHex(for: placements[index].bundleID))),
                            selected: selected == index, frame: frame, editable: !readOnly, select: { selected = index },
                            commit: { dx, dy, dw, dh in
                                let moved = Rect(x: global.x + dx / map.scale, y: global.y + dy / map.scale,
                                    width: global.width + dw / map.scale, height: global.height + dh / map.scale)
                                let target = (dw != 0 || dh != 0) ? screen : CanvasGeometry.target(for: moved, displays: displays)
                                if let target { change(index, moved, target) }
                            })
                            .zIndex(selected == index ? 2 : 1)
                    }
                }
            }
            .clipped()
            .dropDestination(for: String.self) { items, location in
                guard !readOnly, let id = items.first else { return false }
                let point = map.globalPoint(location)
                guard let screen = displays.first(where: {
                    point.x >= $0.usable.x && point.x <= $0.usable.x + $0.usable.width &&
                    point.y >= $0.usable.y && point.y <= $0.usable.y + $0.usable.height
                }) else { return false }
                add(id, screen, point); return true
            }
        }
    }
}

private struct CanvasMap {
    var origin: CGPoint
    var offset: CGPoint
    var scale: Double
    init(displays: [Display], size: CGSize) {
        let minX = displays.map { $0.usable.x }.min() ?? 0
        let minY = displays.map { $0.usable.y }.min() ?? 0
        let maxX = displays.map { $0.usable.x + $0.usable.width }.max() ?? 1
        let maxY = displays.map { $0.usable.y + $0.usable.height }.max() ?? 1
        let width = max(1, maxX - minX); let height = max(1, maxY - minY)
        scale = max(0.001, min((Double(size.width) - 36) / width, (Double(size.height) - 60) / height))
        origin = CGPoint(x: minX, y: minY)
        offset = CGPoint(x: (Double(size.width) - width * scale) / 2, y: (Double(size.height) - height * scale) / 2)
    }
    func viewRect(_ rect: Rect) -> CGRect {
        CGRect(x: offset.x + (rect.x - origin.x) * scale, y: offset.y + (rect.y - origin.y) * scale,
               width: rect.width * scale, height: rect.height * scale)
    }
    func globalPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale + origin.x, y: (point.y - offset.y) / scale + origin.y)
    }
}

@MainActor
private struct AppRectangle: View {
    let name: String
    let icon: NSImage
    let color: Color
    let selected: Bool
    let frame: CGRect
    var editable = true
    let select: () -> Void
    let commit: (Double, Double, Double, Double) -> Void
    @StateObject private var drag = RectangleDragState()
    private var offset: CGSize {
        get { drag.offset }
        nonmutating set { drag.offset = newValue }
    }
    private var resize: CGSize {
        get { drag.resize }
        nonmutating set { drag.resize = newValue }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(selected ? 0.27 : 0.13))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: selected ? 3 : 1.5))
            VStack(spacing: 3) {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            if selected && editable {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold)).padding(6)
                    .background(color).clipShape(RoundedRectangle(cornerRadius: 4))
                    .highPriorityGesture(DragGesture(coordinateSpace: .global)
                        .onChanged { resize = CGSize(width: $0.translation.width, height: $0.translation.height) }
                        .onEnded { value in
                            commit(0, 0, Double(value.translation.width), Double(value.translation.height)); resize = .zero
                        })
            }
        }
        .frame(width: max(20, frame.width + resize.width), height: max(20, frame.height + resize.height))
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { guard editable else { return }; select(); offset = $0.translation }
            .onEnded { value in guard editable else { return }; commit(Double(value.translation.width), Double(value.translation.height), 0, 0); offset = .zero })
        .position(x: frame.midX + offset.width + resize.width / 2, y: frame.midY + offset.height + resize.height / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name).accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .help(editable ? "\(name): drag to move; select and drag the corner to resize" : "Select \(name)")
    }
}
