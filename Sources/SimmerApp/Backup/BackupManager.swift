import Foundation
import SimmerShared

/// App-side preferences that travel with a backup (UserDefaults keys the app owns).
struct AppPrefsBackup: Codable, Equatable {
    var showPercent: Bool?
    var showHardwarePercent: Bool?
    var showTemperature: Bool?
    var showSystemWatts: Bool?
    var notificationsEnabled: Bool?
    var automaticUpdateChecks: Bool?

    static let updatesKey = "SUEnableAutomaticChecks"

    static func current(_ d: UserDefaults = .standard) -> AppPrefsBackup {
        func b(_ k: String) -> Bool? { d.object(forKey: k) == nil ? nil : d.bool(forKey: k) }
        return AppPrefsBackup(showPercent: b("showPercent"), showHardwarePercent: b("showHardwarePercent"),
                              showTemperature: b("showTemperature"), showSystemWatts: b("showSystemWatts"),
                              notificationsEnabled: b("notificationsEnabled"), automaticUpdateChecks: b(updatesKey))
    }

    func apply(_ d: UserDefaults = .standard) {
        func set(_ v: Bool?, _ k: String) { if let v { d.set(v, forKey: k) } }
        set(showPercent, "showPercent"); set(showHardwarePercent, "showHardwarePercent")
        set(showTemperature, "showTemperature"); set(showSystemWatts, "showSystemWatts")
        set(notificationsEnabled, "notificationsEnabled"); set(automaticUpdateChecks, Self.updatesKey)
    }
}

/// The `.simmerbackup` file: JSON with a format tag and version so later versions can migrate it.
struct SimmerBackup: Codable, Equatable {
    static let formatTag = "com.umarwaseem.simmer.backup"
    static let currentVersion = 1
    static let fileExtension = "simmerbackup"

    var format = SimmerBackup.formatTag
    var version = SimmerBackup.currentVersion
    var createdAt = Date()
    var appVersion = ""
    var macModel = ""
    var config: SimmerConfig
    var prefs: AppPrefsBackup?
    var panelLayout: PanelLayout?

    enum ValidationError: LocalizedError {
        case notJSON(String), wrongFormat, tooNew(Int)
        var errorDescription: String? {
            switch self {
            case .notJSON(let m): return "This file is not a Simmer backup (\(m))."
            case .wrongFormat: return "This file is not a Simmer backup."
            case .tooNew(let v): return "This backup was made by a newer Simmer (format \(v)). Update Simmer first."
            }
        }
    }

    func encoded() -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }

    /// Decodes and validates a backup. The config is clamped to valid ranges.
    static func decode(_ data: Data) throws -> SimmerBackup {
        do {
            var b = try SimmerJSON.decode(SimmerBackup.self, data)
            guard b.format == formatTag else { throw ValidationError.wrongFormat }
            guard b.version <= currentVersion else { throw ValidationError.tooNew(b.version) }
            b.config.clamp()
            b.panelLayout?.normalize()
            return b
        } catch let e as ValidationError {
            throw e
        } catch {
            throw ValidationError.notJSON(error.localizedDescription)
        }
    }

    /// A readable list of the settings that differ between `old` and this backup's config.
    func changes(from old: SimmerConfig, prefs oldPrefs: AppPrefsBackup, layout oldLayout: PanelLayout) -> [BackupChange] {
        var out = BackupChange.diff(old: Self.flatten(old), new: Self.flatten(config))
        if let p = prefs {
            out += BackupChange.diff(old: Self.flatten(oldPrefs), new: Self.flatten(p), prefix: "App · ")
        }
        if let l = panelLayout, l != oldLayout {
            out.append(BackupChange(key: "Panel layout", old: "current layout", new: l.visible.map(\.title).joined(separator: ", ")))
        }
        return out
    }

    /// Flattens an Encodable into "key.path" → JSON text pairs.
    static func flatten<T: Encodable>(_ v: T) -> [String: String] {
        guard let obj = try? JSONSerialization.jsonObject(with: SimmerJSON.encode(v)) else { return [:] }
        var out: [String: String] = [:]
        func walk(_ o: Any, _ path: String) {
            if let d = o as? [String: Any] {
                for (k, v) in d { walk(v, path.isEmpty ? k : "\(path).\(k)") }
            } else if let a = o as? [Any], let data = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys]) {
                let raw = String(decoding: data, as: UTF8.self)
                out[path] = a.isEmpty ? "none" : (raw.count <= 40 ? raw : (a.count == 1 ? "1 item" : "\(a.count) items"))
                out[path + "#raw"] = raw
            } else if let n = o as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
                out[path] = n.boolValue ? "on" : "off"
            } else {
                out[path] = "\(o)"
            }
        }
        walk(obj, "")
        return out
    }
}

struct BackupChange: Identifiable, Equatable {
    var key: String
    var old: String
    var new: String
    var id: String { key }

    static func diff(old: [String: String], new: [String: String], prefix: String = "") -> [BackupChange] {
        var out: [BackupChange] = []
        for k in Set(old.keys).union(new.keys).sorted() where !k.hasSuffix("#raw") {
            let o = old[k] ?? "–", n = new[k] ?? "–"
            let changed = o != n || old[k + "#raw"] != new[k + "#raw"]
            if changed && new[k] != nil {
                out.append(BackupChange(key: prefix + readable(k), old: pretty(o), new: pretty(n)))
            }
        }
        return out
    }

    private static func pretty(_ v: String) -> String {
        switch v { case "1": return v; case "true": return "on"; case "false": return "off"; default: return v }
    }

    /// "deskModeAfterHours" → "Desk mode after hours".
    static func readable(_ key: String) -> String {
        key.split(separator: ".").map { part -> String in
            var words: [String] = []
            var cur = ""
            for ch in part {
                if ch.isUppercase, !cur.isEmpty { words.append(cur); cur = "" }
                cur.append(ch)
            }
            if !cur.isEmpty { words.append(cur) }
            let s = words.joined(separator: " ").lowercased()
            return s.prefix(1).uppercased() + s.dropFirst()
        }.joined(separator: " › ")
    }
}

/// Weekly automatic backups in ~/Library/Application Support/Simmer/Backups (keeps the last 8).
enum BackupManager {
    static let keep = 8
    static let interval: TimeInterval = 7 * 86_400
    static let lastAutoKey = "lastAutomaticBackup"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Simmer/Backups", isDirectory: true)
    }

    static func make(config: SimmerConfig, layout: PanelLayout) -> SimmerBackup {
        SimmerBackup(appVersion: AppInfo.version, macModel: MacModel.current.identifier, config: config,
                     prefs: AppPrefsBackup.current(), panelLayout: layout)
    }

    static func defaultFileName(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Simmer-\(f.string(from: date)).\(SimmerBackup.fileExtension)"
    }

    /// Writes a backup when the last one is older than a week. Returns the file on success.
    @discardableResult
    static func autoBackupIfDue(config: SimmerConfig, layout: PanelLayout, now: Date = Date(), defaults: UserDefaults = .standard) -> URL? {
        if let last = defaults.object(forKey: lastAutoKey) as? Date, now.timeIntervalSince(last) < interval { return nil }
        guard let url = write(make(config: config, layout: layout), now: now) else { return nil }
        defaults.set(now, forKey: lastAutoKey)
        prune()
        return url
    }

    @discardableResult
    static func write(_ b: SimmerBackup, now: Date = Date()) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(defaultFileName(now))
            try b.encoded().write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    struct Entry: Identifiable, Equatable {
        var url: URL
        var date: Date
        var size: Int
        var id: URL { url }
    }

    static func list() -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension == SimmerBackup.fileExtension }.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return Entry(url: u, date: v?.contentModificationDate ?? .distantPast, size: v?.fileSize ?? 0)
        }
        .sorted { $0.date > $1.date }
    }

    static func prune() {
        for e in list().dropFirst(keep) { try? FileManager.default.removeItem(at: e.url) }
    }
}
