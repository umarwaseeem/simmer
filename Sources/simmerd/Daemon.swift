import Darwin
import Foundation
import SimmerShared

/// Wires the engine to the run loop, IOKit notifications, signals and XPC.
final class Daemon {
    let engine: Engine
    let insecureXPC: Bool
    private var listener: NSXPCListener?
    private var listenerDelegate: ListenerDelegate?
    private var powerSourceObserver: PowerSourceObserver?
    private var systemPower: SystemPowerObserver?
    private var signalSources: [DispatchSourceSignal] = []
    private var energySampler: EnergySampler?

    init(mode: RunMode, insecureXPC: Bool) {
        engine = Engine(mode: mode)
        self.insecureXPC = insecureXPC
    }

    /// Never returns.
    func run() -> Never {
        let engine = self.engine
        log.notice("simmerd \(Simmer.helperVersion, privacy: .public) starting (mode=\(String(describing: engine.mode), privacy: .public))")

        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: engine.queue)
            src.setEventHandler {
                log.notice("signal \(sig) received, shutting down")
                engine.shutdown()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }

        if engine.mode == .daemon {
            let l = NSXPCListener(machServiceName: Simmer.machService)
            let d = ListenerDelegate(engine: engine, insecure: insecureXPC)
            l.delegate = d
            l.resume()
            listener = l
            listenerDelegate = d
            if insecureXPC { log.warning("XPC code-signing check DISABLED (--insecure-xpc)") }
        }

        powerSourceObserver = PowerSourceObserver { engine.requestTick("power source") }
        systemPower = SystemPowerObserver { event in
            switch event {
            case .willSleep:
                // Runs on the main thread; the engine queue never waits on main, so sync is safe.
                engine.queue.sync { engine.prepareForSleep() }
            case .hasPoweredOn:
                engine.queue.async { engine.forceReassert() }
                engine.requestTick("wake")
            }
        }

        if engine.mode == .daemon {
            let sampler = EnergySampler(writes: true, onBattery: { !engine.pluggedBox.get() })
            sampler.start()
            energySampler = sampler
        }

        engine.start()   // first timer fire is immediate
        CFRunLoopRun()
        exit(0)
    }

    /// `--status`: one read-only tick, print JSON, exit.
    static func printStatus() -> Never {
        let engine = Engine(mode: .statusOnly)
        engine.powerModes.refreshBlocking()
        let data: Data = engine.queue.sync {
            engine.tick(reason: "status")
            return SimmerJSON.encode(engine.status)
        }
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    }

    /// `--reset`: charging allowed, adapter enabled, LED system.
    static func reset() -> Never {
        guard getuid() == 0 else {
            stderrPrint("simmerd: --reset needs root")
            exit(1)
        }
        let cc: ChargeControl
        do { cc = ChargeControl(smc: try SMC()) } catch {
            stderrPrint("simmerd: cannot open AppleSMC: \(error)")
            exit(1)
        }
        var failed = false
        func step(_ what: String, _ body: () throws -> Void) {
            do { try body(); print("ok: \(what)") } catch { failed = true; stderrPrint("failed: \(what): \(error)") }
        }
        step("adapter enabled") { try cc.setAdapterDisabled(false) }
        step("charging allowed") { try cc.setChargingInhibited(false) }
        if cc.isLimitOnly { step("BCLM 100 (no limit)") { try cc.applyHardwareLimit(100) } }
        if cc.hasLED { step("LED system") { try cc.setLED(.system) } }
        log.notice("simmerd --reset done (failed=\(failed))")
        exit(failed ? 1 : 0)
    }
}
