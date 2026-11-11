import AppIntents
import Foundation
import SimmerShared

// Shortcuts actions that read battery and power data. Battery facts come straight from the IORegistry
// (no helper needed); charging state, limit and power draw come from the helper or its status.json.

private func batteryOrThrow() throws -> BatterySnapshot {
    let b = BatterySnapshot.read()
    guard b.present, b.designCapacity > 0 || b.percent > 0 else { throw SimmerIntentError.noBattery }
    return b
}

private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

struct GetChargingStateIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Charging State"
    static var description = IntentDescription(
        "Returns what Simmer is doing now, for example \"Charging\", \"Charge Limit Reached\", \"Sailing\" or \"On Battery\".",
        categoryName: "Battery Info", searchKeywords: ["state", "status", "charging"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let s = await SimmerHelperAccess.currentStatus() {
            let title = s.state.title
            return .result(value: title, dialog: "\(title). Battery at \(s.battery.percent)%, limit \(s.targetPercent)%.")
        }
        let b = try batteryOrThrow()
        let title = !b.externalConnected ? "On Battery" : (b.isCharging ? "Charging" : "Not Charging")
        return .result(value: title, dialog: "\(title) at \(b.percent)%. The Simmer helper is not running, so the charge limit is not active.")
    }
}

struct GetBatteryPercentageIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Percentage"
    static var description = IntentDescription(
        "Returns the battery charge in percent, as macOS shows it or as the hardware reports it.",
        categoryName: "Battery Info", searchKeywords: ["percent", "level", "charge"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Source", default: .macOS)
    var source: PercentKindOption

    static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$source) battery percentage")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let b = try batteryOrThrow()
        let v = source == .hardware ? Int(b.hardwarePercent.rounded()) : b.percent
        return .result(value: v, dialog: "The battery is at \(v)%.")
    }
}

struct GetBatteryTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Temperature"
    static var description = IntentDescription(
        "Returns the battery temperature.", categoryName: "Battery Info", searchKeywords: ["temperature", "heat", "hot"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Unit", default: .celsius)
    var unit: TemperatureUnitOption

    static var parameterSummary: some ParameterSummary {
        Summary("Get the battery temperature in \(\.$unit)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let b = try batteryOrThrow()
        let c = SimmerHelperAccess.snapshotStatus()?.smcTemperatureC ?? b.temperatureC
        let v = round1(unit == .fahrenheit ? c * 9 / 5 + 32 : c)
        let text = String(format: "%.1f °%@", v, unit == .fahrenheit ? "F" : "C")
        return .result(value: v, dialog: "The battery is at \(text).")
    }
}

struct GetChargeLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Charge Limit"
    static var description = IntentDescription(
        "Returns the charge limit you set in Simmer, in percent.", categoryName: "Charging", searchKeywords: ["limit", "percentage"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let c = await SimmerHelperAccess.currentConfig() else {
            throw SimmerIntentError.noData("Simmer cannot read its settings. Open Simmer to install or start the helper.")
        }
        let s = SimmerHelperAccess.snapshotStatus()
        if !c.limiterEnabled {
            return .result(value: c.chargeLimit, dialog: "The charge limit is \(c.chargeLimit)%, but the limiter is off.")
        }
        if let s, s.effectiveLimit != c.chargeLimit {
            return .result(value: c.chargeLimit, dialog: "The charge limit is \(c.chargeLimit)%. Right now Simmer uses \(s.effectiveLimit)%.")
        }
        return .result(value: c.chargeLimit, dialog: "The charge limit is \(c.chargeLimit)%.")
    }
}

struct GetBatteryHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Health"
    static var description = IntentDescription(
        "Returns the battery health: the full charge capacity as a percentage of the design capacity.",
        categoryName: "Battery Info", searchKeywords: ["health", "capacity", "condition", "wear"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let b = try batteryOrThrow()
        guard b.designCapacity > 0 else { throw SimmerIntentError.noData("The battery does not report its design capacity.") }
        let v = round1(b.healthPercent)
        let text = String(format: "%.1f%%", v)
        return .result(value: v, dialog: "Battery health is \(text) (\(b.rawMaxCapacity) of \(b.designCapacity) mAh).")
    }
}

struct GetCycleCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Cycle Count"
    static var description = IntentDescription(
        "Returns the battery charge cycle count.", categoryName: "Battery Info", searchKeywords: ["cycles", "count"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let b = try batteryOrThrow()
        return .result(value: b.cycleCount, dialog: "The battery has \(b.cycleCount) cycles.")
    }
}

struct GetPowerDrawIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Power Draw"
    static var description = IntentDescription(
        "Returns power in watts: what the Mac uses, what the power adapter delivers, or what flows into (+) or out of (−) the battery.",
        categoryName: "Battery Info", searchKeywords: ["watts", "power", "consumption", "adapter"])
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Reading", default: .system)
    var reading: PowerReadingOption

    static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$reading) power draw")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        switch reading {
        case .battery:
            let b = try batteryOrThrow()
            let v = round1(b.batteryPowerW)
            let text = String(format: "%.1f W", abs(v))
            let dir = v > 0.05 ? "into" : (v < -0.05 ? "out of" : "through")
            return .result(value: v, dialog: "\(text) flows \(dir) the battery.")
        case .system, .adapter:
            guard let s = await SimmerHelperAccess.currentStatus() else {
                throw SimmerIntentError.noData("Power readings need the Simmer helper. Open Simmer to install or start it.")
            }
            if reading == .adapter {
                guard s.battery.externalConnected else { return .result(value: 0, dialog: "No power adapter is connected.") }
                let v = round1(s.adapterPowerW ?? 0)
                return .result(value: v, dialog: "The power adapter delivers \(String(format: "%.1f W", v)).")
            }
            guard let w = s.systemPowerW else { throw SimmerIntentError.noData("This Mac does not report its power use.") }
            let v = round1(w)
            return .result(value: v, dialog: "The Mac uses \(String(format: "%.1f W", v)).")
        }
    }
}

struct GetChargerReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Charger Report"
    static var description = IntentDescription(
        "Checks the connected charger against what the Mac uses and returns a short verdict, for example \"Your 30 W charger can't keep up\".",
        categoryName: "Battery Info", searchKeywords: ["charger", "adapter", "cable", "watts"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let status = await SimmerHelperAccess.currentStatus()
        let b = status?.battery ?? BatterySnapshot.read()
        guard b.externalConnected else { return .result(value: "No charger connected", dialog: "No charger is connected.") }
        let peak = BatteryHistory.load()?.samples
            .filter { $0.t > Date().addingTimeInterval(-86_400) }
            .compactMap(\.systemW).max()
        let r = ChargerAnalyzer.report(battery: b, systemW: status?.systemPowerW, adapterW: status?.adapterPowerW, recentPeakSystemW: peak)
        var headline = r.headline
        if headline.isEmpty {
            let name = b.adapterName.isEmpty ? "Power adapter" : b.adapterName
            headline = b.adapterWatts > 0 ? "\(name), \(b.adapterWatts) W" : name
        }
        let more = r.details.first.map { " \($0)" } ?? ""
        return .result(value: headline, dialog: "\(headline).\(more)")
    }
}

struct GetTopEnergyAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Top Energy App"
    static var description = IntentDescription(
        "Returns the name of the app that used the most energy in the last minute.",
        categoryName: "Battery Info", searchKeywords: ["energy", "app", "drain", "power hungry"])
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let r = EnergyReport.load(), Date().timeIntervalSince(r.generatedAt) < 15 * 60 else {
            throw SimmerIntentError.noData("Simmer has no recent energy data. The Simmer helper collects it while it runs.")
        }
        guard let top = r.entries.max(by: { $0.watts1m < $1.watts1m }) else {
            throw SimmerIntentError.noData("No app used measurable energy in the last minute.")
        }
        return .result(value: top.name, dialog: "\(top.name) uses the most energy: about \(String(format: "%.1f W", top.watts1m)).")
    }
}
