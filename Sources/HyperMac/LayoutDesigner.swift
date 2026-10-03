import AppKit
import SwiftUI
import HyperMacCore

// Keep view state independent of the SwiftUIMacros plugin in newer SDKs.
@MainActor
private final class LayoutEditorState: ObservableObject {
    @Published var layoutIndex = 0
    @Published var selected: Int?
    @Published var search = ""
    @Published var snap = true
    @Published var preview: ArrangementPreview?
    @Published var showingPreview = false
    @Published var previewLoading = false
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
    @StateObject private var editor = LayoutEditorState()
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
            HStack(alignment: .top, spacing: 12) {
                appSidebar.frame(width: 190)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(validLayout && model.draft.layouts[layoutIndex].adaptive
                        ? "Adaptive mode uses display assignments and open windows. Preview shows the live arrangement; rectangles below are your fixed-mode template."
                        : "Drag an app onto a monitor. Move its rectangle or resize from the bottom-right corner.")
                        .font(.callout).foregroundStyle(.secondary)
                    if validLayout {
                        MonitorCanvas(placements: placements, displays: model.displays, config: model.draft,
                            library: library, selected: $editor.selected, snap: snap,
                            change: { index, frame, screen in update(index, global: frame, screen: screen) },
                            add: { id, screen, point in add(id, on: screen, point: point) })
                            .frame(height: 280)
                        VStack(alignment: .leading, spacing: 12) { inspector }
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView("Create a layout", systemImage: "display.2", description: Text("Choose New layout to start."))
                    }
                }.padding(.bottom, 8)
                }
            }
        }
        .padding(16)
        .task { library.refresh() }
        .sheet(isPresented: $editor.showingPreview) { previewSheet }

        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.displays = ScreenCatalog.current()
        }
        .onChange(of: layoutIndex) { _, _ in selected = nil }
        .onChange(of: model.draft.layouts.count) { _, count in
            layoutIndex = min(layoutIndex, max(0, count - 1)); selected = nil
        }
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
                model.draft.layouts.append(HyperMacCore.Layout(name: name, placements: []))
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
            Label("Layout editor", systemImage: "square.grid.2x2").font(.caption).foregroundStyle(.secondary)
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
                            if let screen = Displays.resolve("external-1", in: model.displays, fallback: true) {
                                add(app.id, on: screen, point: nil)
                            }
                        } label: {
                            HStack {
                                Image(nsImage: library.icon(app.id)).resizable().frame(width: 25, height: 25)
                                Text(app.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "plus").font(.caption).foregroundStyle(.secondary)
                            }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(.plain).draggable(app.id).disabled(!validLayout)
                    }
                }
            }.frame(minHeight: 100, maxHeight: .infinity)
            Divider()
            Text("IN THIS LAYOUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(placements.indices, id: \.self) { i in
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
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if validLayout {
            let layout = inspectedLayout
            VStack(alignment: .leading, spacing: 10) {
                Text("Layout options").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                Toggle("Adaptive · fill space with open layout windows", isOn: layout.adaptive)
                Text(layout.wrappedValue.adaptive
                    ? "Open windows in this layout share each display. Closing or minimizing one redistributes its space; reopening restores it. Other apps remain untouched."
                    : "Fixed mode uses the rectangles below, including empty space for closed windows.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("Window gaps", isOn: layout.applyGap)
                    Toggle("Use primary if display is missing", isOn: layout.fallbackToPrimary)
                }.toggleStyle(.checkbox)
            }.font(.callout)
        }
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
                Button("Remove app", role: .destructive) {
                    model.draft.layouts[layoutIndex].placements.remove(at: selected); self.selected = nil
                }
            }
            HStack {
                Button("Left half") { setFrame(selected, Rect(x: 0, y: 0, width: 0.5, height: 1)) }
                Button("Right half") { setFrame(selected, Rect(x: 0.5, y: 0, width: 0.5, height: 1)) }
                Button("Full screen area") { setFrame(selected, Rect(x: 0, y: 0, width: 1, height: 1)) }
                Spacer()
                Text("\(Int(p.frame.width * 100))% × \(Int(p.frame.height * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            DisclosureGroup("Advanced window matching & coordinates") {
                PlacementEditor(placement: inspectedPlacement(selected)) {
                    model.draft.layouts[layoutIndex].placements.remove(at: selected); self.selected = nil
                }.padding(.top, 6)
            }.font(.callout)
        } else {
            Text("Select an app rectangle to change its color or placement.").foregroundStyle(.secondary)
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
            Text("Current open windows only. Applying also launches configured apps; their windows may appear later. No windows have moved yet.")
                .font(.callout).foregroundStyle(.secondary)
            if editor.previewLoading { ProgressView("Reading windows…") }
            if let preview = editor.preview {
                Text("\(preview.count) windows to arrange").font(.headline)
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
                Button("Save & apply") {
                    guard validLayout else { return }
                    if model.saveAndArrange(model.draft.layouts[layoutIndex].name) { editor.showingPreview = false }
                }.buttonStyle(.borderedProminent).disabled(editor.previewLoading || editor.preview == nil)
            }
        }.padding(24).frame(width: 640)
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

    private func add(_ bundleID: String, on screen: Display, point: CGPoint?) {
        guard validLayout, library.apps.contains(where: { $0.id == bundleID }) else { return }
        var frame = Rect(x: 0, y: 0, width: 0.5, height: 1)
        if let point {
            frame.x = min(0.5, max(0, (point.x - screen.usable.x) / screen.usable.width - 0.25))
            frame.y = 0
        }
        var placement = Placement(bundleID: bundleID, display: selector(for: screen), frame: frame)
        let used = Set(placements.filter { $0.bundleID == bundleID && $0.titleContains.isEmpty }.map(\.windowIndex))
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
                            selected: selected == index, frame: frame, select: { selected = index },
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
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold)).padding(6)
                    .background(color).clipShape(RoundedRectangle(cornerRadius: 4))
                    .highPriorityGesture(DragGesture(coordinateSpace: .global)
                        .onChanged { resize = $0.translation }
                        .onEnded { value in
                            commit(0, 0, Double(value.translation.width), Double(value.translation.height)); resize = .zero
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
