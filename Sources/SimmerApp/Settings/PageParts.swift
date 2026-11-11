import SwiftUI
import AppKit
import SimmerShared

/// A centered icon, title and explanation for pages without data yet.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tint)
            Text(title).font(.headline)
            Text(message)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            actions.controlSize(.small).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String, tint: Color = .secondary) {
        self.init(symbol: symbol, title: title, message: message, tint: tint) { EmptyView() }
    }
}

/// A button that switches the Settings window to another page.
struct PageLinkButton: View {
    let title: String
    let page: SettingsPage
    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.general.rawValue
    init(_ title: String, page: SettingsPage) { self.title = title; self.page = page }
    var body: some View {
        Button(title) { pageRaw = page.rawValue }
    }
}

/// A short colored verdict line with a symbol, for example "Cells are well balanced".
struct VerdictRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// A horizontal bar for a value out of a maximum, with a label and a value text.
struct ValueBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let text: String
    var tint: Color = .accentColor
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).foregroundStyle(tint).frame(width: 16) }
                Text(label).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(tint.gradient)
                        .frame(width: max(3, g.size.width * min(1, maxValue > 0 ? value / maxValue : 0)))
                }
            }
            .frame(height: 8)
            Text(text).monospacedDigit().foregroundStyle(.secondary).frame(width: 74, alignment: .trailing)
        }
        .font(.callout)
    }
}

enum DurationText {
    /// "7 h 20 min", "45 min".
    static func hours(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        if total < 60 { return "\(total) min" }
        if h >= 10 { return "\(Int(h.rounded())) h" }
        let m = total % 60
        return m == 0 ? "\(total / 60) h" : "\(total / 60) h \(m) min"
    }
}
