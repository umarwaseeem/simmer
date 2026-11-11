import Foundation
import IOKit
import IOKit.pwr_mgt

// iokit_common_msg(x) = sys_iokit (0xE0000000) | sub_iokit_common (0) | x. The C macros do not import into Swift.
private let kMsgCanSystemSleep: UInt32 = 0xE000_0270
private let kMsgSystemWillSleep: UInt32 = 0xE000_0280
private let kMsgSystemWillNotSleep: UInt32 = 0xE000_0290
private let kMsgSystemHasPoweredOn: UInt32 = 0xE000_0300
private let kMsgSystemWillPowerOn: UInt32 = 0xE000_0320

/// Holds a PreventUserIdleSystemSleep assertion while the policy asks for it.
/// Use only from the engine queue.
final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private var reason: String?
    var isHeld: Bool { reason != nil }

    func set(_ prevent: Bool, reason newReason: String) {
        if !prevent { release(); return }
        let name = "Simmer: \(newReason)"
        if reason == name { return }
        release()
        var newID: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &newID)
        if r == kIOReturnSuccess {
            id = newID; reason = name
            log.info("sleep assertion taken: \(name, privacy: .public)")
        } else {
            log.error("IOPMAssertionCreateWithName failed: \(String(format: "0x%08x", r), privacy: .public)")
        }
    }

    func release() {
        guard reason != nil else { return }
        IOPMAssertionRelease(id)
        log.info("sleep assertion released: \(self.reason ?? "", privacy: .public)")
        id = 0; reason = nil
    }
}

/// Blocks all system sleep, including lid-close (clamshell) sleep, via `pmset -a disablesleep`.
/// Needed while the adapter is disabled: macOS then sees battery power and sleeps on lid close, which
/// turns external displays off (observed: "Entering Sleep state due to 'Clamshell Sleep' ... Using Batt").
/// A marker file records that Simmer set it, so a crash or reboot never leaves sleep disabled for good.
final class ClamshellSleepBlocker {
    private let marker = "/Library/Application Support/Simmer/sleep-disabled-by-simmer"
    private(set) var isActive = false

    /// Call once at daemon start: undo a block left behind by a crash.
    func recover() {
        if FileManager.default.fileExists(atPath: marker) {
            log.notice("clearing disablesleep left over from a previous run")
            if Self.pmset(false) { try? FileManager.default.removeItem(atPath: marker) }
        }
    }

    func set(_ on: Bool) {
        guard on != isActive else { return }
        guard Self.pmset(on) else { return }
        isActive = on
        if on { FileManager.default.createFile(atPath: marker, contents: Data()) }
        else { try? FileManager.default.removeItem(atPath: marker) }
        log.notice("clamshell sleep \(on ? "blocked" : "allowed", privacy: .public)")
    }

    @discardableResult
    private static func pmset(_ on: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-a", "disablesleep", on ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { log.error("pmset disablesleep failed: \(error.localizedDescription, privacy: .public)"); return false }
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return false }
        return p.terminationStatus == 0
    }
}

/// Receives system sleep / wake messages on the main run loop.
final class SystemPowerObserver {
    enum Event { case willSleep, hasPoweredOn }

    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    /// Runs synchronously on the main thread. For `.willSleep` it must finish its work before returning;
    /// sleep continues right after it returns.
    private let handler: (Event) -> Void

    init?(_ handler: @escaping (Event) -> Void) {
        self.handler = handler
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            Unmanaged<SystemPowerObserver>.fromOpaque(refcon).takeUnretainedValue()
                .handle(messageType, Int(bitPattern: messageArgument))
        }, &notifier)
        guard rootPort != 0, let notifyPort else {
            log.error("IORegisterForSystemPower failed")
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let notifyPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
            IONotificationPortDestroy(notifyPort)
        }
        if rootPort != 0 { IOServiceClose(rootPort) }
    }

    private func handle(_ message: UInt32, _ argument: Int) {
        switch message {
        case kMsgCanSystemSleep:
            IOAllowPowerChange(rootPort, argument)
        case kMsgSystemWillSleep:
            log.info("system will sleep")
            handler(.willSleep)
            IOAllowPowerChange(rootPort, argument)
        case kMsgSystemHasPoweredOn:
            log.info("system has powered on")
            handler(.hasPoweredOn)
        case kMsgSystemWillNotSleep, kMsgSystemWillPowerOn:
            break
        default:
            break
        }
    }
}

/// Puts the Mac to sleep now.
func sleepSystemNow() -> String? {
    let port = IOPMFindPowerManagement(kIOMainPortDefault)
    guard port != 0 else { return "Cannot reach IOPMrootDomain" }
    defer { IOServiceClose(port) }
    let r = IOPMSleepSystem(port)
    return r == kIOReturnSuccess ? nil : "IOPMSleepSystem failed (\(String(format: "0x%08x", r)))"
}
