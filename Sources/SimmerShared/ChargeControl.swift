import Foundation

/// Hardware charge-control backends. Verified on an M5 Pro (macOS 26.4) by reading the SMC key list:
/// only CHTE/CHIE exist there. Older firmware and Intel Macs use CH0B/CH0C/CH0I/CH0J or BCLM.
public enum ChargeBackend: String, Codable, Sendable {
    case chte      // Apple Silicon, macOS 15+ firmware: CHTE ui32 (1 = inhibit), CHIE hex_ (0x08 = adapter off)
    case ch0b      // Apple Silicon older firmware / T2 Intel: CH0B+CH0C (0x02 = inhibit), CH0I (0x01 = adapter off)
    case bclm      // Intel without CH0x: BCLM charge level max (no adapter control)
    case none
}

/// ACLC values. 0x00 hands the LED back to macOS.
public enum LEDColor: UInt8, Codable, CaseIterable, Sendable {
    case system = 0x00, off = 0x01, green = 0x03, orange = 0x04, orangeBlinkSlow = 0x05, orangeBlinkFast = 0x06

    public var title: String {
        switch self {
        case .system: return "System default"
        case .off: return "Off"
        case .green: return "Green"
        case .orange: return "Orange"
        case .orangeBlinkSlow: return "Orange, slow blink"
        case .orangeBlinkFast: return "Orange, fast blink"
        }
    }
    /// Short name for the CLI and URL scheme.
    public var cliName: String {
        switch self {
        case .system: return "system"
        case .off: return "off"
        case .green: return "green"
        case .orange: return "orange"
        case .orangeBlinkSlow: return "blink-slow"
        case .orangeBlinkFast: return "blink-fast"
        }
    }
    public init?(cliName: String) {
        guard let c = Self.allCases.first(where: { $0.cliName == cliName.lowercased() }) else { return nil }
        self = c
    }
}

public enum ChargeControlError: Error, CustomStringConvertible, Equatable {
    case unsupported(String)
    public var description: String {
        switch self { case .unsupported(let m): return m }
    }
}

/// Writes the SMC keys for the detected backend. Needs root for writes.
///
/// Backends (chosen by which keys exist, in this order):
/// - `.chte`  Apple silicon, macOS 15+ firmware. CHTE ui32 (1 = stop charging), CHIE (0x08 = adapter off).
///            Integers are little endian. Verified on M5 Pro / macOS 26.4.
/// - `.ch0b`  Apple silicon with older firmware, and Intel Macs of the T2 era. CH0B + CH0C (0x02 = stop charging),
///            CH0I (0x01) or CH0J (0x20) = adapter off. Single-byte keys, so byte order does not matter.
/// - `.bclm`  Older Intel Macs: BCLM (ui8) = maximum charge level that the SMC enforces by itself, also while the
///            Mac sleeps or is shut down. No on-demand stop/start and no adapter control.
/// Intel support is written from public documentation of these keys from open-source tools (bclm, batt, battery CLI) and is
/// covered by tests with a fake SMC; it has not run on Intel hardware.
public final class ChargeControl {
    public let access: SMCAccess
    public let platform: HardwarePlatform
    public let backend: ChargeBackend
    public let hasLED: Bool
    /// Added to the limit before it is written to BCLM (see `bclmValue`). Default −3.
    public var bclmOffset: Int = ChargeControl.defaultBCLMOffset

    /// The real SMC, when this control is backed by hardware.
    public var smc: SMC? { access as? SMC }

    public convenience init(smc: SMC) { self.init(access: smc, platform: .current) }

    public init(access: SMCAccess, platform: HardwarePlatform = .current) {
        self.access = access
        self.platform = platform
        backend = Self.detectBackend(access)
        hasLED = access.exists("ACLC")
    }

    public static func detectBackend(_ a: SMCAccess) -> ChargeBackend {
        if a.exists("CHTE") { return .chte }
        if a.exists("CH0B") { return .ch0b }
        if a.exists("BCLM") { return .bclm }
        return .none
    }

    public var supportsDischarge: Bool {
        switch backend {
        case .chte: return access.exists("CHIE")
        case .ch0b: return access.exists("CH0I") || access.exists("CH0J")
        default: return false
        }
    }

    /// True when the backend only offers a fixed maximum level (BCLM).
    public var isLimitOnly: Bool { backend == .bclm }

    public var capabilities: Capabilities {
        var c = Capabilities()
        c.isIntel = platform.isIntel
        c.led = hasLED
        switch backend {
        case .chte, .ch0b:
            c.chargeInhibit = true
            c.discharge = supportsDischarge
        case .bclm:
            c.chargeInhibit = false
            c.discharge = false
            c.limitOnly = true
            c.limitPersistsWhenOff = true
        case .none:
            c.chargeInhibit = false
            c.discharge = false
            c.led = false
        }
        return c
    }

    /// true = charging inhibited (battery holds, adapter still powers the Mac).
    public func isChargingInhibited() -> Bool {
        switch backend {
        case .chte: return (access.readByte("CHTE") ?? 0) != 0
        case .ch0b: return (access.readByte("CH0B") ?? 0) != 0
        case .bclm, .none: return false
        }
    }

    /// BCLM backends ignore this on purpose: toggling BCLM for sailing or heat protection would wear the
    /// SMC flash and fight the SMC's own limit. Use `applyHardwareLimit` instead.
    public func setChargingInhibited(_ inhibit: Bool) throws {
        switch backend {
        case .chte:
            try access.write("CHTE", inhibit ? [1, 0, 0, 0] : [0, 0, 0, 0])
        case .ch0b:
            try access.write("CH0B", [inhibit ? 0x02 : 0x00])
            if access.exists("CH0C") { try access.write("CH0C", [inhibit ? 0x02 : 0x00]) }
        case .bclm, .none: break
        }
    }

    /// true = adapter disconnected logically, Mac runs from battery while plugged in.
    public func isAdapterDisabled() -> Bool {
        switch backend {
        case .chte: return (access.readByte("CHIE") ?? 0) != 0
        case .ch0b:
            if access.exists("CH0J") { return (access.readByte("CH0J") ?? 0) != 0 }
            return (access.readByte("CH0I") ?? 0) != 0
        default: return false
        }
    }

    /// Enabling the adapter is always safe (no-op without adapter control); disabling throws when unsupported.
    public func setAdapterDisabled(_ disabled: Bool) throws {
        switch backend {
        case .chte: try access.write("CHIE", [disabled ? 0x08 : 0x00])
        case .ch0b:
            if access.exists("CH0J") { try access.write("CH0J", [disabled ? 0x20 : 0x00]) }
            else if access.exists("CH0I") { try access.write("CH0I", [disabled ? 0x01 : 0x00]) }
            else if disabled { throw ChargeControlError.unsupported("This Mac cannot run from the battery while the charger is connected") }
        case .bclm, .none:
            if disabled { throw ChargeControlError.unsupported("This Mac cannot run from the battery while the charger is connected") }
        }
    }

    // MARK: limit-only backend (BCLM)

    /// Offset applied when writing BCLM. On BCLM Macs the level macOS shows tends to settle a few percent
    /// above the BCLM value, because the SMC compares BCLM with the raw gauge level while macOS shows a
    /// level that excludes a small reserve. Writing `limit − 3` lands near the limit the user picked.
    /// The size of the gap differs between models and batteries, so it is configurable
    /// (`SimmerConfig.intelBCLMOffset`, −10...0). Not measured by Simmer on real Intel hardware.
    public static let defaultBCLMOffset = -3

    /// BCLM value for a limit. 100 always means "no limit" (never offset), and the result stays in 20...100.
    public static func bclmValue(forLimit limit: Int, offset: Int) -> Int {
        if limit >= 100 { return 100 }
        return min(100, max(20, limit + offset))
    }

    /// Current BCLM value, nil when the backend has no BCLM key.
    public func readHardwareLimit() -> Int? {
        guard backend == .bclm, let v = access.readNumber("BCLM") else { return nil }
        return Int(v)
    }

    /// Writes BCLM for `limit` (with the offset) only when the hardware value differs. Returns the value
    /// on the hardware afterwards. Throws for backends without BCLM.
    @discardableResult
    public func applyHardwareLimit(_ limit: Int) throws -> Int {
        guard backend == .bclm else { throw ChargeControlError.unsupported("This Mac has no fixed charge-level key (BCLM)") }
        let want = Self.bclmValue(forLimit: limit, offset: bclmOffset)
        if readHardwareLimit() == want { return want }
        let size = (try? access.keyInfo("BCLM").size) ?? 1
        try access.write("BCLM", SMCValue.encodeUInt(UInt64(want), size: size, byteOrder: access.byteOrder))
        return want
    }

    // MARK: LED

    public func setLED(_ c: LEDColor) throws {
        guard hasLED else { return }
        try access.write("ACLC", [c.rawValue])
    }

    public func readLED() -> UInt8? { access.readByte("ACLC") }

    // MARK: sensors (readable without root)
    public var batteryTemperatureC: Double? { access.readNumber("TB0T") }
    public var systemPowerW: Double? { access.readNumber("PSTR") ?? access.readNumber("PDTR") }
    public var adapterInputPowerW: Double? { access.readNumber("PDTR") }
    public var lidClosed: Bool { (access.readByte("MSLD") ?? 0) != 0 }
}
