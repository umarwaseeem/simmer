import Foundation
import SimmerShared

// Fixed, privacy-safe demo data (no serial numbers, no real app list), shaped like an M5 Pro
// MacBook Pro holding at an 80% limit on a 96 W charger.

enum HarnessFlags { nonisolated(unsafe) static var frozen = true }

func mockBattery(percent: Int = 80) -> BatterySnapshot {
    var b = BatterySnapshot()
    b.present = true
    b.percent = percent
    b.hardwarePercent = Double(percent) - 0.6
    b.externalConnected = true
    b.isCharging = false
    b.voltageV = 12.34
    b.amperageA = 0
    b.temperatureC = 30.4
    b.cycleCount = 111
    b.designCapacity = 6249
    b.rawMaxCapacity = 5750
    b.rawCurrentCapacity = 4369
    b.nominalCapacity = 5902
    b.adapterWatts = 94
    b.adapterName = "96W USB-C Power Adapter"
    b.adapterVoltageV = 20
    b.adapterCurrentA = 4.69
    b.serial = ""
    return b
}

func mockStatus() -> SimmerStatus {
    var s = SimmerStatus()
    s.helperVersion = Simmer.helperVersion
    s.backend = .chte
    s.supportsDischarge = true
    s.supportsLED = true
    s.state = .limitReached
    s.targetPercent = 80
    s.effectiveLimit = 80
    s.chargingInhibited = true
    s.battery = mockBattery()
    s.smcTemperatureC = 31
    s.systemPowerW = 18.6
    s.adapterPowerW = 19.1
    s.powerModes.highPowerCharger = true
    s.runtime.lastCalibration = Date().addingTimeInterval(-21 * 86_400)
    s.updatedAt = Date()
    return s
}

func mockEnergy() -> EnergyReport {
    var r = EnergyReport()
    func app(_ id: String, _ name: String, _ path: String, _ w: Double, _ cpu: Double, _ wake: Double) -> EnergyEntry {
        EnergyEntry(id: id, name: name, bundlePath: path, isApp: true, pidCount: 3, watts1m: w, watts1h: w * 0.8,
                    cpuPercent1m: cpu, wakeupsPerSec1m: wake, energySinceUnplugWh: nil)
    }
    r.entries = [
        ("node", 6.8, 92.0, 140.0), ("ffmpeg", 3.1, 38.0, 210.0), ("python3", 1.4, 12.0, 60.0),
        ("photo-export", 0.7, 5.0, 22.0), ("rsync", 0.4, 3.0, 9.0), ("backup-agent", 0.3, 2.0, 14.0),
    ].map { n, w, cpu, wake in
        EnergyEntry(id: "/usr/local/bin/" + n, name: n, bundlePath: nil, isApp: false, pidCount: 1, watts1m: w, watts1h: w * 0.8,
                    cpuPercent1m: cpu, wakeupsPerSec1m: wake, energySinceUnplugWh: nil)
    }
    r.totalWatts1m = r.entries.reduce(0) { $0 + $1.watts1m } + 1.1
    r.processCount = 612
    return r
}

private func dayRecord(_ day: String, health: Double, raw: Int, design: Int, cycles: Int, avg: Double, max: Double,
                       minPct: Int, maxPct: Int) -> DailyBatteryRecord {
    let d: [String: Any] = ["day": day, "healthPercent": health, "rawMaxCapacity": raw, "designCapacity": design,
                            "cycleCount": cycles, "avgTempC": avg, "maxTempC": max, "minPct": minPct, "maxPct": maxPct,
                            "samples": 200]
    return try! JSONDecoder().decode(DailyBatteryRecord.self, from: JSONSerialization.data(withJSONObject: d))
}

/// 30 days of daily records and 14 days of 5-minute samples: a workday plug-in pattern held at 80%.
func mockHistory(now: Date = Date()) -> BatteryHistory {
    var h = BatteryHistory()
    let cal = Calendar.current
    let design = 6249
    var seed: UInt64 = 42
    func noise(_ a: Double) -> Double {   // deterministic, so re-renders look the same
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * a
    }
    let days = 30
    for i in stride(from: days - 1, through: 0, by: -1) {
        let d = cal.date(byAdding: .day, value: -i, to: now)!
        let f = Double(days - 1 - i) / Double(days - 1)
        let health = 92.6 - 0.7 * f + noise(0.15)
        h.daily.append(dayRecord(DailyBatteryRecord.dayFormatter.string(from: d), health: (health * 10).rounded() / 10,
                                 raw: Int(Double(design) * health / 100), design: design,
                                 cycles: 97 + Int((f * 14).rounded()), avg: 29.5 + noise(1.2), max: 34 + noise(1.5),
                                 minPct: 38 + Int(noise(6)), maxPct: 80))
    }
    var t = now.addingTimeInterval(-14 * 86_400)
    var pct = 72.0
    while t <= now {
        let hour = cal.component(.hour, from: t)
        let weekday = cal.component(.weekday, from: t)
        if hour >= 1 && hour < 7 { t = t.addingTimeInterval(300); continue }   // asleep
        let plugged = (hour >= 9 && hour < 18 && weekday != 1) || (weekday == 1 && hour >= 15)
        var w: Double
        var charging = false
        if plugged {
            if pct < 80 { w = 24 + noise(4); pct = min(80, pct + 1.5); charging = true } else { w = noise(0.2) }
        } else {
            w = -(8 + noise(3)); pct = max(22, pct - 0.6)
        }
        let temp = 28.5 + (charging ? 5 : 0) + (plugged ? 1 : 0) + noise(0.2)
        h.samples.append(HistorySample(t: t, pct: Int(pct.rounded()), hwPct: pct - 0.5, tempC: (temp * 10).rounded() / 10,
                                       batteryW: (w * 10).rounded() / 10, systemW: 11 + noise(3), plugged: plugged,
                                       charging: charging))
        t = t.addingTimeInterval(300)
    }
    return h
}
