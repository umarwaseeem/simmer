import SwiftUI
import SimmerShared

// MARK: - Shortcuts

struct ShortcutsPage: View {
    private let urls: [(String, String)] = [
        ("simmer://limit/80", "Set the charge limit (20–100)"),
        ("simmer://limiter/on · /off", "Enable or disable the limiter"),
        ("simmer://topup · /topup/off", "Start or stop Top Up"),
        ("simmer://discharge · /discharge/off", "Start or stop discharge"),
        ("simmer://calibrate · /calibrate/stop", "Start or stop calibration"),
        ("simmer://pause", "Set the limit to the current percentage"),
        ("simmer://led/system · /smart · /off · /custom", "MagSafe LED mode"),
        ("simmer://lpm/on · /off", "Low Power Mode"),
        ("simmer://hpm/on · /off", "High Power Mode"),
        ("simmer://sleep", "Sleep now"),
    ]
    private let commands: [(String, String)] = [
        ("simmerctl status [--json]", "Battery, state and power flow"),
        ("simmerctl limit 80", "Set the charge limit"),
        ("simmerctl limiter on|off", "Enable or disable the limiter"),
        ("simmerctl topup on|off", "Top Up"),
        ("simmerctl discharge on|off", "Discharge"),
        ("simmerctl calibrate start|stop", "Calibration"),
        ("simmerctl pause", "Limit to the current percentage"),
        ("simmerctl led system|smart|off|custom", "MagSafe LED mode"),
        ("simmerctl led charging green", "Custom LED color for one state"),
        ("simmerctl led blink green|orange|alternate|heartbeat|level [n]", "Blink the MagSafe LED as a notification"),
        ("simmerctl lpm on|off [all|battery|charger]", "Low Power Mode"),
        ("simmerctl hpm on|off [all|battery|charger]", "High Power Mode"),
        ("simmerctl sleep", "Sleep now"),
        ("simmerctl config [--json]", "Show all settings"),
        ("simmerctl set sailing on", "Change a setting (see simmerctl help)"),
    ]

    var body: some View {
        Form {
            Section { PageHeader(page: .shortcuts) }
            Section {
                ForEach(urls, id: \.0) { row($0.0, $0.1) }
            } header: {
                HelpLabel("URL Scheme", .shortcuts)
            } footer: {
                SectionCaption("In Shortcuts, use the \"Open URLs\" action. In Terminal: open simmer://limit/80")
            }
            Section {
                ForEach(commands, id: \.0) { row($0.0, $0.1) }
            } header: {
                Text("Command Line")
            } footer: {
                SectionCaption("In Shortcuts, use \"Run Shell Script\" with /usr/local/bin/simmerctl.")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ code: String, _ note: String) -> some View {
        LabeledContent {
            Text(note).font(.callout).foregroundStyle(.secondary)
        } label: {
            Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }
    }
}

// MARK: - Helper

struct HelperPage: View {
    @ObservedObject var model: AppModel
    @State private var confirmUninstall = false
    @AppStorage("SUEnableAutomaticChecks") private var autoUpdates = true

    var body: some View {
        Form {
            Section { PageHeader(page: .helper) }

            if let s = model.status, s.helperOutdated {
                Section {
                    HelperUpdateBanner(installing: model.installing) { model.installHelper() }
                        .disabled(!HelperInstaller.isBundled)
                    LabeledContent("Helper running", value: s.helperVersion)
                    LabeledContent("Helper in this app", value: Simmer.helperVersion)
                }
            }

            Section {
                LabeledContent {
                    connectionBadge
                } label: {
                    HelpLabel("Connection", .helper)
                }
                if let e = model.connectionError, model.reachable == false {
                    Text(e).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button(model.helperInstalled ? "Reinstall Helper" : "Install Helper") { model.installHelper() }
                    Button("Uninstall Helper…", role: .destructive) { confirmUninstall = true }
                        .disabled(!model.helperInstalled)
                    Spacer()
                    if model.installing { ProgressView().controlSize(.small) }
                }
                .disabled(model.installing || !HelperInstaller.isBundled)
                if !HelperInstaller.isBundled {
                    Label("Install scripts are missing. Run Simmer from the app bundle that scripts/build.sh creates.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let err = model.commandError { Text(err).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Status")
            } footer: {
                SectionCaption("Installing asks for an administrator password. It does not touch the helpers of other apps.")
            }

            Section("Details") {
                LabeledContent("Helper version", value: model.helperVersion ?? "–")
                if let s = model.status {
                    let caps = UICapabilities(s)
                    LabeledContent("Charge backend", value: s.backend.rawValue.uppercased())
                    LabeledContent("Discharge support", value: caps.discharge ? "Yes" : "No")
                    LabeledContent("MagSafe LED support", value: caps.led ? "Yes" : "No")
                    if caps.limitOnly { LabeledContent("Charge control", value: "Limit only (kept when off)") }
                }
                LabeledContent("Install path") {
                    Text(Simmer.helperInstallPath).font(.caption).textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simmer \(AppInfo.version)").font(.callout.weight(.medium))
                        Text("Build \(AppInfo.build)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        NotificationCenter.default.post(name: Notification.Name("SimmerCheckForUpdates"), object: nil)
                    }
                    .help(.updates)
                }
                Toggle(isOn: $autoUpdates) { HelpLabel("Automatically check for updates", .autoUpdates) }
            } header: {
                HelpLabel("Updates", .updates)
            } footer: {
                SectionCaption("The installer copies the helper to /Library/PrivilegedHelperTools, loads its LaunchDaemon and installs simmerctl to /usr/local/bin.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Uninstall the Simmer helper?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { model.uninstallHelper(purge: false) }
            Button("Uninstall and Delete Settings", role: .destructive) { model.uninstallHelper(purge: true) }
        } message: {
            Text("The uninstaller restores the default charging behavior (SMC keys) and removes the helper and simmerctl.")
        }
    }

    @ViewBuilder private var connectionBadge: some View {
        switch model.reachable {
        case .some(true): Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false): Label(model.helperInstalled ? "Not responding" : "Not installed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .none: Text("Checking…").foregroundStyle(.secondary)
        }
    }
}
