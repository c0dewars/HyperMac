import AppKit
import SwiftUI
import HyperMacCore

// Keep view state independent of the SwiftUIMacros plugin in newer SDKs.
@MainActor
final class LayoutEditorState: ObservableObject {
    @Published var layoutIndex = 0
    @Published var editingDisplayID: String?
    @Published var selected: Int?
    @Published var search = ""
    @Published var snap = true
    @Published var preview: ArrangementPreview?
    @Published var showingPreview = false
    @Published var previewLoading = false
    var columnResizeStart: Double?
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
    init(model: SettingsModel) {
        self.model = model
        self.editor = model.layoutEditor
    }
    private var layoutIndex: Int {
        get { editor.layoutIndex }
        nonmutating set { editor.layoutIndex = newValue }
    }
    private var selected: Int? {
        get { editor.selected }
        nonmutating set { editor.selected = newValue }
    }
    private var search: String { editor.search }
    private var snap: Bool { editor.snap }

    private var validLayout: Bool { model.draft.layouts.indices.contains(layoutIndex) }
    private var placements: [Placement] { validLayout ? model.draft.layouts[layoutIndex].placements : [] }

    private var editingDisplay: Display? {
        model.displays.first { $0.id == editor.editingDisplayID } ??
            (validLayout ? ScrollingSession.target(layout: model.draft.layouts[layoutIndex], displays: model.displays) : nil) ?? placements.compactMap { Displays.resolve($0.display, in: model.displays, fallback: false) }.first ?? model.displays.first
    }
    private var displayPlacementIndices: [Int] {
        guard validLayout, let screen = editingDisplay else { return [] }
        return placements.indices.filter {
            Displays.resolve(placements[$0].display, in: model.displays, fallback: model.draft.layouts[layoutIndex].fallbackToPrimary)?.id == screen.id
        }
    }

    private var screenMode: LayoutScreenMode {
        guard validLayout, let screen = editingDisplay else { return .floating }
        return LayoutScreens.mode(on: screen, layout: model.draft.layouts[layoutIndex], displays: model.displays)
    }
    private var isHorizontal: Bool { screenMode == .horizontal }
    private var disconnectedIndices: [Int] {
        placements.indices.filter { Displays.resolve(placements[$0].display, in: model.displays, fallback: false) == nil }
    }
    private var screenPlacements: [Placement] {
        displayPlacementIndices.map { index in
            var placement = placements[index]
            placement.display = editingDisplay.map { "uuid:" + $0.id } ?? "primary"
            return placement
        }
    }
    private var screenSelection: Binding<Int?> {
        Binding(get: { displayPlacementIndices.firstIndex { $0 == selected } }, set: { value in
            selected = value.flatMap { displayPlacementIndices.indices.contains($0) ? displayPlacementIndices[$0] : nil }
        })
    }

    // Outgoing SwiftUI views can read their bindings after an array deletion.
    private var inspectedLayout: Binding<HyperMacCore.Layout> {
        let index = layoutIndex
        let count = model.draft.layouts.count
        let fallback = validLayout ? model.draft.layouts[index] : HyperMacCore.Layout(name: "", placements: [])
        return Binding(get: {
            guard model.draft.layouts.count == count, model.draft.layouts.indices.contains(index) else { return fallback }
            return model.draft.layouts[index]
        }, set: { value in
            guard model.draft.layouts.count == count, model.draft.layouts.indices.contains(index) else { return }
            model.draft.layouts[index] = value
        })
    }

    private func inspectedPlacement(_ index: Int) -> Binding<Placement> {
        let layout = inspectedLayout
        let count = layout.wrappedValue.placements.count
        let fallback = layout.wrappedValue.placements[index]
        return Binding(get: {
            let items = layout.wrappedValue.placements
            guard items.count == count, items.indices.contains(index) else { return fallback }
            return items[index]
        }, set: { value in
            var current = layout.wrappedValue
            guard current.placements.count == count, current.placements.indices.contains(index) else { return }
            current.placements[index] = value
            layout.wrappedValue = current
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if validLayout { screenSelector }
            HStack(alignment: .top, spacing: 12) {
                appSidebar.frame(width: 190)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if validLayout, let screen = editingDisplay {
                        screenHeader(screen)
                        if isHorizontal {
                            scrollingCanvas
                            DisclosureGroup("Screen overview · drag to reorder or stack") {
                            MonitorCanvas(placements: scrollingPreviewPlacements, displays: editingDisplay.map { [$0] } ?? [], config: model.draft,
                                library: library, selected: Binding(get: {
                                    scrollingPreviewIndices.firstIndex(where: { $0 == selected })
                                }, set: { value in selected = value.map { scrollingPreviewIndices[$0] } }), snap: snap,
                                horizontalOnly: true,
                                edit: { index, dx, dy, dw, _, screen in
                                    let source = scrollingPreviewIndices[index]
                                    var items = placements
                                    if dw != 0 {
                                        ScrollingTemplate.resize(&items, index: source,
                                            width: items[source].frame.width + dw / screen.usable.width, snap: snap)
                                    } else if dx != 0 || dy != 0, let frame = ScrollingTemplate.frames(items)[source] {
                                        selected = ScrollingTemplate.move(&items, index: source,
                                            x: frame.x + frame.width / 2 + dx / screen.usable.width,
                                            y: frame.y + frame.height / 2 + dy / screen.usable.height)
                                    }
                                    model.draft.layouts[layoutIndex].placements = items
                                },
                                change: { _, _, _ in },
                                add: { id, screen, point in
                                    add(id, on: screen, point: point)
                                })
                                .frame(height: 160)
                            }.font(.callout)
                            if let screen = editingDisplay,
                               !ScrollingSession.supportsContinuousMotion(on: screen, displays: model.displays) {
                                Label("Instant navigation on this display arrangement. For sideways animation, place other displays above or below the scrolling screen in macOS Displays settings.", systemImage: "info.circle")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            HStack {
                                Button("Previous column", systemImage: "arrow.left") { model.navigateScrolling(model.draft.layouts[layoutIndex].name, "left", editingDisplay?.id) }
                                    .help("Focus the previous column · Hyper + H")
                                Button("Next column", systemImage: "arrow.right") { model.navigateScrolling(model.draft.layouts[layoutIndex].name, "right", editingDisplay?.id) }
                                    .help("Focus the next column · Hyper + L")
                            }
                        } else if screenMode == .floating {
                            ContentUnavailableView("Windows stay where they are", systemImage: "rectangle.on.rectangle",
                                description: Text("This layout will leave \(screen.name) unchanged. Choose a tiling mode above to manage its windows. Saved app rules are kept."))
                                .frame(height: 200)
                        } else {
                            MonitorCanvas(placements: screenMode == .normal ? [] : screenPlacements,
                                displays: [screen], config: model.draft, library: library, selected: screenSelection, snap: snap,
                                readOnly: screenMode != .fixed,
                                change: { index, frame, target in
                                    guard displayPlacementIndices.indices.contains(index) else { return }
                                    update(displayPlacementIndices[index], global: frame, screen: target)
                                }, add: { id, target, point in add(id, on: target, point: point) })
                                .frame(height: 240)
                                .overlay {
                                    if screenMode == .normal {
                                        VStack(spacing: 8) {
                                            Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(AppTheme.cyan)
                                            Text("All open windows · automatic sizing").font(.headline)
                                            Text("Preview & apply shows the current arrangement.").font(.caption).foregroundStyle(.secondary)
                                        }.allowsHitTesting(false)
                                    } else if displayPlacementIndices.isEmpty {
                                        Text("Add an app from the library to get started.").foregroundStyle(.secondary).allowsHitTesting(false)
                                    }
                                }
                        }
                        VStack(alignment: .leading, spacing: 12) { inspector }
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView("Create a layout", systemImage: "display.2", description: Text("Choose New layout to start."))
                    }
                }.padding(.bottom, 8)
                }.id("\(layoutIndex):\(editingDisplay?.id ?? "none")")
            }
        }
        .padding(16)
        .task { library.refresh() }
        .sheet(isPresented: $editor.showingPreview) { previewSheet }

        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.displays = ScreenCatalog.current()
        }
        .onChange(of: layoutIndex) { _, _ in selected = nil }
        .onChange(of: editor.editingDisplayID) { _, _ in editor.columnResizeStart = nil }
        .onChange(of: model.draft.layouts.count) { _, count in
            layoutIndex = min(layoutIndex, max(0, count - 1)); selected = nil
        }
    }

    private func modeIcon(_ mode: LayoutScreenMode) -> String {
        switch mode {
        case .horizontal: return "rectangle.split.3x1"
        case .normal: return "square.grid.2x2"
        case .adaptive: return "rectangle.3.group"
        case .fixed: return "rectangle.and.pencil.and.ellipsis"
        case .floating: return "rectangle.on.rectangle"
        }
    }

    private var screenSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("1  Choose a screen").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Each screen has its own mode and apps").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.displays) { screen in
                        let mode = LayoutScreens.mode(on: screen, layout: model.draft.layouts[layoutIndex], displays: model.displays)
                        let active = editingDisplay?.id == screen.id
                        Button {
                            editor.editingDisplayID = screen.id
                            selected = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: screen.builtIn ? "laptopcomputer" : "display")
                                    .font(.system(size: 24)).foregroundStyle(active ? AppTheme.cyan : .secondary)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(screen.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Label(mode.title, systemImage: modeIcon(mode)).font(.caption)
                                        .foregroundStyle(active ? AppTheme.cyan : .secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(active ? AppTheme.cyan : Color.secondary.opacity(0.4))
                            }
                            .padding(12).frame(width: 270, alignment: .leading)
                            .background(active ? AppTheme.cyan.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? AppTheme.cyan : .clear, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Edit " + screen.name)
                            .accessibilityValue(mode.title + (active ? ", selected" : ""))
                    }
                }.padding(2)
            }.scrollIndicators(.hidden)
        }
    }

    private func screenHeader(_ screen: Display) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("2  Arrange " + screen.name).font(.headline)
                Spacer(minLength: 8)
                Text(screen.builtIn ? "Built-in" : "External").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Screen mode", selection: Binding(get: { screenMode }, set: { mode in
                LayoutScreens.setMode(mode, on: screen, layout: &model.draft.layouts[layoutIndex], displays: model.displays)
                selected = nil
            })) {
                ForEach(LayoutScreenMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: modeIcon(mode)).tag(mode)
                }
            }.frame(maxWidth: 410, alignment: .leading)
            Text(screenDescription).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var screenDescription: String {
        switch screenMode {
        case .horizontal: return "Applying moves saved apps to this screen. Drop cards together to stack; select an app for width and order. Hyper + H / L navigates the strip."
        case .normal: return "All eligible windows already on this screen tile automatically, using the algorithm in General. Saved app rules are kept but not used in this mode."
        case .adaptive: return "Saved apps share this screen and adjust when windows open or close. Applying moves matching open windows to this screen. Preview shows the planned arrangement."
        case .fixed: return "Saved apps use the rectangles below. Drag to position them and resize from the corner; empty space is kept for closed apps."
        case .floating: return "Applying this layout will not arrange windows on this screen."
        }
    }

    private var horizontalOptions: some View {
        let layout = inspectedLayout
        return VStack(alignment: .leading, spacing: 12) {
            if let options = layout.wrappedValue.scrolling, let screen = editingDisplay {
                let excluded = Array(Set(options.excludedBundleIDs + (options.displayExcludedBundleIDs["uuid:" + screen.id] ?? []))).sorted()
                if !excluded.isEmpty {
                    HStack {
                        Text("\(excluded.count) apps excluded on this screen").font(.caption).foregroundStyle(.secondary)
                        Menu("Add back…") {
                            ForEach(excluded, id: \.self) { id in
                                Button(library.name(id)) { add(id, on: screen, point: nil) }
                            }
                        }.fixedSize()
                    }
                }
            }
            DisclosureGroup("Horizontal defaults · shared across scrolling screens") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Include all eligible open windows", isOn: Binding(get: { layout.wrappedValue.scrolling?.allWindows ?? true }, set: { layout.wrappedValue.scrolling?.allWindows = $0 }))
                    Text("Off: only saved apps join each strip. On: other open apps join too, using the default width below. Windows remain on their current screens.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Default column width", selection: Binding(get: { layout.wrappedValue.scrolling?.width ?? 0.5 }, set: { layout.wrappedValue.scrolling?.width = $0 })) {
                        Text("⅓").tag(1.0 / 3); Text("½").tag(0.5); Text("⅔").tag(2.0 / 3); Text("Full width").tag(1.0)
                    }
                    Text("Select an app to override its width on this screen.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Neighbor space")
                        Slider(value: Binding(get: { layout.wrappedValue.scrolling?.neighborPreview ?? 120 }, set: { layout.wrappedValue.scrolling?.neighborPreview = $0 }), in: 0...240, step: 10)
                        Text("\(Int(layout.wrappedValue.scrolling?.neighborPreview ?? 120)) pt").monospacedDigit().frame(width: 60)
                    }
                    Text("Reserves space beside the focused column. Shared display edges may hide a neighbor preview. Full width fills the remaining area.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Center focused column", isOn: Binding(get: { layout.wrappedValue.scrolling?.centerFocus ?? false }, set: { layout.wrappedValue.scrolling?.centerFocus = $0 }))
                    Toggle("Hyper + scroll moves between columns", isOn: Binding(get: { layout.wrappedValue.scrolling?.hyperScroll ?? false }, set: { layout.wrappedValue.scrolling?.hyperScroll = $0 }))
                    Toggle("Wrap left/right navigation", isOn: Binding(get: { layout.wrappedValue.scrolling?.wrap ?? false }, set: { layout.wrappedValue.scrolling?.wrap = $0 }))
                    HStack {
                        Text("Transition duration")
                        Slider(value: Binding(get: { layout.wrappedValue.scrolling?.animationDuration ?? 0.22 }, set: { layout.wrappedValue.scrolling?.animationDuration = $0 }), in: 0...0.5, step: 0.01)
                        Text("\(Int((layout.wrappedValue.scrolling?.animationDuration ?? 0.22) * 1000)) ms").monospacedDigit().frame(width: 65)
                    }
                }.padding(.top, 10)
            }.font(.callout)
        }
    }

    private var layoutOptions: some View {
        let layout = inspectedLayout
        return DisclosureGroup("Layout name & shared options") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Layout name", text: Binding(get: { layout.wrappedValue.name }, set: { value in
                    let old = layout.wrappedValue.name
                    for i in model.draft.monitorProfiles.indices where model.draft.monitorProfiles[i].layoutName == old {
                        model.draft.monitorProfiles[i].layoutName = value
                    }
                    layout.wrappedValue.name = value
                    for i in model.draft.shortcuts.indices where model.draft.shortcuts[i].action == .layout && model.draft.shortcuts[i].target == old {
                        model.draft.shortcuts[i].target = value
                    }
                })).textFieldStyle(.roundedBorder)
                Toggle("Window gaps", isOn: layout.applyGap)
                Toggle("Use primary if a saved app’s display is missing", isOn: layout.fallbackToPrimary)
                Text("Screen mode selections are tied to the chosen display. Disconnected app rules remain available in the sidebar.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }.font(.callout)
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
        HStack {
            Picker("Layout", selection: $editor.layoutIndex) {
                ForEach(model.draft.layouts.indices, id: \.self) { i in Text(model.draft.layouts[i].name).tag(i) }
            }.frame(maxWidth: 250)
            Button("New layout", systemImage: "plus") {
                var name = "Layout \(model.draft.layouts.count + 1)"
                while model.draft.layouts.contains(where: { $0.name == name }) { name += " copy" }
                model.draft.layouts.append(LayoutScreens.emptyLayout(name: name))
                layoutIndex = model.draft.layouts.count - 1
            }
            if validLayout {
                Button("Preview & apply") { previewLayout() }
                    .buttonStyle(.borderedProminent)
                Button("Duplicate") {
                    var copy = model.draft.layouts[layoutIndex]
                    copy.name += " copy"
                    while model.draft.layouts.contains(where: { $0.name == copy.name }) { copy.name += " copy" }
                    model.draft.layouts.append(copy); layoutIndex = model.draft.layouts.count - 1
                }
                Button("Delete", role: .destructive) {
                    let index = layoutIndex
                    let name = model.draft.layouts[index].name
                    selected = nil
                    layoutIndex = max(0, index - 1)
                    model.draft.layouts.remove(at: index)
                    model.draft.shortcuts.removeAll { $0.action == .layout && $0.target == name }
                    model.draft.monitorProfiles.removeAll { $0.layoutName == name }
                    selected = nil
                }
            }
            Spacer(minLength: 0)
        }
        HStack {
            Label("Set a mode and apps for each screen", systemImage: "display.2").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Undo arrangement", systemImage: "arrow.uturn.backward") { model.undoAction() }
                .disabled(!model.canUndo())
            Button("Redo", systemImage: "arrow.uturn.forward") { model.redoAction() }.disabled(!model.canRedo())
            Toggle("Snap 5%", isOn: $editor.snap).toggleStyle(.checkbox)
            Button("Refresh", systemImage: "arrow.clockwise") { model.displays = ScreenCatalog.current(); library.refresh() }
        }
        }
    }

    private var appSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APP LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search apps", text: $editor.search).textFieldStyle(.roundedBorder)
            if library.loading { ProgressView().controlSize(.small) }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(library.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                        Button {
                            if let screen = editingDisplay {
                                add(app.id, on: screen, point: nil)
                            }
                        } label: {
                            HStack {
                                Image(nsImage: library.icon(app.id)).resizable().frame(width: 25, height: 25)
                                Text(app.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "plus").font(.caption).foregroundStyle(.secondary)
                            }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(.plain).draggable(app.id).disabled(!validLayout || screenMode == .floating || screenMode == .normal)
                    }
                }
            }.frame(minHeight: 65, idealHeight: 100, maxHeight: 130)
            if screenMode == .normal || screenMode == .floating {
                Text(screenMode == .normal ? "Automatic tiles includes all eligible open windows. Use Tile saved apps to choose specific apps." : "Choose a tiling mode to add apps to this screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !disconnectedIndices.isEmpty {
                DisclosureGroup("Disconnected screens (\(disconnectedIndices.count))") {
                    ForEach(disconnectedIndices, id: \.self) { index in
                        HStack {
                            Text(library.name(placements[index].bundleID)).lineLimit(1)
                            Menu { ForEach(model.displays) { screen in
                                Button("Move to " + screen.name) {
                                    model.draft.layouts[layoutIndex].placements[index].display = "uuid:" + screen.id
                                    editor.editingDisplayID = screen.id
                                    selected = index
                                }
                            } } label: { Image(systemName: "display.trianglebadge.exclamationmark") }
                            Button(role: .destructive) { removePlacement(index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                        }.font(.caption)
                    }
                }.font(.caption)
            }
            Divider()
            Text("APPS ON THIS SCREEN").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(displayPlacementIndices, id: \.self) { i in
                        HStack(spacing: 4) {
                        Button { selected = i } label: {
                            HStack {
                                Circle().fill(Color(nsColor: AppColor.nsColor(model.draft.colorHex(for: placements[i].bundleID))))
                                    .frame(width: 8, height: 8)
                                Text(library.name(placements[i].bundleID)).lineLimit(1)
                                Spacer(minLength: 0)
                                if Displays.resolve(placements[i].display, in: model.displays, fallback: false) == nil {
                                    Image(systemName: "display.trianglebadge.exclamationmark").help("Target display is not connected")
                                }
                            }.padding(6).background(selected == i ? Color.accentColor.opacity(0.15) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { removePlacement(i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).help("Remove \(library.name(placements[i].bundleID)) from this layout")
                        }
                        if Displays.resolve(placements[i].display, in: model.displays, fallback: false) == nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Display disconnected · " + placements[i].display)
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Use primary display") {
                                    model.draft.layouts[layoutIndex].placements[i].display = "primary"
                                }.font(.caption)
                                Menu("Choose another display") {
                                    ForEach(model.displays) { screen in
                                        Button(screen.name) { model.draft.layouts[layoutIndex].placements[i].display = selector(for: screen) }
                                    }
                                }.font(.caption)
                            }.padding(.horizontal, 6).padding(.bottom, 6)
                        }
                    }
                }
            }.frame(minHeight: 80, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var scrollingCanvas: some View {
        if displayPlacementIndices.isEmpty {
            ContentUnavailableView("Automatic columns", systemImage: "rectangle.split.3x1",
                description: Text("Open windows become columns when you apply this layout. Add apps to define widths and vertical groups."))
                .frame(height: 160)
        } else {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(scrollingColumns, id: \.first) { indices in
                    VStack(spacing: 8) {
                        ForEach(indices, id: \.self) { index in
                            Button { selected = index } label: {
                                VStack(spacing: 8) {
                                    Image(nsImage: library.icon(placements[index].bundleID)).resizable().frame(width: 32, height: 32)
                                    Text(library.name(placements[index].bundleID)).lineLimit(2)
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(10)
                                    .background(AppTheme.cyan.opacity(selected == index ? 0.25 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                Button(role: .destructive) { removePlacement(index) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .symbolRenderingMode(.hierarchical)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(library.name(placements[index].bundleID)) from this screen's layout")
                                .accessibilityLabel("Remove \(library.name(placements[index].bundleID)) from layout")
                            }
                            .draggable("hypermac-placement:\(index)")
                            .dropDestination(for: String.self) { items, _ in
                                guard let value = items.first, value.hasPrefix("hypermac-placement:"),
                                      let source = Int(value.dropFirst(19)), placements.indices.contains(source),
                                      placements.indices.contains(index) else { return false }
                                guard source != index else { return false }
                                let group = placements[index].scrollColumn ?? ((placements.compactMap(\.scrollColumn).max() ?? -1) + 1)
                                model.draft.layouts[layoutIndex].placements[index].scrollColumn = group
                                model.draft.layouts[layoutIndex].placements[source].scrollColumn = group
                                setColumnWidth(source, placements[index].frame.width)
                                let moved = model.draft.layouts[layoutIndex].placements.remove(at: source)
                                let insertion = index + (source < index ? 0 : 1)
                                model.draft.layouts[layoutIndex].placements.insert(moved, at: insertion)
                                selected = insertion
                                return true
                            }
                        }
                        HStack {
                            Text("\(Int(placements[indices[0]].frame.width * 100))% width").font(.caption)
                            Spacer()
                            Image(systemName: "arrow.left.and.right")
                                .padding(8).background(AppTheme.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                                .help("Drag left or right to resize this column")
                                .gesture(DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        let index = indices[0]
                                        guard placements.indices.contains(index) else { return }
                                        if editor.columnResizeStart == nil { editor.columnResizeStart = placements[index].frame.width }
                                        let width = min(1, max(0.2, (editor.columnResizeStart ?? 0.5) + value.translation.width / 320))
                                        setColumnWidth(index, snap ? (width * 20).rounded() / 20 : width)
                                    }.onEnded { _ in editor.columnResizeStart = nil })
                        }
                    }.frame(width: max(150, 320 * (placements[indices[0]].frame.width)), height: max(180, CGFloat(indices.count) * 70 + 30))
                }
            }.padding(10)
        }.frame(height: max(205, CGFloat(scrollingColumns.map(\.count).max() ?? 1) * 70 + 55))
        }
    }
    private var scrollingColumns: [[Int]] {
        ScrollingTemplate.columns(placements).map { $0.filter { displayPlacementIndices.contains($0) } }.filter { !$0.isEmpty }
    }

    private var scrollingPreviewIndices: [Int] {
        let frames = ScrollingTemplate.frames(placements)
        return scrollingColumns.flatMap { $0 }.filter { (frames[$0]?.x ?? 1) < 1 }
    }
    private var scrollingPreviewPlacements: [Placement] {
        let frames = ScrollingTemplate.frames(placements)
        return scrollingPreviewIndices.map { index in
            var placement = placements[index]
            placement.display = editingDisplay.map { "uuid:" + $0.id } ?? "primary"
            placement.frame = frames[index]!
            placement.frame.width = min(placement.frame.width, 1 - placement.frame.x)
            return placement
        }
    }

    private func setColumnWidth(_ index: Int, _ width: Double) {
        guard validLayout, placements.indices.contains(index) else { return }
        let group = placements[index].scrollColumn
        for i in placements.indices where i == index || (group != nil && placements[i].scrollColumn == group && placements[i].display == placements[index].display) {
            model.draft.layouts[layoutIndex].placements[i].frame = Rect(x: 0, y: 0, width: width, height: 1)
        }
    }
    private func moveScrollingPlacement(_ index: Int, by delta: Int) {
        guard let localIndex = displayPlacementIndices.firstIndex(of: index), displayPlacementIndices.indices.contains(localIndex + delta) else { return }
        let target = displayPlacementIndices[localIndex + delta]
        model.draft.layouts[layoutIndex].placements.swapAt(index, target); selected = target
    }
    private func groupScrollingPlacement(_ index: Int) {
        guard let position = displayPlacementIndices.firstIndex(of: index), position > 0 else { return }
        let previous = displayPlacementIndices[position - 1]
        let group = placements[previous].scrollColumn ?? ((placements.compactMap(\.scrollColumn).max() ?? -1) + 1)
        model.draft.layouts[layoutIndex].placements[previous].scrollColumn = group
        model.draft.layouts[layoutIndex].placements[index].scrollColumn = group
        model.draft.layouts[layoutIndex].placements[index].frame = placements[previous].frame
    }

    @ViewBuilder private var inspector: some View {
        if let selected, placements.indices.contains(selected) {
            let p = placements[selected]
            HStack {
                Image(nsImage: library.icon(p.bundleID)).resizable().frame(width: 24, height: 24)
                Text(library.name(p.bundleID)).font(.headline).lineLimit(1)
                ColorPicker("App color", selection: Binding(
                    get: { Color(nsColor: AppColor.nsColor(model.draft.colorHex(for: p.bundleID))) },
                    set: { model.draft.appColors[p.bundleID] = AppColor.hex($0) }), supportsOpacity: false)
                    .frame(width: 140)
                Spacer()
                Menu("Move rule to…") {
                    ForEach(model.displays.filter { $0.id != editingDisplay?.id }) { screen in
                        Button(screen.name) { moveRule(selected, to: screen) }
                    }
                }.fixedSize().disabled(model.displays.count < 2)
                Button("Remove app", role: .destructive) {
                    removePlacement(selected)
                }
            }
            if isHorizontal {
                HStack {
                    Button("Move left") { moveScrollingPlacement(selected, by: -1) }.disabled(displayPlacementIndices.first == selected)
                    Button("Move right") { moveScrollingPlacement(selected, by: 1) }.disabled(displayPlacementIndices.last == selected)
                    Button("Group with previous") { groupScrollingPlacement(selected) }.disabled(displayPlacementIndices.first == selected)
                    Menu("Stack with…") {
                        ForEach(displayPlacementIndices.filter { $0 != selected }, id: \.self) { other in
                            Button("\(library.name(placements[other].bundleID)) · window \(placements[other].windowIndex + 1)") {
                                let group = placements[other].scrollColumn ?? ((placements.compactMap(\.scrollColumn).max() ?? -1) + 1)
                                model.draft.layouts[layoutIndex].placements[other].scrollColumn = group
                                model.draft.layouts[layoutIndex].placements[selected].scrollColumn = group
                                setColumnWidth(selected, placements[other].frame.width)
                            }
                        }
                    }.disabled(placements.count < 2)
                    Button("Separate") { model.draft.layouts[layoutIndex].placements[selected].scrollColumn = nil }
                }
                HStack {
                    Text("Column width")
                    Slider(value: Binding(get: { placements.indices.contains(selected) ? placements[selected].frame.width : p.frame.width }, set: { width in
                        setColumnWidth(selected, width)
                    }), in: 0.2...1)
                    Text("\(Int(p.frame.width * 100))%")
                }
                HStack {
                    Button("⅓ width") { setColumnWidth(selected, 1.0 / 3) }
                    Button("½ width") { setColumnWidth(selected, 0.5) }
                    Button("⅔ width") { setColumnWidth(selected, 2.0 / 3) }
                    Button("Full width") { setColumnWidth(selected, 1) }
                }
                Text("Drop a card onto another to stack them, or choose Stack with…. Add an app again for its second window. Move left/right changes order. In live windows, drag the title bar into the lower third of another tile and release. Grouped windows share a width. Edits save automatically and update this layout when it is active.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if screenMode == .fixed {
            HStack {
                Button("Left half") { setFrame(selected, Rect(x: 0, y: 0, width: 0.5, height: 1)) }
                Button("Right half") { setFrame(selected, Rect(x: 0.5, y: 0, width: 0.5, height: 1)) }
                Button("Full screen area") { setFrame(selected, Rect(x: 0, y: 0, width: 1, height: 1)) }
                Spacer()
                Text("\(Int(p.frame.width * 100))% × \(Int(p.frame.height * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            }
            DisclosureGroup("Advanced window matching & coordinates") {
                PlacementEditor(placement: inspectedPlacement(selected)) {
                    removePlacement(selected)
                }.padding(.top, 6)
            }.font(.callout)
        } else {
            Text(isHorizontal ? "Select an app to edit its width, color or column." : "Select an app from the list to edit its rules.")
                .font(.callout).foregroundStyle(.secondary)
        }
        if validLayout {
            if isHorizontal { horizontalOptions }
            Divider()
            layoutOptions
        }
    }

    private func previewLayout() {
        guard validLayout else { return }
        do { try model.draft.validate() }
        catch { model.message = error.localizedDescription; return }
        let layout = model.draft.layouts[layoutIndex]
        let gap = model.draft.gap
        editor.preview = nil; editor.previewLoading = true; editor.showingPreview = true
        Task {
            editor.preview = await model.previewAction(layout, gap)
            editor.previewLoading = false
        }
    }

    private var previewSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview arrangement").font(.title2.bold())
            Text(validLayout && model.draft.layouts[layoutIndex].scrolling?.allWindows == true
                ? "Matching open windows will move to their saved screens. Other windows stay on their current screens; closed apps will not launch. No windows have moved yet."
                : "Current open windows only. Applying also launches configured apps; their windows may appear later. No windows have moved yet.")
                .font(.callout).foregroundStyle(.secondary)
            if validLayout {
                ForEach(model.displays) { screen in
                    HStack {
                        Label(screen.name, systemImage: screen.builtIn ? "laptopcomputer" : "display")
                        Spacer()
                        Text(LayoutScreens.mode(on: screen, layout: model.draft.layouts[layoutIndex], displays: model.displays).title)
                            .foregroundStyle(AppTheme.cyan)
                    }.font(.callout)
                }
            }
            if editor.previewLoading { ProgressView("Reading windows…") }
            if let preview = editor.preview {
                Text(preview.totalCount.map { "\($0) scrolling windows · \(preview.count) windows shown across displays" }
                    ?? "\(preview.count) windows to arrange").font(.headline)
                MonitorCanvas(placements: preview.placements, displays: model.displays, config: model.draft,
                    library: library, selected: .constant(nil), snap: false,
                    change: { _, _, _ in }, add: { _, _, _ in })
                    .frame(height: 260).allowsHitTesting(false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(preview.messages.enumerated()), id: \.offset) { _, message in
                            Label(message, systemImage: "exclamationmark.triangle").font(.caption)
                        }
                    }
                }.frame(maxHeight: 100)
                Text("Undo restores surviving visible windows and pauses tiling. It does not close apps launched by the layout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { editor.showingPreview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply layout") {
                    guard validLayout else { return }
                    if model.saveAndArrange(model.draft.layouts[layoutIndex].name) { editor.showingPreview = false }
                }.buttonStyle(.borderedProminent).disabled(editor.previewLoading || editor.preview == nil)
            }
        }.padding(24).frame(width: 640)
    }

    private func moveRule(_ index: Int, to screen: Display) {
        guard validLayout, placements.indices.contains(index) else { return }
        var rule = placements[index]
        let localRules = placements.enumerated().filter { $0.offset != index &&
            Displays.resolve($0.element.display, in: model.displays, fallback: false)?.id == screen.id }.map(\.element)
        rule.display = localRules.first?.display ?? "uuid:" + screen.id
        rule.scrollColumn = nil
        let used = Set(localRules.filter { $0.bundleID == rule.bundleID && $0.titleContains == rule.titleContains }.map(\.windowIndex))
        rule.windowIndex = 0
        while used.contains(rule.windowIndex) { rule.windowIndex += 1 }
        model.draft.layouts[layoutIndex].placements[index] = rule
        editor.editingDisplayID = screen.id
        selected = index
    }

    private func setFrame(_ index: Int, _ frame: Rect) { model.draft.layouts[layoutIndex].placements[index].frame = frame }

    private func selector(for screen: Display) -> String {
        if screen.builtIn { return "built-in" }
        for role in ["external-1", "external-2"] {
            if Displays.resolve(role, in: model.displays, fallback: false)?.id == screen.id { return role }
        }
        return "uuid:" + screen.id
    }

    private func update(_ index: Int, global: Rect, screen: Display) {
        guard validLayout, placements.indices.contains(index) else { return }
        if Displays.resolve(placements[index].display, in: model.displays, fallback: false)?.id != screen.id {
            model.draft.layouts[layoutIndex].placements[index].display = selector(for: screen)
        }
        setFrame(index, CanvasGeometry.placement(global, on: screen, snap: snap))
    }

    private func removePlacement(_ index: Int) {
        guard validLayout, placements.indices.contains(index) else { return }
        let id = placements[index].bundleID
        let screen = Displays.resolve(placements[index].display, in: model.displays, fallback: model.draft.layouts[layoutIndex].fallbackToPrimary)
        model.draft.layouts[layoutIndex].placements.remove(at: index)
        if let screen, model.draft.layouts[layoutIndex].scrolling != nil,
           !placements.contains(where: { $0.bundleID == id && Displays.resolve($0.display, in: model.displays, fallback: true)?.id == screen.id }) {
            let key = "uuid:" + screen.id
            var excluded = model.draft.layouts[layoutIndex].scrolling?.displayExcludedBundleIDs[key] ?? []
            if !excluded.contains(id) { excluded.append(id) }
            model.draft.layouts[layoutIndex].scrolling?.displayExcludedBundleIDs[key] = excluded
        }
        selected = nil
    }

    private func add(_ bundleID: String, on screen: Display, point: CGPoint?) {
        guard validLayout, screenMode != .normal, screenMode != .floating,
              library.apps.contains(where: { $0.id == bundleID }) else { return }
        model.draft.layouts[layoutIndex].scrolling?.excludedBundleIDs.removeAll { $0 == bundleID }
        model.draft.layouts[layoutIndex].scrolling?.displayExcludedBundleIDs["uuid:" + screen.id]?.removeAll { $0 == bundleID }
        var frame = Rect(x: 0, y: 0, width: 0.5, height: 1)
        if isHorizontal, let scrolling = model.draft.layouts[layoutIndex].scrolling { frame.width = scrolling.width }
        if let point, screenMode == .fixed {
            frame.x = min(0.5, max(0, (point.x - screen.usable.x) / screen.usable.width - 0.25))
            frame.y = 0
        }
        let screenSelector = displayPlacementIndices.first.map { placements[$0].display } ?? ("uuid:" + screen.id)
        var placement = Placement(bundleID: bundleID, display: screenSelector, frame: frame)
        let used = Set(placements.filter { $0.bundleID == bundleID && $0.titleContains.isEmpty && (model.draft.layouts[layoutIndex].scrolling == nil || Displays.resolve($0.display, in: model.displays, fallback: true)?.id == screen.id) }.map(\.windowIndex))
        while used.contains(placement.windowIndex) { placement.windowIndex += 1 }
        model.draft.layouts[layoutIndex].placements.append(placement)
        selected = model.draft.layouts[layoutIndex].placements.count - 1
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
    var horizontalOnly = false
    var edit: ((Int, Double, Double, Double, Double, Display) -> Void)? = nil
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
                            selected: selected == index, frame: frame, horizontalOnly: horizontalOnly, select: { selected = index },
                            commit: { dx, dy, dw, dh in
                                if let edit {
                                    edit(index, dx / map.scale, dy / map.scale, dw / map.scale, dh / map.scale, screen)
                                    return
                                }
                                let moved = Rect(x: global.x + dx / map.scale, y: global.y + dy / map.scale,
                                    width: global.width + dw / map.scale, height: global.height + dh / map.scale)
                                let target = (dw != 0 || dh != 0) ? screen : CanvasGeometry.target(for: moved, displays: displays)
                                if let target { change(index, moved, target) }
                            })
                            .zIndex(selected == index ? 2 : 1)
                            .allowsHitTesting(!readOnly)
                    }
                }
            }
            .clipped()
            .dropDestination(for: String.self) { items, location in
                guard let id = items.first else { return false }
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
    var horizontalOnly = false
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
            if selected {
                Image(systemName: horizontalOnly ? "arrow.left.and.right" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold)).padding(6)
                    .background(color).clipShape(RoundedRectangle(cornerRadius: 4))
                    .highPriorityGesture(DragGesture(coordinateSpace: .global)
                        .onChanged { resize = CGSize(width: $0.translation.width, height: horizontalOnly ? 0 : $0.translation.height) }
                        .onEnded { value in
                            commit(0, 0, Double(value.translation.width), horizontalOnly ? 0 : Double(value.translation.height)); resize = .zero
                        })
            }
        }
        .frame(width: max(20, frame.width + resize.width), height: max(20, frame.height + resize.height))
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { select(); offset = $0.translation }
            .onEnded { value in commit(Double(value.translation.width), Double(value.translation.height), 0, 0); offset = .zero })
        .position(x: frame.midX + offset.width + resize.width / 2, y: frame.midY + offset.height + resize.height / 2)
        .help("\(name): drag to move; select and drag the corner to resize")
    }
}
