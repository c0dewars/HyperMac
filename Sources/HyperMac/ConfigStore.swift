import Foundation
import HyperMacCore

final class ConfigStore {
    let url: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var lastRead: Data?
    var onChange: ((Result<Configuration, Error>) -> Void)?

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/hypermac/config.json")
    }

    func load() throws -> Configuration {
        if !FileManager.default.fileExists(atPath: url.path) { try save(.starter) }
        let data = try Data(contentsOf: url)
        var config = try Configuration.decode(data)
        if config.shortcuts == Configuration.legacyShortcuts {
            // Only migrate untouched defaults; keep a recoverable copy of the original.
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.before-omarchy-shortcuts.json")
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
            config.shortcuts = Configuration.omarchyShortcuts
            try save(config)
            return config
        }
        lastRead = data
        return config
    }

    func save(_ config: Configuration) throws {
        let data = try config.encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastRead = data
    }

    func startWatching() {
        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                do {
                    let data = try Data(contentsOf: self.url)
                    guard data != self.lastRead else { return }
                    let config = try Configuration.decode(data)
                    self.lastRead = data
                    self.onChange?(.success(config))
                } catch { self.onChange?(.failure(error)) }
            }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        watcher = source
        source.resume()
    }

    deinit { pending?.cancel(); watcher?.cancel() }
}
