import SwiftUI
import SwiftData
import HeedCore

// MARK: - List editor

struct ListEditor: View {
    let list: TodoList?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @State private var name = ""
    @State private var symbol = "list.bullet"
    @State private var colorIndex = 0
    @State private var confirmDelete = false

    private static let symbols = ["list.bullet", "house", "briefcase", "cart", "heart", "book", "airplane", "gift", "star",
                                  "graduationcap", "dumbbell", "fork.knife", "leaf", "wrench.and.screwdriver", "creditcard", "pawprint"]

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name).textInputAutocapitalization(.words) }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { candidate in
                            Button { symbol = candidate } label: {
                                Image(systemName: candidate)
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(symbol == candidate ? Color.white : Color.primary)
                                    .background(symbol == candidate ? HeedPalette.color(colorIndex) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Colour") {
                    HStack {
                        ForEach(0..<HeedPalette.colors.count, id: \.self) { index in
                            Button { colorIndex = index } label: {
                                Circle().fill(HeedPalette.color(index)).frame(width: 30, height: 30)
                                    .overlay { if colorIndex == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                if list != nil {
                    Section {
                        Button("Delete list", role: .destructive) { confirmDelete = true }
                    } footer: { Text("Its tasks move to your Inbox. Nothing is deleted.") }
                }
            }
            .navigationTitle(list == nil ? "New list" : "Edit list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this list?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete list", role: .destructive, action: deleteList)
            } message: { Text("Its tasks move to your Inbox.") }
            .onAppear {
                if let list { name = list.name; symbol = list.symbol; colorIndex = list.colorIndex } else { colorIndex = lists.count }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let list {
            list.name = trimmed
            list.symbol = symbol
            list.colorIndex = colorIndex
            list.modifiedAt = .now
        } else {
            context.insert(TodoList(name: trimmed, symbol: symbol, colorIndex: colorIndex, sortOrder: (lists.map(\.sortOrder).max() ?? -1) + 1))
        }
        TaskActions.commit(context)
        dismiss()
    }

    private func deleteList() {
        guard let list else { return }
        let id = list.id
        let members = (try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.listID == id }))) ?? []
        for item in members { item.listID = nil; item.touch() }
        context.delete(list)
        TaskActions.commit(context)
        dismiss()
    }
}

// MARK: - Filter editor

struct FilterEditor: View {
    let saved: SavedFilter?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt == nil }) private var items: [TodoItem]
    @Query(sort: [SortDescriptor(\SavedFilter.sortOrder)]) private var filters: [SavedFilter]
    @State private var name = ""
    @State private var filter = TaskFilter()
    @State private var includeTags = ""
    @State private var excludeTags = ""
    @State private var confirmDelete = false

    var body: some View {
        let current = built
        let matches = items.filter { current.matches($0.summary, today: app.today) }.count
        NavigationStack {
            Form {
                Section { TextField("Name, for example “Work, not waiting”", text: $name) }

                if !lists.isEmpty {
                    Section("Lists (any of)") {
                        ForEach(lists) { list in
                            Button {
                                if filter.listIDs.contains(list.id) { filter.listIDs.remove(list.id) } else { filter.listIDs.insert(list.id) }
                            } label: {
                                HStack {
                                    Image(systemName: list.symbol).foregroundStyle(HeedPalette.color(list.colorIndex)).frame(width: 26)
                                    Text(list.name).foregroundStyle(.primary)
                                    Spacer()
                                    if filter.listIDs.contains(list.id) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Has any of these tags", text: $includeTags).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Does not have these tags", text: $excludeTags).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Tags") } footer: { Text("Separate tags with commas or spaces. Leave the @ off.") }

                Section("Priority and date") {
                    Picker("At least", selection: $filter.minimumPriority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0 == .none ? "Any priority" : $0.label).tag($0) }
                    }
                    Picker("Due", selection: $filter.due) {
                        ForEach(TaskFilter.Due.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Include completed tasks", isOn: $filter.includeCompleted)
                }

                Section { Label("\(matches) \(matches == 1 ? "task matches" : "tasks match") right now", systemImage: "line.3.horizontal.decrease") }

                if saved != nil {
                    Section { Button("Delete filter", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(saved == nil ? "New filter" : "Edit filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this filter?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete filter", role: .destructive) {
                    if let saved { context.delete(saved); try? context.save() }
                    dismiss()
                }
            } message: { Text("Your tasks are not affected.") }
            .onAppear {
                guard let saved else { return }
                name = saved.name
                filter = saved.filter
                includeTags = filter.anyTags.sorted().joined(separator: ", ")
                excludeTags = filter.excludedTags.sorted().joined(separator: ", ")
            }
        }
    }

    /// The filter as currently edited, with the tag text folded in.
    private var built: TaskFilter {
        var copy = filter
        copy.anyTags = Set(Self.tags(from: includeTags))
        copy.excludedTags = Set(Self.tags(from: excludeTags))
        return copy
    }

    static func tags(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@# ")).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let saved {
            saved.name = trimmed
            saved.filter = built
            saved.modifiedAt = .now
        } else {
            context.insert(SavedFilter(name: trimmed, filter: built, sortOrder: (filters.map(\.sortOrder).max() ?? -1) + 1))
        }
        try? context.save()
        dismiss()
    }
}
