import Foundation
import IOKit

// Layout must match the kernel's SMCParamStruct (80 bytes).
struct SMCKeyDataVers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct SMCPLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct SMCKeyInfoData {
    var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
    var pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0  // C pads this struct to 12 bytes
}
typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCKeyDataVers()
    var pLimit = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

public enum SMCError: Error, CustomStringConvertible {
    case openFailed(kern_return_t), keyNotFound(String), callFailed(String, kern_return_t, UInt8), badSize(String, Int, Int)
    public var description: String {
        switch self {
        case .openFailed(let r): return "AppleSMC open failed (\(String(format: "0x%08x", r)))"
        case .keyNotFound(let k): return "SMC key \(k) not found"
        case .callFailed(let k, let r, let s): return "SMC call for \(k) failed (kr=\(String(format: "0x%08x", r)), smc=\(s))"
        case .badSize(let k, let want, let got): return "SMC key \(k) expects \(want) bytes, got \(got)"
        }
    }
}

public struct SMCKeyInfo: Equatable, Sendable {
    public let size: Int; public let type: String
    public init(size: Int, type: String) { self.size = size; self.type = type }
}

/// Minimal SMC surface used by the charge-control backends. `SMC` is the real AppleSMC client;
/// tests use a fake so backend logic (Apple silicon, Intel T2-era, Intel BCLM) runs without hardware.
public protocol SMCAccess: AnyObject {
    func keyInfo(_ key: String) throws -> SMCKeyInfo
    func read(_ key: String) throws -> [UInt8]
    func write(_ key: String, _ bytes: [UInt8]) throws
    /// Byte order of multi-byte integer types (ui16/si16/ui32/si32) on this machine.
    var byteOrder: SMCByteOrder { get }
}

extension SMCAccess {
    public func exists(_ key: String) -> Bool { (try? keyInfo(key)) != nil }
    /// Reads a numeric key and converts it with its SMC data type. nil when missing or the type is unknown.
    public func readNumber(_ key: String) -> Double? {
        guard let info = try? keyInfo(key), let b = try? read(key) else { return nil }
        return SMCValue.decode(b, type: info.type, byteOrder: byteOrder)
    }
    /// First byte of a key (flags such as CHTE, CH0B, BCLM, ACLC).
    public func readByte(_ key: String) -> UInt8? { (try? read(key))?.first }
}

/// Integer byte order of the SMC. Apple silicon: little endian. Intel: big endian.
/// Fixed-point types (spXY, fpXY) are big endian on both; `flt ` is little endian on both
/// (Intel tools such as smcFanControl memcpy it into a native x86 float).
public enum SMCByteOrder: String, Sendable { case little, big }

/// What kind of Mac the code runs on. The SMC keys stay the ground truth for which backend works.
public struct HardwarePlatform: Equatable, Sendable {
    public var isAppleSilicon: Bool
    public var isIntel: Bool { !isAppleSilicon }
    public init(isAppleSilicon: Bool) { self.isAppleSilicon = isAppleSilicon }

    /// `#if arch(x86_64)` alone is not enough: an x86_64 binary may run under Rosetta on Apple silicon.
    /// `hw.optional.arm64` is 1 on Apple silicon for both native and translated processes.
    public static let current: HardwarePlatform = {
        #if arch(arm64)
        return HardwarePlatform(isAppleSilicon: true)
        #else
        return HardwarePlatform(isAppleSilicon: sysctlInt("hw.optional.arm64") == 1 || sysctlInt("sysctl.proc_translated") == 1)
        #endif
    }()

    public var smcByteOrder: SMCByteOrder { isAppleSilicon ? .little : .big }

    static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }
}

/// Pure SMC value decoding, unit tested for both byte orders.
public enum SMCValue {
    public static func decode(_ b: [UInt8], type: String, byteOrder: SMCByteOrder) -> Double? {
        func uint(_ n: Int) -> UInt64? {
            guard b.count >= n else { return nil }
            let bytes = Array(b.prefix(n))
            let ordered = byteOrder == .little ? bytes.reversed() : bytes
            return ordered.reduce(0) { $0 << 8 | UInt64($1) }
        }
        func bigEndian16() -> UInt16? { b.count >= 2 ? UInt16(b[0]) << 8 | UInt16(b[1]) : nil }
        switch type {
        case "flt ":
            guard b.count == 4 else { return nil }
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8 ", "flag": return b.isEmpty ? nil : Double(b[0])
        case "hex_": return b.count == 1 ? Double(b[0]) : nil
        case "si8 ": return b.isEmpty ? nil : Double(Int8(bitPattern: b[0]))
        case "ui16": return uint(2).map { Double($0) }
        case "si16": return uint(2).map { Double(Int16(bitPattern: UInt16($0))) }
        case "ui32": return uint(4).map { Double($0) }
        case "si32": return uint(4).map { Double(Int32(bitPattern: UInt32($0))) }
        default:
            // Fixed point "spXY" (signed) / "fpXY" (unsigned): Y (hex) fraction bits, always big endian, 2 bytes.
            let chars = Array(type)
            guard chars.count == 4, let frac = Int(String(chars[3]), radix: 16), let raw = bigEndian16() else { return nil }
            if type.hasPrefix("sp") { return Double(Int16(bitPattern: raw)) / Double(1 << frac) }
            if type.hasPrefix("fp") { return Double(raw) / Double(1 << frac) }
            return nil
        }
    }

    /// Encodes an unsigned integer for a key of `size` bytes in the given byte order.
    public static func encodeUInt(_ v: UInt64, size: Int, byteOrder: SMCByteOrder) -> [UInt8] {
        let le = (0..<size).map { UInt8((v >> (8 * UInt64($0))) & 0xff) }
        return byteOrder == .little ? le : le.reversed()
    }
}

/// Thin AppleSMC client. Reads work as any user; writes need root.
public final class SMC: SMCAccess {
    private var conn: io_connect_t = 0
    private let lock = NSLock()
    private var infoCache: [UInt32: SMCKeyInfo] = [:]
    public let byteOrder: SMCByteOrder

    private enum Selector: UInt8 { case read = 5, write = 6, keyFromIndex = 8, keyInfo = 9 }

    public init(platform: HardwarePlatform = .current) throws {
        precondition(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct layout mismatch")
        byteOrder = platform.smcByteOrder
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        defer { IOObjectRelease(svc) }
        let r = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.openFailed(r) }
    }
    deinit { IOServiceClose(conn) }

    public static func fourCC(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }
    public static func string(_ v: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "????"
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var out = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCParamStruct>.stride, &out, &size)
        if r != kIOReturnSuccess || out.result != 0 {
            if out.result == 0x84 { throw SMCError.keyNotFound(key) }
            throw SMCError.callFailed(key, r, out.result)
        }
        return out
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        return try keyInfoLocked(key)
    }

    private func keyInfoLocked(_ key: String) throws -> SMCKeyInfo {
        let k = Self.fourCC(key)
        if let c = infoCache[k] { return c }
        var p = SMCParamStruct(); p.key = k; p.data8 = Selector.keyInfo.rawValue
        let o = try call(&p, key: key)
        let info = SMCKeyInfo(size: Int(o.keyInfo.dataSize), type: Self.string(o.keyInfo.dataType))
        infoCache[k] = info
        return info
    }

    public func exists(_ key: String) -> Bool { (try? keyInfo(key)) != nil }

    public func read(_ key: String) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        var p = SMCParamStruct(); p.key = Self.fourCC(key); p.keyInfo.dataSize = UInt32(info.size); p.data8 = Selector.read.rawValue
        let o = try call(&p, key: key)
        return withUnsafeBytes(of: o.bytes) { Array($0.prefix(info.size)) }
    }

    public func write(_ key: String, _ bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        guard bytes.count == info.size else { throw SMCError.badSize(key, info.size, bytes.count) }
        var p = SMCParamStruct(); p.key = Self.fourCC(key); p.keyInfo.dataSize = UInt32(info.size); p.data8 = Selector.write.rawValue
        withUnsafeMutableBytes(of: &p.bytes) { buf in for (i, b) in bytes.enumerated() { buf[i] = b } }
        _ = try call(&p, key: key)
    }

    // MARK: typed helpers

    /// Numeric value of a key, decoded with this machine's SMC byte order.
    public func readFloat(_ key: String) -> Double? { readNumber(key) }
}
