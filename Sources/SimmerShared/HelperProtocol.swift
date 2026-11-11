import Foundation

/// XPC interface exported by simmerd. Payloads are JSON (SimmerJSON) to keep the ObjC surface small.
@objc public protocol SimmerHelperProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    /// JSON SimmerStatus
    func getStatus(reply: @escaping (Data) -> Void)
    /// JSON SimmerConfig
    func getConfig(reply: @escaping (Data) -> Void)
    /// JSON SimmerConfig; reply(errorMessage or nil)
    func setConfig(_ config: Data, reply: @escaping (String?) -> Void)
    /// JSON SimmerCommand; reply(errorMessage or nil)
    func perform(_ command: Data, reply: @escaping (String?) -> Void)
}

/// Client used by the app and the CLI.
public final class HelperClient: @unchecked Sendable {
    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "simmer.helperclient")
    public init() {}

    private func proxy(_ onError: @escaping (String) -> Void) -> SimmerHelperProtocol? {
        queue.sync {
            if connection == nil {
                let c = NSXPCConnection(machServiceName: Simmer.machService, options: .privileged)
                c.remoteObjectInterface = NSXPCInterface(with: SimmerHelperProtocol.self)
                c.invalidationHandler = { [weak self] in self?.queue.async { self?.connection = nil } }
                c.interruptionHandler = { [weak self] in self?.queue.async { self?.connection = nil } }
                c.resume()
                connection = c
            }
            return connection?.remoteObjectProxyWithErrorHandler { onError($0.localizedDescription) } as? SimmerHelperProtocol
        }
    }

    public func version(_ done: @escaping (Result<String, Error>) -> Void) {
        let once = Once(done)
        proxy { once(.failure(HelperError.connection($0))) }?.getVersion { once(.success($0)) }
    }

    public func status(_ done: @escaping (Result<SimmerStatus, Error>) -> Void) {
        let once = Once(done)
        proxy { once(.failure(HelperError.connection($0))) }?.getStatus { data in
            once(Result { try SimmerJSON.decode(SimmerStatus.self, data) })
        }
    }

    public func config(_ done: @escaping (Result<SimmerConfig, Error>) -> Void) {
        let once = Once(done)
        proxy { once(.failure(HelperError.connection($0))) }?.getConfig { data in
            once(Result { try SimmerJSON.decode(SimmerConfig.self, data) })
        }
    }

    public func setConfig(_ cfg: SimmerConfig, _ done: @escaping (Result<Void, Error>) -> Void) {
        let once = Once(done)
        proxy { once(.failure(HelperError.connection($0))) }?.setConfig(SimmerJSON.encode(cfg)) { err in
            once(err.map { .failure(HelperError.remote($0)) } ?? .success(()))
        }
    }

    public func perform(_ cmd: SimmerCommand, _ done: @escaping (Result<Void, Error>) -> Void) {
        let once = Once(done)
        proxy { once(.failure(HelperError.connection($0))) }?.perform(SimmerJSON.encode(cmd)) { err in
            once(err.map { .failure(HelperError.remote($0)) } ?? .success(()))
        }
    }

    public func invalidate() { queue.sync { connection?.invalidate(); connection = nil } }
}

public enum HelperError: LocalizedError {
    case connection(String), remote(String), timeout
    public var errorDescription: String? {
        switch self {
        case .connection(let m): return "Helper not reachable: \(m)"
        case .remote(let m): return m
        case .timeout: return "Helper did not respond"
        }
    }
}

/// Ensures an XPC completion fires once, even if both the reply and the error handler run.
private final class Once<T>: @unchecked Sendable {
    private var fn: ((T) -> Void)?
    private let lock = NSLock()
    init(_ fn: @escaping (T) -> Void) { self.fn = fn }
    func callAsFunction(_ v: T) { lock.lock(); let f = fn; fn = nil; lock.unlock(); f?(v) }
}
