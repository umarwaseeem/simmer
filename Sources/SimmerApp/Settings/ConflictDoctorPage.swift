import SwiftUI
import AppKit
import SimmerShared

struct ConflictDoctorPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var insights: InsightsModel = .shared
    @State private var pendingFix: Conflict?

    static let batterySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!

    var body: some View {
        Form {
            Section { PageHeader(page: .conflicts) }

            Section {
                if !insights.conflictsScanned {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning…").foregroundStyle(.secondary)
                    }
                } else if insights.conflicts.isEmpty {
                    EmptyState(symbol: "checkmark.seal.fill", title: "No conflicts",
                               message: "No other charge limiter or leftover helper was found. Simmer is the only tool that controls charging.",
                               tint: .green)
                } else {
                    ForEach(insights.conflicts) { c in
                        ConflictRow(conflict: c, helperConnected: model.connected,
                                    fix: { pendingFix = c },
                                    openSettings: { NSWorkspace.shared.open(Self.batterySettingsURL) })
                    }
                }
            } header: {
                HelpLabel("Scan Results", .conflicts)
            } footer: {
                SectionCaption("The scan is read-only. It looks at /Library/LaunchDaemons, /Library/PrivilegedHelperTools, running apps and the macOS charge limit setting.")
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "gearshape.2").font(.title2).frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Newer macOS versions have their own charge limit in System Settings → Battery. Use either the macOS limit or Simmer, not both.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If you keep the macOS limit on, it stops charging at its own level, and Simmer's limit cannot go above it.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Open Battery Settings") { NSWorkspace.shared.open(Self.batterySettingsURL) }
                            .help(.nativeChargeLimit)
                    }
                }
            } header: {
                HelpLabel("macOS Charge Limit", .nativeChargeLimit)
            }
        }
        .formStyle(.grouped)
        .pageRefresh(busy: insights.scanning, updated: insights.conflictsScannedAt) { insights.scanConflicts() }
        .onAppear { insights.scanConflicts() }
        .confirmationDialog(pendingFix.map { "Remove \($0.name)?" } ?? "Remove?",
                            isPresented: Binding(get: { pendingFix != nil }, set: { if !$0 { pendingFix = nil } }),
                            presenting: pendingFix) { c in
            Button("Remove", role: .destructive) {
                model.perform(.removeConflict(c.id))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { InsightsModel.shared.scanConflicts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            Text("The Simmer helper stops this background helper and deletes these files:\n\n" + c.paths.joined(separator: "\n")
                 + "\n\nThe other app stays installed. Remove it yourself if you no longer use it.")
        }
    }
}

struct ConflictRow: View {
    let conflict: Conflict
    let helperConnected: Bool
    let fix: () -> Void
    let openSettings: () -> Void

    private var runningApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: conflict.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.red).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conflict.name).font(.callout.weight(.semibold))
                    Text(kindTitle).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
                Text(conflict.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !conflict.paths.isEmpty, !conflict.paths.contains(where: { conflict.detail.contains($0) }) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(conflict.paths, id: \.self) { p in
                            Text(p).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                HStack {
                    switch conflict.kind {
                    case .leftoverHelper:
                        Button("Fix…", action: fix)
                            .disabled(!conflict.fixableBySimmer || !helperConnected)
                            .help(helperConnected ? "Remove this helper. You confirm the exact files first." : "The Simmer helper must run to remove it.")
                    case .runningApp:
                        if !runningApps.isEmpty {
                            Button("Quit \(conflict.name)") { runningApps.forEach { $0.terminate() } }
                        }
                        if conflict.fixableBySimmer { Button("Remove Helper…", action: fix).disabled(!helperConnected) }
                    case .nativeChargeLimit:
                        Button("Open Battery Settings", action: openSettings)
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch conflict.kind {
        case .leftoverHelper: return "gearshape.2.fill"
        case .runningApp: return "app.badge.fill"
        case .nativeChargeLimit: return "gearshape.2"
        }
    }

    private var kindTitle: String {
        switch conflict.kind {
        case .leftoverHelper: return "Background helper"
        case .runningApp: return "Running app"
        case .nativeChargeLimit: return "macOS setting"
        }
    }
}
