import SwiftUI
import SwiftData
import HeedCore

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }, sort: [SortDescriptor(\TodoItem.sortOrder)]) private var items: [TodoItem]
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @State private var showDone = false

    var body: some View {
        let today = app.today
        let byID = items.byID
        let listsByID = lists.byID
        let plan = Planning.dayPlan(items.map(\.summary), today: today)

        NavigationStack {
            List {
                Section { header(plan: plan, today: today) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))

                if !plan.overdue.isEmpty {
                    Section {
                        ForEach(plan.overdue) { task in
                            if let item = byID[task.id] { TaskRow(item: item, lists: listsByID) }
                        }
                    } header: {
                        HStack {
                            Label("Overdue", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                            Spacer()
                            Button("Plan my day") { app.showTriage = true }
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }

                if !plan.today.isEmpty {
                    Section(plan.overdue.isEmpty ? "" : "Today") {
                        ForEach(plan.today) { task in
                            if let item = byID[task.id] { TaskRow(item: item, lists: listsByID, showDate: false) }
                        }
                    }
                }

                if plan.openCount == 0 {
                    Section {
                        ContentUnavailableView {
                            Label(plan.doneToday.isEmpty ? "Nothing planned" : "All done for today", systemImage: plan.doneToday.isEmpty ? "sun.max" : "checkmark.seal")
                        } description: {
                            Text(plan.doneToday.isEmpty ? "Add something with the + button. Try “call mum tomorrow 6pm”." : "Nice. Anything new will show up here.")
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if !plan.doneToday.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showDone) {
                            ForEach(plan.doneToday) { task in
                                if let item = byID[task.id] {
                                    TaskRow(item: item, lists: listsByID, showDate: false, doneToday: !item.isCompleted)
                                }
                            }
                        } label: {
                            Label("Done today · \(plan.doneToday.count)", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .floatingChrome()
        }
    }

    private func header(plan: DayPlan, today: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Day.date(for: today).longDay).font(.subheadline).foregroundStyle(.secondary)
            if plan.totalToday > 0 {
                let done = plan.doneToday.count
                HStack(spacing: 12) {
                    ProgressView(value: Double(done), total: Double(max(plan.totalToday, 1)))
                        .tint(.accentColor)
                    Text("\(done) of \(plan.totalToday) done").font(.subheadline.weight(.medium)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
        // Room above the first line: iOS 26 fades list content just under the large title, which clipped the "F".
        .padding(.top, 10)
    }
}
