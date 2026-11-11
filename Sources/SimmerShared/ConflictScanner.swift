import Foundation

/// Inputs of the conflict scan, injectable for tests. `.live` reads the real system without subprocesses.
public struct ConflictEnvironment {
    public var fileExists: (String) -> Bool
    /// The `Label` of a launchd plist, nil when unreadable.
    public var plistLabel: (String) -> String?
    /// Executable paths of all running processes.
    public var processPaths: () -> [String]
    /// Contents of /Library/Preferences/com.apple.powerd.charging.plist, nil when missing.
    public var powerdChargingPrefs: () -> Data?
    public var osVersion: OperatingSystemVersion

    public init(fileExists: @escaping (String) -> Bool, plistLabel: @escaping (String) -> String?,
                processPaths: @escaping () -> [String], powerdChargingPrefs: @escaping () -> Data?,
                osVersion: OperatingSystemVersion) {
        self.fileExists = fileExists; self.plistLabel = plistLabel; self.processPaths = processPaths
        self.powerdChargingPrefs = powerdChargingPrefs; self.osVersion = osVersion
    }

    public static var live: ConflictEnvironment {
        ConflictEnvironment(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            plistLabel: { path in
                guard let d = FileManager.default.contents(atPath: path),
                      let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return nil }
                return p["Label"] as? String
            },
            processPaths: { ProcessList.all().map(\.path) },
            powerdChargingPrefs: { FileManager.default.contents(atPath: ConflictScanner.powerdChargingPrefsPath) },
            osVersion: ProcessInfo.processInfo.operatingSystemVersion)
    }
}

extension ConflictScanner {
    /// A privileged helper of another charge limiter, matched only on its exact, well-known files.
    public struct KnownHelper: Sendable {
        public var label: String              // also the Conflict id
        public var product: String
        public var files: [String]            // exact paths under /Library/LaunchDaemons and /Library/PrivilegedHelperTools
        public var note: String?              // what Simmer leaves alone (e.g. a CLI binary elsewhere)
    }

    /// Sources: the vendors' documented install layouts; Battery Toolkit uninstall.sh; batt hack/cc.chlc.batt.plist;
    /// bclm persist.swift; BatFi Info.plist SMPrivilegedExecutables (newer BatFi uses SMAppService, whose
    /// plist lives inside the app; those builds are found as a running app instead).
    public static let knownHelperDetails: [KnownHelper] = [
        KnownHelper(label: "com.apphousekitchen.aldente-pro.helper", product: "Third-party charge limiter",
                    files: ["/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist",
                            "/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"], note: nil),
        KnownHelper(label: "com.apphousekitchen.aldente.helper", product: "Third-party charge limiter",
                    files: ["/Library/LaunchDaemons/com.apphousekitchen.aldente.helper.plist",
                            "/Library/PrivilegedHelperTools/com.apphousekitchen.aldente.helper"], note: nil),
        KnownHelper(label: "me.mhaeuser.batterytoolkitd", product: "Battery Toolkit",
                    files: ["/Library/LaunchDaemons/me.mhaeuser.batterytoolkitd.plist",
                            "/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd"], note: nil),
        KnownHelper(label: "software.micropixels.BatFi.Helper", product: "BatFi",
                    files: ["/Library/LaunchDaemons/software.micropixels.BatFi.Helper.plist",
                            "/Library/PrivilegedHelperTools/software.micropixels.BatFi.Helper"], note: nil),
        KnownHelper(label: "cc.chlc.batt", product: "batt",
                    files: ["/Library/LaunchDaemons/cc.chlc.batt.plist"],
                    note: "The batt command itself (for example /usr/local/bin/batt) stays; remove it with the tool you installed it with."),
        KnownHelper(label: "com.zackelia.bclm", product: "bclm (persist)",
                    files: ["/Library/LaunchDaemons/com.zackelia.bclm.plist"],
                    note: "The bclm command itself (for example /usr/local/bin/bclm) stays. The BCLM value it wrote stays in the SMC until Simmer or bclm writes a new one."),
    ]

    /// Running apps / daemons of other charge limiters, matched on exact path fragments.
    static let knownApps: [(id: String, product: String, markers: [String])] = [
        ("app:commercial-limiter", "Third-party charge limiter app", ["/AlDente.app/Contents/MacOS/AlDente"]),
        ("app:batfi", "BatFi", ["/BatFi.app/Contents/"]),
        ("app:battery-toolkit", "Battery Toolkit", ["/Battery Toolkit.app/Contents/"]),
        ("app:battery", "battery (by actuallymentor)", ["/battery.app/Contents/MacOS/"]),
        ("app:batt", "batt", ["/usr/local/bin/batt", "/opt/homebrew/bin/batt", "/opt/homebrew/Cellar/batt/"]),
    ]

    public static let powerdChargingPrefsPath = "/Library/Preferences/com.apple.powerd.charging.plist"
    public static let nativeLimitConflictID = "native-charge-limit"
    static let allowedDirectories = ["/Library/LaunchDaemons/", "/Library/PrivilegedHelperTools/"]

    public static func scan(environment env: ConflictEnvironment) -> [Conflict] {
        var out: [Conflict] = []

        for h in knownHelperDetails where !h.label.hasPrefix("com.umarwaseem.simmer") {
            let present = h.files.filter { env.fileExists($0) && isRemovablePath($0) }
            guard !present.isEmpty else { continue }
            var detail = "\(h.product) installed a background helper that controls charging. It writes the same charging keys as Simmer, so the two fight over the limit."
            detail += " Removing it deletes: " + present.joined(separator: ", ") + "."
            if let n = h.note { detail += " " + n }
            out.append(Conflict(id: h.label, kind: .leftoverHelper, name: "\(h.product) helper", detail: detail,
                                paths: present, fixableBySimmer: true))
        }

        let paths = env.processPaths()
        for app in knownApps {
            guard paths.contains(where: { p in app.markers.contains { matches(p, marker: $0) } && !p.contains("com.umarwaseem.simmer") }) else { continue }
            out.append(Conflict(id: app.id, kind: .runningApp, name: "\(app.product) is running",
                                detail: "\(app.product) is running and controls charging too. Two charge limiters fight over the same charging keys. Quit \(app.product) and turn off its option to open at login.",
                                paths: [], fixableBySimmer: false))
        }

        if let native = nativeLimitConflict(env) { out.append(native) }
        return out
    }

    /// Marker ending in "/": the path contains it (a bundle or folder). Otherwise the path is the marker or ends
    /// with it, so "/usr/local/bin/batt" does not match "/usr/local/bin/battery".
    static func matches(_ path: String, marker: String) -> Bool {
        marker.hasSuffix("/") ? path.contains(marker) : (path == marker || path.hasSuffix(marker))
    }

    /// A fix may only delete files directly inside the two helper folders, never anything else.
    public static func isRemovablePath(_ path: String) -> Bool {
        let std = (path as NSString).standardizingPath
        guard std == path, !path.contains("/../") else { return false }
        return allowedDirectories.contains { dir in
            path.hasPrefix(dir) && !path.dropFirst(dir.count).contains("/") && path.count > dir.count
        }
    }

    // MARK: native Charge Limit (macOS 26.4+)

    /// macOS 26.4 adds System Settings → Battery → Charging → Charge Limit. PowerUIAgent (root) hands the
    /// setting to powerd as a `ChargeCtrlPolicy` with reason "manualChargeLimit" and `soclimit` = the limit.
    /// powerd keeps its active policies in /Library/Preferences/com.apple.powerd.charging.plist
    /// (world-readable; key "policies" = NSKeyedArchiver data). On the reference Mac the policy reads
    /// soclimit 100 (no limit) while the slider is at 100 %. A value below 100 was not observed directly,
    /// so the detail text also tells the user where to check.
    public struct NativeChargeLimit: Equatable, Sendable {
        public var limit: Int
        public var terminated: Bool
    }

    /// nil = no manual charge-limit policy in the data; throws when the data cannot be decoded.
    public static func nativeChargeLimit(fromPrefs data: Data) throws -> NativeChargeLimit? {
        guard let prefs = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        guard let archive = prefs["policies"] as? Data else { return nil }
        let u = try NSKeyedUnarchiver(forReadingFrom: archive)
        u.setClass(ChargeCtrlPolicyStandIn.self, forClassName: "ChargeCtrlPolicy")
        let root = u.decodeObject(of: [NSArray.self, NSMutableArray.self, ChargeCtrlPolicyStandIn.self, NSUUID.self, NSString.self,
                                       NSNumber.self], forKey: NSKeyedArchiveRootObjectKey)
        u.finishDecoding()
        if let e = u.error { throw e }
        guard let list = root as? [ChargeCtrlPolicyStandIn] else {
            if root == nil { throw CocoaError(.coderReadCorrupt) }
            return nil
        }
        let manual = list.filter { $0.reason == "manualChargeLimit" }
        guard let p = manual.first(where: { !$0.terminated }) ?? manual.first else { return nil }
        return NativeChargeLimit(limit: p.socLimit, terminated: p.terminated)
    }

    static func nativeLimitConflict(_ env: ConflictEnvironment) -> Conflict? {
        let v = env.osVersion
        let has = v.majorVersion > 26 || (v.majorVersion == 26 && v.minorVersion >= 4)
        let howToCheck = "Open System Settings → Battery, click the info button next to Battery Health or open Charging, and check Charge Limit. Set it to 100 % so Simmer controls the limit."
        guard let data = env.powerdChargingPrefs() else { return nil }
        do {
            guard let n = try nativeChargeLimit(fromPrefs: data), !n.terminated, n.limit > 0, n.limit < 100 else { return nil }
            return Conflict(id: nativeLimitConflictID, kind: .nativeChargeLimit, name: "macOS Charge Limit (\(n.limit) %)",
                            detail: "macOS itself stops charging at \(n.limit) %. Simmer cannot charge above that, so Top Up, calibration and limits above \(n.limit) % do not work. " + howToCheck,
                            paths: [], fixableBySimmer: false)
        } catch {
            guard has else { return nil }
            return Conflict(id: nativeLimitConflictID, kind: .nativeChargeLimit, name: "macOS Charge Limit (unknown)",
                            detail: "Simmer could not read the macOS Charge Limit setting. If it is below 100 %, macOS stops charging there no matter what Simmer does. " + howToCheck,
                            paths: [], fixableBySimmer: false)
        }
    }
}

/// Decodes powerd's ChargeCtrlPolicy objects without linking any private framework.
@objc(SimmerChargeCtrlPolicyStandIn)
final class ChargeCtrlPolicyStandIn: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let socLimit: Int
    let reason: String?
    let terminated: Bool
    init?(coder c: NSCoder) {
        socLimit = c.decodeInteger(forKey: "soclimit")
        reason = c.decodeObject(of: NSString.self, forKey: "reason") as String?
        terminated = c.decodeBool(forKey: "terminated")
    }
    init(socLimit: Int, reason: String, terminated: Bool) {
        self.socLimit = socLimit; self.reason = reason; self.terminated = terminated
    }
    func encode(with c: NSCoder) {
        c.encode(socLimit, forKey: "soclimit")
        c.encode(reason as NSString?, forKey: "reason")
        c.encode(terminated, forKey: "terminated")
    }
}
