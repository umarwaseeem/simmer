import Foundation
import SimmerShared

/// Loads and saves config.json and state.json under /Library/Application Support/Simmer.
struct Store {
    let configPath: String
    let statePath: String
    let writable: Bool

    init(writable: Bool, configPath: String = Simmer.configPath, statePath: String = Simmer.statePath) {
        self.writable = writable
        self.configPath = configPath
        self.statePath = statePath
    }

    func loadConfig() -> SimmerConfig {
        var cfg = load(SimmerConfig.self, at: configPath) ?? SimmerConfig()
        cfg.clamp()
        if writable && !FileManager.default.fileExists(atPath: configPath) { save(cfg) }
        return cfg
    }

    func loadState() -> RuntimeState {
        load(RuntimeState.self, at: statePath) ?? RuntimeState()
    }

    @discardableResult
    func save(_ cfg: SimmerConfig) -> Bool { write(SimmerJSON.encode(cfg), to: configPath) }

    @discardableResult
    func save(_ rt: RuntimeState) -> Bool { write(SimmerJSON.encode(rt), to: statePath) }

    private func load<T: Decodable>(_ type: T.Type, at path: String) -> T? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            log.error("cannot read \(path, privacy: .public)")
            return nil
        }
        do {
            return try SimmerJSON.decode(type, data)
        } catch {
            log.error("cannot decode \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            if writable {
                // Keep the bad file for inspection; defaults get written on the next save.
                let bad = path + ".bad"
                try? FileManager.default.removeItem(atPath: bad)
                try? FileManager.default.moveItem(atPath: path, toPath: bad)
            }
            return nil
        }
    }

    private func write(_ data: Data, to path: String) -> Bool {
        guard writable else { return true }
        guard !data.isEmpty else { log.error("refusing to write empty JSON to \(path, privacy: .public)"); return false }
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            log.error("cannot write \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
