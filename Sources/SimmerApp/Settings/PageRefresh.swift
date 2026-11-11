import SwiftUI
import AppKit

/// What a page with sampled data tells the Settings window: when the data was read, whether a read is running,
/// and how to read it again. The window shows it as a toolbar control with ⌘R.
struct PageRefresh: Equatable, @unchecked Sendable {
    var busy: Bool
    var updated: Date?
    /// A short note after the time, for example "the helper measures every 60 s".
    var note: String?
    var action: @MainActor () -> Void

    static func == (a: PageRefresh, b: PageRefresh) -> Bool {
        a.busy == b.busy && a.updated == b.updated && a.note == b.note
    }
}

struct PageRefreshKey: PreferenceKey {
    static let defaultValue: PageRefresh? = nil
    static func reduce(value: inout PageRefresh?, nextValue: () -> PageRefresh?) { value = value ?? nextValue() }
}

extension View {
    /// Adds the Refresh control (toolbar button, ⌘R, "Updated 12 s ago") for this page.
    /// Put it on the page's Form, not inside a Section: rows of a grouped Form do not pass preferences up.
    func pageRefresh(busy: Bool, updated: Date?, note: String? = nil, action: @escaping @MainActor () -> Void) -> some View {
        preference(key: PageRefreshKey.self, value: PageRefresh(busy: busy, updated: updated, note: note, action: action))
    }
}

/// "Updated 12 s ago" plus the refresh button. Lives in the Settings window toolbar.
struct PageRefreshControl: View {
    let refresh: PageRefresh

    var body: some View {
        HStack(spacing: 8) {
            if refresh.updated != nil || refresh.note != nil {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.statusText(updated: refresh.updated, note: refresh.note, now: ctx.date))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1)
                }
                .help(refresh.note.map { "Simmer shows the newest reading. Note: \($0)." } ?? "When this page last read its data.")
            }
            RefreshButton(busy: refresh.busy, action: refresh.action)
        }
    }

    static func statusText(updated: Date?, note: String?, now: Date) -> String {
        var parts: [String] = []
        if let updated { parts.append("Updated \(ago(updated, now: now))") }
        if let note { parts.append(note) }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "just now", "12 s ago", "4 min ago", "at 14:05".
    static func ago(_ d: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 3 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "at \(d.formatted(date: .omitted, time: .shortened))"
    }
}

/// A round arrow that turns while the page reads its data. ⌘R triggers it.
struct RefreshButton: View {
    let busy: Bool
    let action: @MainActor () -> Void
    @State private var turns = 0.0
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            spin()
            action()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .rotationEffect(.degrees(turns * 360))
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Read the data again (⌘R)")
        .accessibilityLabel(busy ? "Refreshing" : "Refresh")
        .onChange(of: busy) { _, on in if on { spin() } }
    }

    /// At least one full turn, so even a fast read gives visible feedback; more turns while still busy.
    private func spin() {
        guard !spinning, !reduceMotion else { return }
        spinning = true
        turnOnce()
    }

    private func turnOnce() {
        withAnimation(.linear(duration: 0.7)) {
            turns += 1
        } completion: {
            if busy { turnOnce() } else { spinning = false }
        }
    }
}
