import Foundation

extension ChargerAnalyzer {
    /// Rated watts from an adapter name such as "96W USB-C Power Adapter" or "Anker 65 W".
    static func ratedWatts(fromName name: String) -> Int? {
        guard let r = name.range(of: #"(\d{2,3})\s?W\b"#, options: .regularExpression) else { return nil }
        let v = Int(name[r].filter(\.isNumber)) ?? 0
        return (5...300).contains(v) ? v : nil
    }

    static func w(_ v: Double) -> String { String(format: "%.0f W", v) }
    static func v1(_ v: Double) -> String { v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v) }

    static func analyze(battery b: BatterySnapshot, systemW: Double?, adapterW: Double?, recentPeakSystemW: Double?) -> ChargerReport {
        var r = ChargerReport()
        r.adapterName = b.adapterName
        r.negotiatedWatts = b.adapterWatts
        r.voltageV = b.adapterVoltageV
        r.currentA = b.adapterCurrentA
        r.peakSystemWatts = recentPeakSystemW
        r.isUSBPD = !b.adapterPDOptions.isEmpty || b.adapterDescription.lowercased().contains("pd")

        let connected = b.adapterWatts > 0 || b.externalConnected
        guard connected else {
            r.rating = .none
            r.headline = "No charger connected"
            if let peak = recentPeakSystemW, peak > 0 {
                r.details.append("Your Mac used up to \(w(peak)) recently. A charger with at least \(w(suggestedWatts(peak))) keeps up with that.")
            }
            return r
        }

        let offered = Double(b.adapterWatts)
        let rated = ratedWatts(fromName: b.adapterName)
        let label = rated.map { "\($0) W charger" } ?? (b.adapterWatts > 0 ? "\(b.adapterWatts) W charger" : "charger")
        let now = systemW.flatMap { $0 > 0 ? $0 : nil }
        let peak = max(recentPeakSystemW ?? 0, now ?? 0)
        let pdMax = b.adapterPDOptions.map(\.watts).max()

        // What the charger offers.
        if b.adapterWatts > 0 {
            var s = "The charger offers \(b.adapterWatts) W"
            if b.adapterVoltageV > 0 && b.adapterCurrentA > 0 { s += " (\(v1(b.adapterVoltageV)) V × \(String(format: "%.1f", b.adapterCurrentA)) A)" }
            r.details.append(s + ".")
        } else {
            r.details.append("macOS does not report how much power the charger offers.")
        }
        if !b.adapterPDOptions.isEmpty {
            let volts = b.adapterPDOptions.map { v1($0.voltageV) + " V" }
            r.details.append("It uses USB Power Delivery and supports \(volts.joined(separator: ", ")).")
        }

        // Cable, port or hub limits.
        var limitNote: String?
        let topVolts = b.adapterPDOptions.map(\.voltageV).max() ?? b.adapterVoltageV
        if b.adapterWatts > 0 && b.adapterWatts <= 15 && (topVolts <= 5.5 || b.adapterVoltageV <= 5.5) {
            limitNote = "The charger runs at 5 V, which gives only \(b.adapterWatts) W. This happens with a USB-A cable, a hub, or a phone charger. Connect a USB-C Power Delivery charger directly to the Mac."
            r.headline = "Your Mac gets only \(b.adapterWatts) W from this charger"
        } else if let rated, offered > 0, (59...61).contains(offered) || (pdMax.map { (55...61).contains($0) } ?? false),
                  Double(rated) >= offered + 15 {
            limitNote = "A \(rated) W charger offers only about 60 W. The cable (or a hub) is rated for 3 A. A 5 A USB-C cable rated for 100 W or more gives the full power."
            r.headline = "Your cable limits charging to 60 W"
        } else if let rated, offered > 0, Double(rated) >= offered * 1.5 + 5 {
            limitNote = "A \(rated) W charger offers only \(b.adapterWatts) W. The cable, a hub or a dock may limit the power. Try another cable directly in the Mac."
            r.headline = "Your Mac gets only \(b.adapterWatts) W from the \(rated) W charger"
        }
        if let limitNote { r.details.append(limitNote) }

        // What the Mac needs.
        if let now { r.details.append("Your Mac uses \(w(now)) now.") }
        if let p = recentPeakSystemW, p > 0 { r.details.append("The highest use in recent history was \(w(p)).") }
        if let a = adapterW, a > 0, offered > 0, a >= offered * 0.95 {
            r.details.append("The charger delivers almost all of its power right now.")
        }

        // Rating.
        guard offered > 0 else {
            r.rating = .good
            if r.headline.isEmpty { r.headline = "Charger connected" }
            return r
        }
        if let now, offered < now {
            r.rating = .insufficient
            if r.headline.isEmpty { r.headline = "Your \(label) can't keep up" }
            r.details.append("The battery drains even while it is connected. Use a charger with at least \(w(suggestedWatts(peak))).")
        } else if peak > 0 && offered < peak {
            r.rating = .limited
            if r.headline.isEmpty { r.headline = "Your \(label) can't keep up under heavy load" }
            r.details.append("During heavy work the Mac takes the extra power from the battery. A charger with at least \(w(suggestedWatts(peak))) avoids that.")
        } else if peak > 0 && offered < peak * 1.25 {
            r.rating = .good
            if r.headline.isEmpty { r.headline = "Your \(label) keeps up" }
            r.details.append("It covers your highest use, but the battery charges slowly while the Mac works hard.")
        } else if peak == 0 && offered < 30 {
            r.rating = .limited
            if r.headline.isEmpty { r.headline = "Your \(label) is slow" }
            r.details.append("It is enough for light work and for charging while the Mac sleeps.")
        } else {
            r.rating = limitNote == nil ? .excellent : .good
            if r.headline.isEmpty { r.headline = "Your \(label) has plenty of power" }
        }
        return r
    }

    /// Rounds a need up to a common charger size (with 20 % headroom).
    static func suggestedWatts(_ peak: Double) -> Double {
        let need = max(20, peak * 1.2)
        return [20, 30, 35, 45, 61, 67, 70, 96, 100, 140].first { $0 >= need } ?? need.rounded(.up)
    }
}
