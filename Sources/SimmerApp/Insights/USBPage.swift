import SwiftUI
import SimmerShared

struct USBPage: View {
    @State private var snapshot: USBSnapshot?
    @State private var updated: Date?
    @State private var reading = false
    private let autoLoad: Bool

    init(initial: USBSnapshot? = nil, autoLoad: Bool = true) {
        _snapshot = State(initialValue: initial)
        self.autoLoad = autoLoad
    }

    var body: some View {
        Form {
            Section { PageHeader(page: .usb) }
            if let s = snapshot {
                Section {
                    if s.ports.isEmpty {
                        Label("No port is powering a device right now.", systemImage: "bolt.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(s.ports) { p in
                            LabeledContent {
                                HStack(spacing: 10) {
                                    Text(String(format: "%.1f V · %.2f A", p.voltageV, p.currentA)).foregroundStyle(.secondary)
                                    Text(String(format: "%.1f W", p.watts)).fontWeight(.semibold)
                                }
                                .monospacedDigit()
                            } label: {
                                Label("Port \(p.port)", systemImage: "bolt.horizontal.fill")
                            }
                            .help(p.maxCurrentA.map { String(format: "This port may supply up to %.1f A.", $0) } ?? "")
                        }
                        if s.ports.count > 1 {
                            LabeledContent("Total") { Text(String(format: "%.1f W", s.totalOutW)).monospacedDigit().fontWeight(.semibold) }
                        }
                    }
                } header: {
                    HelpLabel("Power Out of Your Mac", .usbPower)
                } footer: {
                    SectionCaption("Live power the Mac sends to devices on its USB-C ports, measured by the power controller. A hub on one port counts as one.")
                }

                Section {
                    if s.devices.isEmpty {
                        EmptyState(symbol: "cable.connector", title: "No USB devices",
                                   message: "Nothing is connected over USB right now. Built-in parts such as the keyboard and trackpad are not listed.")
                    } else {
                        ForEach(s.devices) { USBDeviceRow(device: $0) }
                    }
                } header: {
                    HelpLabel("Connected Devices", .usbAllocation)
                } footer: {
                    SectionCaption("\"Reserved\" is the power macOS set aside for the device (milliamps at 5 V). It is the most the device may draw, not what it uses right now.")
                }
            } else {
                Section {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading USB devices…").foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
        .pageRefresh(busy: reading, updated: updated, note: "checks every 3 s") { Task { await read() } }
        .task {
            while autoLoad && !Task.isCancelled {
                await read()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func read() async {
        guard !reading else { return }
        reading = true
        let s = await Task.detached(priority: .utility) { USBSnapshot.read() }.value
        if s != snapshot { snapshot = s }
        updated = Date()
        reading = false
    }
}

struct USBDeviceRow: View {
    let device: USBSnapshot.Device

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.isHub ? "rectangle.connected.to.line.below" : symbol)
                .foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).lineLimit(1)
                Text([device.vendor.isEmpty ? nil : device.vendor, device.speedText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let ma = device.allocationMA, ma > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f W", device.allocationW ?? 0)).monospacedDigit()
                    Text("\(ma) mA reserved").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text(device.isHub ? "Hub" : "Not reported").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(min(device.depth, 3)) * 18)
        .padding(.vertical, 1)
    }

    private var symbol: String {
        let n = device.name.lowercased()
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") { return "computermouse" }
        if n.contains("camera") || n.contains("webcam") || n.contains("cam ") { return "web.camera" }
        if n.contains("audio") || n.contains("headset") || n.contains("mic") || n.contains("speaker") { return "headphones" }
        if n.contains("ssd") || n.contains("drive") || n.contains("disk") || n.contains("storage") { return "externaldrive" }
        if n.contains("iphone") || n.contains("ipad") || n.contains("phone") { return "iphone" }
        if n.contains("ethernet") || n.contains("lan") { return "network" }
        return "cable.connector"
    }
}
