import SwiftUI
import SwiftData
import HeedCore

enum ListDestination: Hashable {
    case inbox, all, logbook
    case list(UUID)
    case saved(UUID)
    case preset(String)
    case tag(String)
}

struct ListsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }) private var items: [TodoItem]
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @Query(sort: [SortDescriptor(\SavedFilter.sortOrder)]) private var filters: [SavedFilter]
    @State private var search = ""
    @State private var newList = false
    @State private var newFilter = false
    @State private var editingList: TodoList?
    @State private var editingFilter: SavedFilter?

    var body: some View {
        let today = app.today
        let open = items.filter { !$0.isCompleted }
        let listsByID = lists.byID
        let tags = Dictionary(grouping: open.flatMap(\.tags), by: { $0.lowercased() })
            .map { (name: $0.value.first ?? $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        NavigationStack {
            List {
                if !search.isEmpty {
                    searchResults(listsByID: listsByID)
                } else {
                    Section {
                        row("Inbox", symbol: "tray", color: .accentColor, count: open.filter { $0.listID == nil }.count, to: .inbox)
                        row("All tasks", symbol: "square.stack", color: .gray, count: open.count, to: .all)
                        row("Logbook", symbol: "checkmark.circle", color: .green, count: nil, to: .logbook)
                    }

                    Section("Lists") {
                        ForEach(lists) { list in
                            row(list.name, symbol: list.symbol, color: HeedPalette.color(list.colorIndex),
                                count: open.filter { $0.listID == list.id }.count, to: .list(list.id))
                                .swipeActions(edge: .trailing) {
                                    Button { editingList = list } label: { Label("Edit", systemImage: "pencil") }.tint(.indigo)
                                }
                        }
                        Button { newList = true } label: { Label("New list", systemImage: "plus") }
                    }

                    Section("Filters") {
                        ForEach(TaskFilter.presets) { preset in
                            row(preset.name, symbol: preset.symbol, color: .secondary,
                                count: open.filter { preset.filter.matches($0.summary, today: today) }.count, to: .preset(preset.name))
                        }
                        ForEach(filters) { saved in
                            row(saved.name, symbol: saved.symbol, color: .indigo,
                                count: open.filter { saved.filter.matches($0.summary, today: today) }.count, to: .saved(saved.id))
                                .swipeActions(edge: .trailing) {
                                    Button { editingFilter = saved } label: { Label("Edit", systemImage: "pencil") }.tint(.indigo)
                                }
                        }
                        Button { newFilter = true } label: { Label("New filter", systemImage: "plus") }
                    }

                    if !tags.isEmpty {
                        Section("Tags") {
                            ForEach(tags, id: \.name) { tag in
                                row("@\(tag.name)", symbol: "tag", color: .secondary, count: tag.count, to: .tag(tag.name))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationDestination(for: ListDestination.self) { TaskListScreen(destination: $0) }
            .searchable(text: $search, prompt: "Search tasks")
            .floatingChrome()
            .sheet(isPresented: $newList) { ListEditor(list: nil) }
            .sheet(item: $editingList) { ListEditor(list: $0) }
            .sheet(isPresented: $newFilter) { FilterEditor(saved: nil) }
            .sheet(item: $editingFilter) { FilterEditor(saved: $0) }
        }
    }

    private func row(_ title: String, symbol: String, color: Color, count: Int?, to destination: ListDestination) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 28)
                Text(title)
                Spacer()
                if let count, count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
        }
    }

    @ViewBuilder
    private func searchResults(listsByID: [UUID: TodoList]) -> some View {
        let results = Planning.ordered(items.map(\.summary).filter { Planning.matches($0, query: search) })
        let byID = items.byID
        if results.isEmpty {
            ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
        } else {
            Section("\(results.count) found") {
                ForEach(results) { task in
                    if let item = byID[task.id] { TaskRow(item: item, lists: listsByID) }
                }
            }
        }
    }
}

// MARK: - A list, filter, tag or the logbook

struct TaskListScreen: View {
    let destination: ListDestination

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }, sort: \TodoItem.sortOrder) private var items: [TodoItem]
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @Query(sort: [SortDescriptor(\SavedFilter.sortOrder)]) private var filters: [SavedFilter]
    @State private var showCompleted = false
    @State private var editingList: TodoList?
    @State private var editingFilter: SavedFilter?

    var body: some View {
        let today = app.today
        let listsByID = lists.byID
        let scoped = items.filter { include($0, today: today) }
        let open = scoped.filter { !$0.isCompleted }
        let done = scoped.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        List {
            if destination == .logbook {
                logbook(done: done, listsByID: listsByID)
            } else {
                openSection(open: open, listsByID: listsByID)
                completedSection(done: done, listsByID: listsByID)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { trailingMenu } }
        .floatingChrome(list: quickAddList)
        .sheet(item: $editingList) { ListEditor(list: $0) }
        .sheet(item: $editingFilter) { FilterEditor(saved: $0) }
    }

    /// Open tasks: in the user's own order for the Inbox and lists (draggable), by time and priority elsewhere.
    private func orderedOpen(_ open: [TodoItem]) -> [TodoItem] {
        if manualOrder { return open }
        let byID = open.byID
        return Planning.ordered(open.map(\.summary)).compactMap { byID[$0.id] }
    }

    @ViewBuilder
    private func openSection(open: [TodoItem], listsByID: [UUID: TodoList]) -> some View {
        let ordered = orderedOpen(open)
        Section {
            if open.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray", description: Text(emptyText))
                    .listRowBackground(Color.clear)
            }
            ForEach(ordered) { item in
                TaskRow(item: item, lists: listsByID, showList: !isList)
            }
            .onMove { source, target in
                guard manualOrder else { return }
                var moved = ordered
                moved.move(fromOffsets: source, toOffset: target)
                TaskActions.applyOrder(moved, in: context)
            }
            .moveDisabled(!manualOrder)
        }
    }

    @ViewBuilder
    private func completedSection(done: [TodoItem], listsByID: [UUID: TodoList]) -> some View {
        if !done.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showCompleted) {
                    ForEach(done.prefix(50)) { item in TaskRow(item: item, lists: listsByID, showList: !isList) }
                } label: {
                    Label("Completed · \(done.count)", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: What this screen shows

    private var isList: Bool { if case .list = destination { return true } else { return false } }

    /// Inbox and lists keep a manual order the user can drag; the rest sort by time and priority.
    private var manualOrder: Bool {
        switch destination {
        case .inbox, .list: return true
        default: return false
        }
    }

    private var quickAddList: UUID? { if case .list(let id) = destination { return id } else { return nil } }

    private func include(_ item: TodoItem, today: Int) -> Bool {
        switch destination {
        case .inbox: return item.listID == nil
        case .all: return true
        case .logbook: return item.isCompleted
        case .list(let id): return item.listID == id
        case .saved(let id): return filters.first { $0.id == id }?.filter.matches(item.summary, today: today) ?? false
        case .preset(let name): return TaskFilter.presets.first { $0.name == name }?.filter.matches(item.summary, today: today) ?? false
        case .tag(let name): return item.tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private var title: String {
        switch destination {
        case .inbox: return "Inbox"
        case .all: return "All tasks"
        case .logbook: return "Logbook"
        case .list(let id): return lists.first { $0.id == id }?.name ?? "List"
        case .saved(let id): return filters.first { $0.id == id }?.name ?? "Filter"
        case .preset(let name): return name
        case .tag(let name): return "@\(name)"
        }
    }

    private var emptyText: String {
        switch destination {
        case .inbox: return "Everything you add without a list lands here."
        case .saved, .preset: return "No open tasks match this filter."
        default: return "Add a task with the + button."
        }
    }

    @ViewBuilder
    private var trailingMenu: some View {
        switch destination {
        case .list(let id):
            if let list = lists.first(where: { $0.id == id }) {
                Menu {
                    Button { editingList = list } label: { Label("Edit list", systemImage: "pencil") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        case .saved(let id):
            if let saved = filters.first(where: { $0.id == id }) {
                Menu {
                    Button { editingFilter = saved } label: { Label("Edit filter", systemImage: "pencil") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        default:
            EmptyView()
        }
        if manualOrder { EditButton() }
    }

    @ViewBuilder
    private func logbook(done: [TodoItem], listsByID: [UUID: TodoList]) -> some View {
        if done.isEmpty {
            ContentUnavailableView("No finished tasks yet", systemImage: "checkmark.circle",
                                   description: Text("Tasks you complete are kept here."))
                .listRowBackground(Color.clear)
        }
        let grouped = Dictionary(grouping: done) { Day.key(for: $0.completedAt ?? .now) }
        ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
            Section(DateText.day(day, today: app.today)) {
                ForEach(grouped[day] ?? []) { item in TaskRow(item: item, lists: listsByID, showDate: false) }
            }
        }
    }
}
