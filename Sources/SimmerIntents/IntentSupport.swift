import AppIntents
import Foundation
import WidgetKit
import SimmerShared

// Shared by the app target and the widget extension (see project.yml).
// The widget target defines SIMMER_WIDGET: there the intents run inside the sandboxed widget
// process (interactive widget buttons), so they are hidden from Shortcuts to avoid duplicates.

/// Errors that App Intents show to the user in Shortcuts.
enum SimmerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case helperNotInstalled
    case helperNotResponding
    case helperUnreachable(String)
    case rejected(String)
    case noBattery
    case noData(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .helperNotInstalled:
            return "The Simmer helper is not installed. Open Simmer and install it first."
        case .helperNotResponding:
            return "The Simmer helper did not respond. Open Simmer to check that the helper is running."
        case .helperUnreachable(let m):
            return "Simmer cannot reach its helper (\(m)). Open Simmer to install or start it."
        case .rejected(let m):
            return "\(m)"
        case .noBattery:
            return "This Mac has no battery."
        case .noData(let m):
            return "\(m)"
        }
    }

    init(_ error: Error) {
        if let e = error as? SimmerIntentError { self = e; return }
        switch error as? HelperError {
        case .timeout?: self = .helperNotResponding
        case .remote(let m)?: self = .rejected(m)
        case .connection(let m)?:
            #if SIMMER_WIDGET
            self = .helperUnreachable(m)          // the sandbox cannot see /Library/PrivilegedHelperTools
            #else
            self = FileManager.default.fileExists(atPath: Simmer.helperInstallPath) ? .helperUnreachable(m) : .helperNotInstalled
            #endif
        case nil: self = .helperUnreachable(error.localizedDescription)
        }
    }
}

/// Fires once, from either the XPC reply or the timeout.
private final class IntentOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Async wrappers around `HelperClient` with a timeout. Each call uses its own XPC connection.
enum SimmerHelperAccess {
    static let timeout: TimeInterval = 6

    static func perform(_ cmd: SimmerCommand, timeout: TimeInterval = timeout) async throws {
        try await call(timeout: timeout) { client, done in client.perform(cmd, done) }
    }

    static func status(timeout: TimeInterval = timeout) async throws -> SimmerStatus {
        try await call(timeout: timeout) { client, done in client.status(done) }
    }

    static func config(timeout: TimeInterval = timeout) async throws -> SimmerConfig {
        try await call(timeout: timeout) { client, done in client.config(done) }
    }

    private static func call<T>(timeout: TimeInterval,
                                _ op: @escaping (HelperClient, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let client = HelperClient()
        defer { client.invalidate() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = IntentOnce()
            let finish: (Result<T, Error>) -> Void = { r in
                guard once.claim() else { return }
                cont.resume(with: r.mapError { SimmerIntentError($0) })
            }
            op(client, finish)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.failure(HelperError.timeout)) }
        }
    }

    // MARK: reads without a command

    /// Live status from the helper, else the status.json snapshot when it is recent. nil when the helper is not running.
    static func currentStatus() async -> SimmerStatus? {
        if let s = try? await status(timeout: 3) { return s }
        return snapshotStatus()
    }

    /// status.json written by simmerd (world-readable). nil when missing or older than 10 minutes.
    static func snapshotStatus(now: Date = Date()) -> SimmerStatus? {
        guard let d = FileManager.default.contents(atPath: Simmer.statusSnapshotPath),
              let s = try? SimmerJSON.decode(SimmerStatus.self, d),
              now.timeIntervalSince(s.updatedAt) < 10 * 60 else { return nil }
        return s
    }

    /// Live config from the helper, else config.json (world-readable).
    static func currentConfig() async -> SimmerConfig? {
        if let c = try? await config(timeout: 3) { return c }
        guard let d = FileManager.default.contents(atPath: Simmer.configPath) else { return nil }
        return try? SimmerJSON.decode(SimmerConfig.self, d)
    }

    /// Asks WidgetKit to redraw the Simmer widgets. simmerd rewrites status.json before it replies to a
    /// command, so the widgets read the new state.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
