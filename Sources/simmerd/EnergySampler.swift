import Darwin
import Foundation
import SimmerShared

/// Samples per-process energy every 60 s on its own utility queue and writes energy.json (0644).
/// Cost per run is logged; on the reference M5 Pro one run takes a few milliseconds for ~800 processes.
final class EnergySampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.umarwaseem.simmer.energy", qos: .utility)
    private let accumulator = EnergyAccumulator()
    private var timer: DispatchSourceTimer?
    private let onBattery: () -> Bool
    private let writes: Bool
    static let interval: TimeInterval = 60

    init(writes: Bool, onBattery: @escaping () -> Bool) {
        self.writes = writes
        self.onBattery = onBattery
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        // First sample right away, the second after 10 s so the app has data soon after a restart.
        t.schedule(deadline: .now() + 1, repeating: Self.interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.run() }
        timer = t
        t.resume()
        queue.asyncAfter(deadline: .now() + 11) { [weak self] in self?.run() }
    }

    func stop() { timer?.cancel() }

    /// One sample; returns the report and the time the run took (ms).
    @discardableResult
    func run() -> (EnergyReport?, Double) {
        dispatchPrecondition(condition: .onQueue(queue))
        return Self.sample(accumulator, onBattery: onBattery(), write: writes)
    }

    static func sample(_ acc: EnergyAccumulator, onBattery: Bool, write: Bool) -> (EnergyReport?, Double) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let samples = ProcessList.sampleAll()
        let abs = mach_absolute_time()
        var report = acc.ingest(samples, time: Date(), abs: abs, onBattery: onBattery)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        report?.sampleMillis = (ms * 100).rounded() / 100
        if let r = report {
            log.debug("energy sample: \(samples.count) processes, \(ms, format: .fixed(precision: 2)) ms, total \(r.totalWatts1m, format: .fixed(precision: 2)) W")
            if write { Engine.writeReadable(SimmerJSON.encode(r), to: Simmer.energyPath) }
        }
        return (report, ms)
    }

    /// `simmerd --energy-once`: two samples `seconds` apart, read-only, prints a table (or JSON) and the cost.
    static func printOnce(seconds: Double = 3, json: Bool) -> Never {
        let acc = EnergyAccumulator()
        let onBattery = !BatterySnapshot.read().externalConnected
        let (_, firstMs) = sample(acc, onBattery: onBattery, write: false)
        Thread.sleep(forTimeInterval: seconds)
        let (report, secondMs) = sample(acc, onBattery: onBattery, write: false)
        guard let r = report else { stderrPrint("simmerd: no energy data"); exit(1) }
        if json {
            print(String(decoding: SimmerJSON.encode(r), as: UTF8.self))
        } else {
            print(String(format: "Energy over %.1f s (%d processes visible to uid %d; root sees all)", r.windowSeconds, r.processCount ?? 0, getuid()))
            print("  WATTS   CPU%  WAKE/s  PIDS  NAME")
            for e in r.entries.prefix(25) {
                print(String(format: "%7.3f %6.1f %7.1f %5d  %@%@", e.watts1m, e.cpuPercent1m, e.wakeupsPerSec1m, e.pidCount,
                             e.name, e.isApp ? "" : "  [\(e.id)]"))
            }
            Thread.sleep(forTimeInterval: 1)
            let (_, warmMs) = sample(acc, onBattery: onBattery, write: false)
            print(String(format: "Total %.2f W. Sampler cost: %.2f ms (first run), %.2f ms (second run, fills the name cache), %.2f ms (warm run).",
                         r.totalWatts1m, firstMs, secondMs, warmMs))
        }
        exit(0)
    }
}
