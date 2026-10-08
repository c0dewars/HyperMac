import Foundation
import AppKit
import HyperMacCore

final class ConfigStore {
    let url: URL
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var lastRead: Data?
    var onChange: ((Result<Configuration, Error>) -> Void)?

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/hypermac/config.json")
    }
    func load() throws -> Configuration {
        if !FileManager.default.fileExists(atPath: url.path) {
            var initial = Configuration.starter
            let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "com.apple.Safari"
            initial.layouts = Configuration.defaultLayouts(browser: browser)
            try save(initial)
        }
        let data = try Data(contentsOf: url)
        var config = try Configuration.decode(data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let removedFeature = (json?["layouts"] as? [[String: Any]])?.contains { $0["scrolling"] is [String: Any] } == true ||
            (json?["shortcuts"] as? [[String: Any]])?.contains { ["groupPrevious", "groupNext", "ungroupWindow", "centerColumn"].contains($0["action"] as? String ?? "") } == true
        let oldShortcuts = config.shortcuts == Configuration.legacyShortcuts
        if removedFeature || oldShortcuts {
            // Never overwrite a previous migration backup or any custom app rules.
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.before-normal-layouts-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            if oldShortcuts { config.shortcuts = Configuration.omarchyShortcuts }
            try save(config)
        } else { lastRead = data }
        return config
    }
    func save(_ config: Configuration) throws {
        let data = try config.encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastRead = data
    }
    func startWatching() {
        directoryWatcher?.cancel()
        directoryWatcher = watch(url.deletingLastPathComponent()) { [weak self] in
            self?.watchCurrentFile()
            self?.scheduleReload()
        }
        watchCurrentFile()
    }
    private func watchCurrentFile() {
        fileWatcher?.cancel()
        fileWatcher = watch(url) { [weak self] in self?.scheduleReload() }
    }
    private func watch(_ location: URL, changed: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = open(location.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
    private func scheduleReload() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: self.url)
                guard data != self.lastRead else { return }
                self.onChange?(.success(try self.load()))
            } catch { self.onChange?(.failure(error)) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    deinit { pending?.cancel(); directoryWatcher?.cancel(); fileWatcher?.cancel() }
}
