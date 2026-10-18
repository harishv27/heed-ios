import SwiftUI
import SwiftData
import HeedCore

/// "Plan my day": go through what slipped and decide, one tap each, instead of watching a red pile grow.
struct TriageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }, sort: [SortDescriptor(\TodoItem.sortOrder)]) private var items: [TodoItem]

    var body: some View {
        let today = app.today
        let byID = items.byID
        let overdue = Planning.dayPlan(items.map(\.summary), today: today).overdue

        NavigationStack {
            List {
                if overdue.isEmpty {
                    ContentUnavailableView("Nothing overdue", systemImage: "checkmark.seal",
                                           description: Text("You're on top of it. Go and do something good."))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        Button {
                            for task in overdue { if let item = byID[task.id] { TaskActions.reschedule(item, to: today, in: context) } }
                            Haptics.success()
                        } label: { Label("Move all \(overdue.count) to today", systemImage: "arrow.down.to.line") }
                    } footer: { Text("Or decide one by one. Nothing is deleted: Drop sends a task to the Trash for \(Trash.retentionDays) days.") }

                    ForEach(overdue) { task in
                        if let item = byID[task.id] { row(item, today: today) }
                    }
                }
            }
            .animation(.snappy, value: overdue.map(\.id))
            .navigationTitle("Plan your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
    }

    private func row(_ item: TodoItem, today: Int) -> some View {
        let late = today - (item.dueDay ?? today)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text(late == 1 ? "1 day overdue" : "\(late) days overdue").font(.caption).foregroundStyle(.red)
            }
            // A wrapping grid, so Done and Drop are always visible instead of hiding off the edge.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach([Reschedule.today, .tomorrow, .weekend, .nextWeek], id: \.self) { option in
                    Button {
                        TaskActions.reschedule(item, to: option.target(from: today, firstWeekday: Calendar.current.firstWeekday), in: context)
                        Haptics.tap()
                    } label: { Text(option.label).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                }
                Button { TaskActions.complete(item, in: context); Haptics.success() } label: {
                    Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.green)
                Button { TaskActions.trash(item, in: context); Haptics.tap() } label: {
                    Label("Drop", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
