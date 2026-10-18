import SwiftUI
import SwiftData
import HeedCore

/// Everything about one task. Changes save as you make them; Done just closes the sheet.
struct TaskDetailView: View {
    @Bindable var item: TodoItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @State private var tagText = ""
    @State private var newStep = ""
    @FocusState private var stepFocused: Bool

    private var today: Int { app.today }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $item.title, axis: .vertical).font(.title3.weight(.semibold))
                    TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(2...8)
                }
                whenSection
                stepsSection
                organiseSection
                footerSection
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .onAppear { tagText = item.tags.joined(separator: ", ") }
            .onDisappear(perform: finish)
            .onChange(of: item.reminderLead) { _, lead in
                guard lead != nil else { return }
                Task {
                    await Reminders.requestAuthorizationIfNeeded()
                    await Reminders.syncAll()
                }
            }
        }
    }

    // MARK: When

    private var whenSection: some View {
        Section("When") {
            Toggle(isOn: hasDate) { Label("Date", systemImage: "calendar") }
            if item.dueDay != nil {
                DatePicker("Day", selection: dateBinding, displayedComponents: .date)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([Reschedule.today, .tomorrow, .weekend, .nextWeek], id: \.self) { option in
                            Button(option.label) {
                                setDue(option.target(from: today, firstWeekday: Calendar.current.firstWeekday))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                Toggle(isOn: hasTime) { Label("Time", systemImage: "clock") }
                if item.dueMinutes != nil {
                    DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            }
            NavigationLink {
                RecurrenceEditor(rule: recurrenceBinding, due: item.dueDay ?? today)
            } label: {
                HStack {
                    Label("Repeat", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(item.recurrence?.summary() ?? "Never").foregroundStyle(.secondary)
                }
            }
            if item.dueDay != nil {
                Picker(selection: $item.reminderLead) {
                    Text("None").tag(Int?.none)
                    ForEach(reminderOptions, id: \.self) { Text(reminderLabel($0)).tag(Int?.some($0)) }
                } label: { Label("Reminder", systemImage: "bell") }
            }
        }
    }

    private var hasDate: Binding<Bool> {
        Binding(get: { item.dueDay != nil }, set: { on in setDue(on ? (item.dueDay ?? today) : nil) })
    }

    private var hasTime: Binding<Bool> {
        Binding(get: { item.dueMinutes != nil }, set: { on in
            item.dueMinutes = on ? (item.dueMinutes ?? Preferences.defaultReminderMinutes) : nil
            // A task with a time reminds you at that time unless you say otherwise.
            if on, item.reminderLead == nil { item.reminderLead = 0 }
        })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { Day.date(for: item.dueDay ?? today) }, set: { setDue(Day.key(for: $0)) })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { Day.date(for: item.dueDay ?? today, minutes: item.dueMinutes ?? Preferences.defaultReminderMinutes) },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    item.dueMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                })
    }

    /// Changing the date keeps a monthly or yearly rule aimed at the new day.
    private func setDue(_ day: Int?) {
        item.dueDay = day
        guard let day else {
            item.dueMinutes = nil
            item.reminderLead = nil
            item.recurrence = nil
            return
        }
        if var rule = item.recurrence {
            let parts = Day.ymd(day)
            if rule.unit == .month || rule.unit == .year { rule.dayOfMonth = parts.day }
            if rule.unit == .year { rule.month = parts.month }
            item.recurrence = rule
        }
    }

    private var recurrenceBinding: Binding<Recurrence?> {
        Binding(get: { item.recurrence }, set: { new in
            guard let new else { item.recurrence = nil; return }
            let day = item.dueDay ?? new.firstOccurrence(onOrAfter: today)
            if item.dueDay == nil { item.dueDay = day }
            item.recurrence = new.anchored(to: day)
        })
    }

    private var reminderOptions: [Int] {
        var options = item.dueMinutes != nil ? [0, 5, 15, 30, 60, 1440] : [0, 1440]
        if let current = item.reminderLead, !options.contains(current) { options.append(current); options.sort() }
        return options
    }

    private func reminderLabel(_ lead: Int) -> String {
        switch lead {
        case 0: return item.dueMinutes != nil ? "At time of task" : "On the day, \(DateText.time(Preferences.defaultReminderMinutes))"
        case 1440: return "1 day before"
        case 60: return "1 hour before"
        default: return "\(lead) minutes before"
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        Section("Steps") {
            ForEach(item.checklist) { step in
                HStack {
                    Button { toggle(step) } label: {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.done ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.done ? "Mark step not done" : "Mark step done")
                    TextField("Step", text: titleBinding(for: step))
                        .strikethrough(step.done)
                        .foregroundStyle(step.done ? .secondary : .primary)
                }
            }
            .onDelete { offsets in
                var steps = item.checklist
                steps.remove(atOffsets: offsets)
                item.checklist = steps
            }
            .onMove { source, target in
                var steps = item.checklist
                steps.move(fromOffsets: source, toOffset: target)
                item.checklist = steps
            }
            HStack {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                TextField("Add a step", text: $newStep)
                    .focused($stepFocused)
                    .submitLabel(.next)
                    .onSubmit(addStep)
            }
        }
    }

    private func toggle(_ step: ChecklistItem) {
        var steps = item.checklist
        if let index = steps.firstIndex(where: { $0.id == step.id }) { steps[index].done.toggle() }
        item.checklist = steps
        Haptics.tap()
    }

    private func titleBinding(for step: ChecklistItem) -> Binding<String> {
        Binding(get: { item.checklist.first { $0.id == step.id }?.title ?? "" }, set: { title in
            var steps = item.checklist
            if let index = steps.firstIndex(where: { $0.id == step.id }) { steps[index].title = title }
            item.checklist = steps
        })
    }

    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        item.checklist = item.checklist + [ChecklistItem(title: title)]
        newStep = ""
        stepFocused = true
    }

    // MARK: Organise

    private var organiseSection: some View {
        Section("Organise") {
            Picker(selection: $item.priorityRaw) {
                ForEach(Priority.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            } label: { Label("Priority", systemImage: "flag") }
            Picker(selection: $item.listID) {
                Text("Inbox").tag(UUID?.none)
                ForEach(lists) { Text($0.name).tag(UUID?.some($0.id)) }
            } label: { Label("List", systemImage: "list.bullet") }
            HStack {
                Label("Tags", systemImage: "tag")
                TextField("errand, phone", text: $tagText)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitTags)
            }
        }
    }

    private func commitTags() {
        item.tags = FilterEditor.tags(from: tagText)
        tagText = item.tags.joined(separator: ", ")
    }

    // MARK: Footer

    private var footerSection: some View {
        Section {
            Button {
                app.toggle(item, in: context)
                dismiss()
            } label: {
                Label(item.isCompleted ? "Reopen task" : "Mark as done", systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
            }
            Button(role: .destructive) {
                app.trash(item, in: context)
                dismiss()
            } label: { Label("Move to Trash", systemImage: "trash") }
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Added \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                if item.timesCompleted > 0 { Text("Completed \(item.timesCompleted) \(item.timesCompleted == 1 ? "time" : "times")") }
                Text("Trash keeps it for \(Trash.retentionDays) days.")
            }
        }
    }

    // MARK: Saving

    private func finish() {
        commitTags()
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.title = "Untitled task" }
        item.touch()
        TaskActions.commit(context)
    }
}

// MARK: - Repeat editor

struct RecurrenceEditor: View {
    @Binding var rule: Recurrence?
    let due: Int

    private static let presets: [(label: String, rule: Recurrence?)] = [
        ("Never", nil), ("Every day", .daily), ("Every weekday", .weekdaysOnly), ("Every week", .weekly),
        ("Every month", .monthly), ("Every year", .yearly),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.presets, id: \.label) { preset in
                    Button { rule = preset.rule } label: {
                        HStack {
                            Text(preset.label).foregroundStyle(.primary)
                            Spacer()
                            if isSelected(preset.rule) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            }

            if let current = rule {
                Section("Custom") {
                    Stepper(value: interval, in: 1...99) {
                        Text("Every \(current.interval) \(unitName(current))")
                    }
                    Picker("Unit", selection: unit) {
                        ForEach(Recurrence.Unit.allCases, id: \.self) { Text($0.rawValue.capitalized + "s").tag($0) }
                    }
                    if current.unit == .week { weekdayPicker(current) }
                    if current.unit == .month {
                        Stepper(value: dayOfMonth, in: 1...31) {
                            Text("On day \(current.dayOfMonth ?? Day.ymd(due).day) of the month")
                        }
                    }
                    Picker("Repeats", selection: mode) {
                        Text("On a schedule").tag(Recurrence.Mode.fixed)
                        Text("After I finish it").tag(Recurrence.Mode.afterCompletion)
                    }
                    Toggle("Ends", isOn: ends)
                    if current.until != nil {
                        DatePicker("Last day", selection: untilDate, displayedComponents: .date)
                    }
                }

                Section {
                    ForEach(previewDays(current), id: \.self) { day in
                        Text(Day.date(for: day).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    }
                } header: { Text("Next dates") } footer: {
                    if current.mode == .afterCompletion {
                        Text("The next date is counted from the day you finish it, so these are only a guide.")
                    }
                }
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Helpers

    private func isSelected(_ preset: Recurrence?) -> Bool {
        guard let preset else { return rule == nil }
        guard let rule else { return false }
        return rule.unit == preset.unit && rule.interval == preset.interval && rule.weekdays == preset.weekdays
            && rule.mode == .fixed && rule.until == nil
    }

    private func unitName(_ rule: Recurrence) -> String {
        rule.interval == 1 ? rule.unit.rawValue : rule.unit.rawValue + "s"
    }

    private func previewDays(_ rule: Recurrence) -> [Int] {
        rule.anchored(to: due).occurrences(startingAt: due, count: 5, firstWeekday: Calendar.current.firstWeekday)
    }

    private func update(_ change: (inout Recurrence) -> Void) {
        guard var copy = rule else { return }
        change(&copy)
        rule = copy
    }

    private var interval: Binding<Int> {
        Binding(get: { rule?.interval ?? 1 }, set: { value in update { $0.interval = max(1, value) } })
    }

    private var unit: Binding<Recurrence.Unit> {
        Binding(get: { rule?.unit ?? .day }, set: { value in
            update {
                $0.unit = value
                if value != .week { $0.weekdays = [] }
                if value != .month, value != .year { $0.dayOfMonth = nil }
                if value != .year { $0.month = nil }
            }
        })
    }

    private var mode: Binding<Recurrence.Mode> {
        Binding(get: { rule?.mode ?? .fixed }, set: { value in update { $0.mode = value } })
    }

    private var dayOfMonth: Binding<Int> {
        Binding(get: { rule?.dayOfMonth ?? Day.ymd(due).day }, set: { value in update { $0.dayOfMonth = value } })
    }

    private var ends: Binding<Bool> {
        Binding(get: { rule?.until != nil }, set: { on in update { $0.until = on ? due + 90 : nil } })
    }

    private var untilDate: Binding<Date> {
        Binding(get: { Day.date(for: rule?.until ?? due) }, set: { date in update { $0.until = Day.key(for: date) } })
    }

    private func weekdayPicker(_ current: Recurrence) -> some View {
        let firstWeekday = Calendar.current.firstWeekday
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let names = Calendar.current.standaloneWeekdaySymbols
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(0..<7, id: \.self) { offset in
                    let weekday = (firstWeekday - 1 + offset) % 7 + 1
                    let on = current.weekdays.contains(weekday)
                    Button {
                        update { if on { $0.weekdays.remove(weekday) } else { $0.weekdays.insert(weekday) } }
                    } label: {
                        Text(symbols[weekday - 1])
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(names[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if current.weekdays.isEmpty {
                Text("No days picked: it repeats on the same weekday as the due date.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
