import SwiftUI
import SimmerShared

struct SchedulePage: View {
    @ObservedObject var model: AppModel
    @State private var editing: ScheduledTask?

    var body: some View {
        SettingsForm(page: .schedule, model: model, requiresHelper: true) {
            Section {
                if model.config.schedule.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No scheduled tasks").font(.callout.weight(.medium))
                            SectionCaption("Add a task, for example a Top Up every Monday morning.")
                        }
                    }
                    .padding(.vertical, 4)
                }
                ForEach(model.config.schedule) { task in
                    TaskRow(task: task, model: model) { editing = task }
                }
            } header: {
                HStack {
                    HelpLabel("Tasks", .schedule)
                    Spacer()
                    Button { editing = ScheduledTask(name: "New Task", action: .setLimit(80), recurrence: .daily, hour: 8, minute: 0) } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                }
            }
            Section {
                SettingToggle("Catch up on missed tasks",
                              caption: "If the Mac was asleep or off, the most recent missed task runs when it wakes.",
                              topic: .catchUp, isOn: model.binding(\.catchUpMissedTasks))
            }
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task) { model.saveTask($0); editing = nil } onCancel: { editing = nil }
        }
    }
}

struct TaskRow: View {
    let task: ScheduledTask
    @ObservedObject var model: AppModel
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { task.enabled },
                set: { on in var t = task; t.enabled = on; model.saveTask(t) }))
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            .help(task.enabled ? "Turn this task off" : "Turn this task on")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name).font(.callout.weight(.medium))
                    .foregroundStyle(task.enabled ? .primary : .secondary)
                Text("\(Fmt.describe(task.action)) · \(Fmt.describe(task.recurrence)) at \(Fmt.time(hour: task.hour, minute: task.minute))")
                    .font(.caption).foregroundStyle(.secondary)
                if let last = task.lastRun {
                    Text("Last run \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { model.runTask(task.id) } label: { Image(systemName: "play.fill") }
                .help("Run this task now, without waiting for its time")
            Button(action: onEdit) { Image(systemName: "pencil") }
                .help("Edit")
            Button(role: .destructive) { model.deleteTask(task.id) } label: { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}

struct TaskEditor: View {
    enum ActionKind: String, CaseIterable, Identifiable {
        case setLimit = "Set Charge Limit", topUp = "Top Up", discharge = "Discharge", calibrate = "Calibrate"
        case lpmOn = "Low Power Mode On", lpmOff = "Low Power Mode Off"
        case hpmOn = "High Power Mode On", hpmOff = "High Power Mode Off"
        case limiterOn = "Enable Limiter", limiterOff = "Disable Limiter"
        var id: String { rawValue }
    }
    enum RecurrenceKind: String, CaseIterable, Identifiable {
        case once = "Once", daily = "Daily", weekly = "Weekly", biweekly = "Every 2 Weeks", monthly = "Monthly"
        var id: String { rawValue }
    }

    let original: ScheduledTask
    let onSave: (ScheduledTask) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var enabled: Bool
    @State private var actionKind: ActionKind
    @State private var limitValue: Int
    @State private var dischargeValue: Int
    @State private var recurrenceKind: RecurrenceKind
    @State private var onceDate: Date
    @State private var weekdays: Set<Weekday>
    @State private var biweeklyDay: Weekday
    @State private var monthDay: Int
    @State private var time: Date

    init(task: ScheduledTask, onSave: @escaping (ScheduledTask) -> Void, onCancel: @escaping () -> Void) {
        original = task
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: task.name)
        _enabled = State(initialValue: task.enabled)

        var kind = ActionKind.setLimit, limit = 80, discharge = 50
        switch task.action {
        case .setLimit(let v): kind = .setLimit; limit = v
        case .topUp: kind = .topUp
        case .discharge(let v): kind = .discharge; discharge = v
        case .calibrate: kind = .calibrate
        case .lowPowerMode(let b): kind = b ? .lpmOn : .lpmOff
        case .highPowerMode(let b): kind = b ? .hpmOn : .hpmOff
        case .limiter(let b): kind = b ? .limiterOn : .limiterOff
        }
        _actionKind = State(initialValue: kind)
        _limitValue = State(initialValue: limit)
        _dischargeValue = State(initialValue: discharge)

        var rk = RecurrenceKind.daily, once = Date(), days: Set<Weekday> = [.mon], bi = Weekday.mon, dom = 1
        switch task.recurrence {
        case .once(let d): rk = .once; once = d
        case .daily: rk = .daily
        case .weekly(let w): rk = .weekly; days = Set(w)
        case .biweekly(let d): rk = .biweekly; bi = d
        case .monthly(let d): rk = .monthly; dom = d
        }
        _recurrenceKind = State(initialValue: rk)
        _onceDate = State(initialValue: once)
        _weekdays = State(initialValue: days)
        _biweeklyDay = State(initialValue: bi)
        _monthDay = State(initialValue: dom)
        _time = State(initialValue: Calendar.current.date(bySettingHour: task.hour, minute: task.minute, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("Enabled", isOn: $enabled)
                }
                Section("Action") {
                    Picker("Action", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if actionKind == .setLimit {
                        Stepper(value: $limitValue, in: 20...100, step: 5) { LabeledContent("Limit", value: "\(limitValue)%") }
                    }
                    if actionKind == .discharge {
                        Stepper(value: $dischargeValue, in: 20...100, step: 5) { LabeledContent("Discharge to", value: "\(dischargeValue)%") }
                    }
                }
                Section("When") {
                    Picker("Repeat", selection: $recurrenceKind) {
                        ForEach(RecurrenceKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    switch recurrenceKind {
                    case .once:
                        DatePicker("Date", selection: $onceDate, displayedComponents: .date)
                    case .daily:
                        EmptyView()
                    case .weekly:
                        LabeledContent("Days") {
                            HStack(spacing: 4) {
                                ForEach(Weekday.allCases, id: \.self) { d in
                                    Toggle(String((Fmt.weekdayShort[d] ?? "").prefix(2)), isOn: Binding(
                                        get: { weekdays.contains(d) },
                                        set: { if $0 { weekdays.insert(d) } else { weekdays.remove(d) } }))
                                    .toggleStyle(.button).controlSize(.small)
                                }
                            }
                        }
                    case .biweekly:
                        Picker("Day", selection: $biweeklyDay) {
                            ForEach(Weekday.allCases, id: \.self) { Text(Fmt.weekdayShort[$0] ?? "").tag($0) }
                        }
                    case .monthly:
                        Stepper(value: $monthDay, in: 1...31) { LabeledContent("Day of month", value: "\(monthDay)") }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(build()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (recurrenceKind == .weekly && weekdays.isEmpty))
            }
            .padding(12)
        }
        .frame(width: 440, height: 480)
    }

    private func build() -> ScheduledTask {
        var t = original
        t.name = name.trimmingCharacters(in: .whitespaces)
        t.enabled = enabled
        switch actionKind {
        case .setLimit: t.action = .setLimit(limitValue)
        case .topUp: t.action = .topUp
        case .discharge: t.action = .discharge(dischargeValue)
        case .calibrate: t.action = .calibrate
        case .lpmOn: t.action = .lowPowerMode(true)
        case .lpmOff: t.action = .lowPowerMode(false)
        case .hpmOn: t.action = .highPowerMode(true)
        case .hpmOff: t.action = .highPowerMode(false)
        case .limiterOn: t.action = .limiter(true)
        case .limiterOff: t.action = .limiter(false)
        }
        let cal = Calendar.current
        t.hour = cal.component(.hour, from: time)
        t.minute = cal.component(.minute, from: time)
        switch recurrenceKind {
        case .once:
            let day = cal.startOfDay(for: onceDate)
            t.recurrence = .once(cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) ?? onceDate)
        case .daily: t.recurrence = .daily
        case .weekly: t.recurrence = .weekly(weekdays.sorted { $0.rawValue < $1.rawValue })
        case .biweekly: t.recurrence = .biweekly(biweeklyDay)
        case .monthly: t.recurrence = .monthly(day: monthDay)
        }
        // A changed schedule should fire at its next occurrence, not catch up on an old one.
        if t.recurrence != original.recurrence || t.hour != original.hour || t.minute != original.minute {
            t.lastRun = nil
        }
        return t
    }
}
