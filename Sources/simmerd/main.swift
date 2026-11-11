import Darwin
import Foundation
import SimmerShared

let usage = """
usage: simmerd [--dry-run | --status | --reset | --energy-once [--json]] [--insecure-xpc]

  (no flags)      run the privileged daemon (root, normally started by launchd)
  --dry-run       read-only: run the policy every tick and print what would be written
  --status        print one SimmerStatus JSON (read-only) and exit
  --reset         restore defaults (charging allowed, adapter enabled, LED system; BCLM 100) and exit; needs root
  --energy-once   read-only: sample per-process energy twice, 3 s apart, print the top apps and the
                  sampler cost, and exit (non-root sees only its own processes)
  --insecure-xpc  accept XPC clients without a code-signing check (debugging only;
                  also enabled by SIMMER_INSECURE_XPC=1)
"""

let args = Set(CommandLine.arguments.dropFirst())
let known: Set<String> = ["--dry-run", "--status", "--reset", "--energy-once", "--json", "--insecure-xpc", "--help", "-h"]
if let bad = args.subtracting(known).first {
    stderrPrint("simmerd: unknown option \(bad)\n\(usage)")
    exit(2)
}
if args.contains("--help") || args.contains("-h") { print(usage); exit(0) }

if args.contains("--energy-once") {
    EnergySampler.printOnce(json: args.contains("--json"))
} else if args.contains("--status") {
    Daemon.printStatus()
} else if args.contains("--reset") {
    Daemon.reset()
} else if args.contains("--dry-run") {
    Daemon(mode: .dryRun, insecureXPC: false).run()
} else {
    guard getuid() == 0 else {
        stderrPrint("simmerd: must run as root (use --dry-run or --status to test as a normal user)")
        exit(1)
    }
    let insecure = args.contains("--insecure-xpc") || ProcessInfo.processInfo.environment["SIMMER_INSECURE_XPC"] == "1"
    Daemon(mode: .daemon, insecureXPC: insecure).run()
}
