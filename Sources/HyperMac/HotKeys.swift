import Carbon
import Foundation
import HyperMacCore

final class HotKeys {
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var recordingObserver: NSObjectProtocol?
    private var suspended: [Shortcut]?
    private var active: [Shortcut] = []
    var onError: ((String) -> Void)?
    var onAction: ((Shortcut) -> Void)?

    init() {
        recordingObserver = NotificationCenter.default.addObserver(forName: .shortcutRecording, object: nil, queue: .main) { [weak self] note in
            guard let self, let recording = note.object as? Bool else { return }
            if recording {
                guard suspended == nil else { return }
                suspended = active; unregister()
            } else if let saved = suspended {
                suspended = nil
                do { try replace(with: saved) }
                catch { onError?("Could not restore shortcuts after recording: " + error.localizedDescription) }
            }
        }

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x48594D43 else { return OSStatus(eventNotHandledErr) }
            let keys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let index = Int(identifier.id) - 1
            if keys.active.indices.contains(index) { keys.onAction?(keys.active[index]) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func replace(with shortcuts: [Shortcut]) throws {
        let old = active
        unregister()
        do { try register(shortcuts) }
        catch {
            unregister()
            do { try register(old) }
            catch { throw ConfigError("New shortcuts failed and old shortcuts could not be restored. Quit other shortcut tools and reload configuration.") }
            throw error
        }
    }

    private func register(_ shortcuts: [Shortcut]) throws {
        guard handler != nil else { throw ConfigError("Could not install the global shortcut handler.") }
        for (index, shortcut) in shortcuts.enumerated() {
            guard let code = KeyMap.codes[shortcut.key.lowercased()] else { throw ConfigError("Unsupported key.") }
            let flags = shortcut.modifiers.reduce(UInt32(0)) { value, modifier in
                value | ["cmd": UInt32(cmdKey), "ctrl": UInt32(controlKey), "alt": UInt32(optionKey), "shift": UInt32(shiftKey)][modifier, default: 0]
            }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(code, flags,
                EventHotKeyID(signature: 0x48594D43, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                throw ConfigError("Shortcut \(shortcut.modifiers.joined(separator: "+"))+\(shortcut.key) is unavailable (\(status)).")
            }
            registrations.append(reference)
        }
        active = shortcuts
    }

    private func unregister() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll(); active.removeAll()
    }

    deinit { if let recordingObserver { NotificationCenter.default.removeObserver(recordingObserver) }; unregister(); if let handler { RemoveEventHandler(handler) } }
}
