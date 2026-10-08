import AppKit
import SwiftUI
import HyperMacCore

extension Notification.Name {
    static let shortcutRecording = Notification.Name("HyperMacShortcutRecording")
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.displayTitle = shortcut.key.isEmpty ? "Click to record" : shortcut.modifiers.map {
            ["ctrl": "⌃", "alt": "⌥", "cmd": "⌘", "shift": "⇧"][$0] ?? $0
        }.joined(separator: " ") + "  " + (["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↵", "space": "Space"] [shortcut.key] ?? shortcut.key.uppercased())
        view.refreshTitle()
        view.record = { key, modifiers in shortcut.key = key; shortcut.modifiers = modifiers }
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish() }
}

final class RecorderButton: NSButton {
    var record: ((String, [String]) -> Void)?
    private var recording = false
    var displayTitle = "Click to record"
    func refreshTitle() { if !recording { title = displayTitle } }
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        title = "Record shortcut"; bezelStyle = .rounded
        target = self; action = #selector(begin)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() {
        if recording { finish(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        recording = true; title = "Press keys · Esc cancels"
        NotificationCenter.default.post(name: .shortcutRecording, object: true)
    }
    func finish() {
        guard recording else { return }
        recording = false; refreshTitle()
        NotificationCenter.default.post(name: .shortcutRecording, object: false)
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = [("ctrl", NSEvent.ModifierFlags.control), ("alt", .option), ("cmd", .command), ("shift", .shift)]
            .filter { flags.contains($0.1) }.map { $0.0 }
        guard !modifiers.isEmpty, let key = KeyMap.codes.keys.sorted().first(where: { KeyMap.codes[$0] == UInt32(event.keyCode) }) else {
            title = "Use modifiers + a key"; return
        }
        record?(key, modifiers); finish()
    }
}
