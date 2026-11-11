import Foundation
import os

/// Shared daemon logger. View with:
/// `log stream --predicate 'subsystem == "com.umarwaseem.simmer"'`
let log = Logger(subsystem: "com.umarwaseem.simmer", category: "daemon")

/// How the binary runs. Only `.daemon` touches hardware, pmset, disk or XPC.
enum RunMode: Equatable {
    case daemon       // root, full control
    case dryRun       // read-only, prints one line per tick
    case statusOnly   // read-only, one tick then exit

    var writesHardware: Bool { self == .daemon }
    var persists: Bool { self == .daemon }
    var runsScheduler: Bool { self != .statusOnly }
    var holdsSleepAssertion: Bool { self == .daemon }
    var postsNotifications: Bool { self == .daemon }
}

func stderrPrint(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}
