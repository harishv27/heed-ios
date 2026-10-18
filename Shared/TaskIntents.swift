import AppIntents
import SwiftData
import HeedCore

/// A task as Shortcuts and Siri see it.
struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(_ item: TodoItem) { self.init(id: item.id, title: item.title) }
}

struct TaskQuery: EntityQuery, EntityStringQuery {
    private func openTasks(in context: ModelContext) throws -> [TodoItem] {
        let open = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.deletedAt == nil && $0.completedAt == nil }))
        return open.sorted { a, b in Planning.areInOrder(a.summary, b.summary) }
    }

    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        try openTasks(in: SharedStore.makeContext()).filter { identifiers.contains($0.id) }.map(TaskEntity.init)
    }

    func entities(matching string: String) async throws -> [TaskEntity] {
        try openTasks(in: SharedStore.makeContext()).filter { Planning.matches($0.summary, query: string) }.prefix(20).map(TaskEntity.init)
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        let today = TaskActions.today
        // Today and overdue first: that is what people ask Siri to tick off.
        let open = try openTasks(in: SharedStore.makeContext())
        let soon = open.filter { ($0.dueDay ?? .max) <= today }
        return (soon + open.filter { !soon.contains($0) }).prefix(25).map(TaskEntity.init)
    }
}

/// Ticks a task off. Used by the widget's checkboxes, by Shortcuts and by Siri.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete a task"
    static let description = IntentDescription("Marks a task as done. Repeating tasks move to their next date.")

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary { Summary("Complete \(\.$task)") }

    init() {}
    init(task: TaskEntity) { self.task = task }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SharedStore.makeContext()
        let id = task.id
        guard let item = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first else {
            return .result(dialog: "I couldn't find that task.")
        }
        if item.isCompleted { return .result(dialog: "\"\(item.title)\" is already done.") }
        let undo = TaskActions.complete(item, in: context)
        return .result(dialog: "\(undo.message): \(item.title).")
    }
}

/// "Add a task in Heed". Understands the same shorthand as the quick-add sheet ("pay rent friday 5pm every month").
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task"
    static let description = IntentDescription("Adds a task. You can include a date, a time, a repeat, a priority, #list and @tag.")

    @Parameter(title: "Task", requestValueDialog: "What should I add?") var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Heed") }

    init() {}
    init(text: String) { self.text = text }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = QuickAddParser.parse(text)
        guard !parsed.title.isEmpty else { return .result(dialog: "I didn't catch a task to add.") }
        let context = SharedStore.makeContext()
        TaskActions.add(parsed, in: context)
        if parsed.minutes != nil { await Reminders.requestAuthorizationIfNeeded() }
        let when = DateText.due(day: parsed.dueDay, minutes: parsed.minutes, today: TaskActions.today)
        return .result(dialog: when.map { "Added \"\(parsed.title)\" for \($0.lowercased())." } ?? "Added \"\(parsed.title)\" to your inbox.")
    }
}
