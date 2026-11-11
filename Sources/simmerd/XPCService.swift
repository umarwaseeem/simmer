import Foundation
import SimmerShared

/// Object exported over XPC. Each call hops to the engine queue.
final class HelperService: NSObject, SimmerHelperProtocol {
    private let engine: Engine
    init(engine: Engine) { self.engine = engine }

    func getVersion(reply: @escaping (String) -> Void) { reply(Simmer.helperVersion) }
    func getStatus(reply: @escaping (Data) -> Void) { engine.statusData(reply: reply) }
    func getConfig(reply: @escaping (Data) -> Void) { engine.configData(reply: reply) }
    func setConfig(_ config: Data, reply: @escaping (String?) -> Void) { engine.setConfig(config, reply: reply) }
    func perform(_ command: Data, reply: @escaping (String?) -> Void) { engine.perform(command, reply: reply) }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    /// The app, the CLI, and the (sandboxed) widget extension, whose interactive buttons call the daemon.
    static let widgetIdentifier = "com.umarwaseem.simmer.widget"
    static let requirement = "identifier \"\(Simmer.appBundleID)\" or identifier \"\(Simmer.ctlIdentifier)\" or identifier \"\(widgetIdentifier)\""

    private let engine: Engine
    private let insecure: Bool
    init(engine: Engine, insecure: Bool) { self.engine = engine; self.insecure = insecure }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        if insecure {
            log.warning("accepting XPC connection from pid \(c.processIdentifier) without a code-signing check (--insecure-xpc)")
        } else {
            // Messages from a client that does not satisfy the requirement are rejected by XPC itself.
            c.setCodeSigningRequirement(Self.requirement)
        }
        c.exportedInterface = NSXPCInterface(with: SimmerHelperProtocol.self)
        c.exportedObject = HelperService(engine: engine)
        c.invalidationHandler = { log.debug("XPC connection invalidated") }
        c.resume()
        return true
    }
}
