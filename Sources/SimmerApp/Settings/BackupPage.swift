import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SimmerShared

extension UTType {
    /// `.simmerbackup` files (JSON). Declared dynamically; the app does not need to own the type.
    static var simmerBackup: UTType { UTType(filenameExtension: SimmerBackup.fileExtension, conformingTo: .json) ?? .json }
}

/// A backup that was read and validated, waiting for the user to confirm.
struct PendingImport: Identifiable {
    let backup: SimmerBackup
    let source: String
    let changes: [BackupChange]
    var id: Date { backup.createdAt }
}

struct BackupPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var layoutStore: PanelLayoutStore = .shared
    @State private var backups: [BackupManager.Entry] = []
    @State private var pending: PendingImport?
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        Form {
            Section { PageHeader(page: .backup) }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(.tint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export settings").font(.callout.weight(.medium))
                        Text("Charge limit, battery care, schedule, LED, panel layout and app preferences.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export…") { exportBackup() }
                        .disabled(!model.connected)
                        .help(model.connected ? HelpTopic.backup.tooltip : "Connect the helper first, so the export contains your current settings.")
                }
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.title2).foregroundStyle(.tint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import settings").font(.callout.weight(.medium))
                        Text("Shows every change before anything is applied.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import…") { importBackup() }
                        .disabled(!model.connected)
                        .help(.importBackup)
                }
                if let message {
                    Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(message.isError ? Color.red : Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                HelpLabel("File", .backup)
            }

            Section {
                if backups.isEmpty {
                    Text("No automatic backup yet. The first one is saved within a day after the helper connects.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { e in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                Text(e.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore…") { preview(url: e.url) }
                                .controlSize(.small).disabled(!model.connected)
                        }
                    }
                }
                HStack {
                    Button("Back Up Now") {
                        if BackupManager.write(BackupManager.make(config: model.config, layout: layoutStore.layout)) != nil {
                            BackupManager.prune()
                            message = ("Backup saved.", false)
                        } else { message = ("Could not save the backup.", true) }
                        reload()
                    }
                    .disabled(!model.connected)
                    Spacer()
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: BackupManager.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([BackupManager.directory])
                    }
                }
                .controlSize(.small)
            } header: {
                HelpLabel("Automatic Weekly Backups", .autoBackup)
            } footer: {
                SectionCaption("Saved in ~/Library/Application Support/Simmer/Backups. Simmer keeps the last \(BackupManager.keep).")
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .sheet(item: $pending) { p in
            ImportPreviewSheet(pending: p, apply: { apply(p.backup) }, cancel: { pending = nil })
        }
    }

    private func reload() { backups = BackupManager.list() }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.simmerBackup]
        panel.nameFieldStringValue = BackupManager.defaultFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackupManager.make(config: model.config, layout: layoutStore.layout).encoded().write(to: url, options: .atomic)
            message = ("Exported to \(url.lastPathComponent).", false)
        } catch {
            message = ("Export failed: \(error.localizedDescription)", true)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.simmerBackup, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preview(url: url)
    }

    private func preview(url: URL) {
        do {
            let b = try SimmerBackup.decode(try Data(contentsOf: url))
            pending = PendingImport(backup: b, source: url.lastPathComponent,
                                    changes: b.changes(from: model.config, prefs: .current(), layout: layoutStore.layout))
        } catch {
            message = (error.localizedDescription, true)
        }
    }

    private func apply(_ b: SimmerBackup) {
        model.updateConfig { $0 = b.config }
        b.prefs?.apply()
        model.prefs = UIPrefs.load()
        if let l = b.panelLayout { layoutStore.layout = l }
        pending = nil
        message = ("Settings restored from the backup of \(b.createdAt.formatted(date: .abbreviated, time: .shortened)).", false)
    }
}

struct ImportPreviewSheet: View {
    let pending: PendingImport
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore this backup?").font(.headline)
                    Text("\(pending.source) · made \(pending.backup.createdAt.formatted(date: .abbreviated, time: .shortened))"
                         + (pending.backup.appVersion.isEmpty ? "" : " by Simmer \(pending.backup.appVersion)")
                         + (pending.backup.macModel.isEmpty ? "" : " on \(pending.backup.macModel)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if pending.changes.isEmpty {
                Label("This backup matches your current settings. Nothing would change.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(pending.changes.count) setting\(pending.changes.count == 1 ? "" : "s") will change:").font(.callout.weight(.medium))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pending.changes) { c in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(c.key).frame(width: 190, alignment: .leading).lineLimit(2)
                                Text(c.old).foregroundStyle(.secondary).strikethrough().lineLimit(1)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text(c.new).fontWeight(.medium).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Apply", action: apply).keyboardShortcut(.defaultAction).disabled(pending.changes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
