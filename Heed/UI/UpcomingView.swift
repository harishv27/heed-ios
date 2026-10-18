import SwiftUI
import SwiftData
import HeedCore

/// The week ahead as a list, or the whole month as a calendar. The month view is free and always was.
struct UpcomingView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }, sort: [SortDescriptor(\TodoItem.sortOrder)]) private var items: [TodoItem]
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @State private var mode: Mode = .list
    @State private var selectedDay: Int?
    @State private var visibleMonth: Int?

    enum Mode: String, CaseIterable { case list = "List", month = "Month" }

    var body: some View {
        let today = app.today
        NavigationStack {
            Group {
                switch mode {
                case .list: listView(today: today)
                case .month: monthView(today: today)
                }
            }
            .navigationTitle("Upcoming")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .floatingChrome()
        }
    }

    // MARK: List

    private func listView(today: Int) -> some View {
        let byID = items.byID
        let listsByID = lists.byID
        let (groups, later) = Planning.upcoming(items.map(\.summary), today: today, horizon: 14)
        return List {
            if groups.isEmpty && later.isEmpty {
                ContentUnavailableView("Nothing coming up", systemImage: "calendar",
                                       description: Text("Tasks with a future date appear here, grouped by day."))
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.day) { group in
                Section(header: dayHeader(group.day, today: today)) {
                    ForEach(group.tasks) { task in
                        if let item = byID[task.id] { TaskRow(item: item, lists: listsByID, showDate: false) }
                    }
                }
            }
            if !later.isEmpty {
                Section("Later") {
                    ForEach(later) { task in
                        if let item = byID[task.id] { TaskRow(item: item, lists: listsByID) }
                    }
                }
            }
        }
    }

    private func dayHeader(_ day: Int, today: Int) -> some View {
        let date = Day.date(for: day)
        let relative = DateText.day(day, today: today)
        let full = date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return HStack {
            Text(relative == full || (day - today) >= 7 ? full : relative).fontWeight(.semibold)
            if (day - today) < 7 { Text(date.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(.secondary) }
        }
    }

    // MARK: Month

    private func monthView(today: Int) -> some View {
        let byID = items.byID
        let listsByID = lists.byID
        let summaries = items.map(\.summary)
        let counts = Planning.openCountByDay(summaries)
        let month = visibleMonth ?? Day.monthStart(of: today)
        let selected = selectedDay ?? today
        let dayTasks = Planning.ordered(summaries.filter { !$0.isCompleted && $0.dueDay == selected })

        return List {
            Section {
                MonthCalendar(month: month, today: today, selected: selected, counts: counts,
                              onSelect: { selectedDay = $0 },
                              onMove: { delta in visibleMonth = Day.adding(months: delta, to: month, aimingFor: 1) },
                              onToday: { visibleMonth = nil; selectedDay = nil })
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            Section(DateText.day(selected, today: today) + " · " + Day.date(for: selected).formatted(.dateTime.day().month(.abbreviated))) {
                if dayTasks.isEmpty {
                    Text("Nothing on this day").foregroundStyle(.secondary)
                }
                ForEach(dayTasks) { task in
                    if let item = byID[task.id] { TaskRow(item: item, lists: listsByID, showDate: false) }
                }
            }
        }
    }
}

/// A month grid with a dot (or a count) under days that have open tasks.
struct MonthCalendar: View {
    let month: Int
    let today: Int
    let selected: Int
    let counts: [Int: Int]
    let onSelect: (Int) -> Void
    let onMove: (Int) -> Void
    let onToday: () -> Void

    var body: some View {
        let parts = Day.ymd(month)
        let firstWeekday = Calendar.current.firstWeekday
        let weeks = MonthGrid.weeks(year: parts.year, month: parts.month, firstWeekday: firstWeekday)
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { symbols[(firstWeekday - 1 + $0) % 7] }

        VStack(spacing: 8) {
            HStack {
                Text(Day.date(for: month).formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Today", action: onToday).font(.footnote.weight(.semibold))
                Button { onMove(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Button { onMove(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.day) { cell in
                        dayCell(cell)
                    }
                }
            }
        }
    }

    private func dayCell(_ cell: MonthCell) -> some View {
        let number = Day.ymd(cell.day).day
        let isSelected = cell.day == selected
        let isToday = cell.day == today
        let count = counts[cell.day] ?? 0
        return Button { onSelect(cell.day) } label: {
            VStack(spacing: 3) {
                Text("\(number)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : (cell.inMonth ? Color.primary : Color.secondary.opacity(0.5))))
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                Circle()
                    .fill(count > 0 ? (cell.day < today ? Color.red : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Day.date(for: cell.day).formatted(.dateTime.weekday(.wide).day().month(.wide)) + (count > 0 ? ", \(count) tasks" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
