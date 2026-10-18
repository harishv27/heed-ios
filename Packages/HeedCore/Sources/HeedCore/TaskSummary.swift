import Foundation

/// A task reduced to plain values. The app maps its SwiftData rows to these so that sorting, filtering, searching and
/// planning can be tested without a database, and so a widget can carry a handful of them cheaply.
public struct TaskSummary: Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueDay: Int?
    /// Minutes after midnight, when the task has a time.
    public var dueMinutes: Int?
    public var recurrence: Recurrence?
    public var priority: Priority
    public var listID: UUID?
    public var tags: [String]
    public var checklist: [ChecklistItem]
    public var sortOrder: Int
    /// Seconds since 1970; only used to break ties.
    public var createdAt: TimeInterval
    /// The day key a one-off task was ticked off, or nil while it is open.
    public var completedDay: Int?
    /// For a repeating task: the day key it was last ticked off. It has already moved on to its next date, but still
    /// counts towards "done today".
    public var lastDoneDay: Int?

    public init(id: UUID = UUID(), title: String, notes: String = "", dueDay: Int? = nil, dueMinutes: Int? = nil,
                recurrence: Recurrence? = nil, priority: Priority = .none, listID: UUID? = nil, tags: [String] = [],
                checklist: [ChecklistItem] = [], sortOrder: Int = 0, createdAt: TimeInterval = 0, completedDay: Int? = nil,
                lastDoneDay: Int? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.recurrence = recurrence
        self.priority = priority
        self.listID = listID
        self.tags = tags
        self.checklist = checklist
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedDay = completedDay
        self.lastDoneDay = lastDoneDay
    }

    public var isCompleted: Bool { completedDay != nil }
}

/// A step inside a task.
public struct ChecklistItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var done: Bool

    public init(id: UUID = UUID(), title: String, done: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
    }
}

public enum Checklist {
    public static func encode(_ items: [ChecklistItem]) -> Data { (try? JSONEncoder().encode(items)) ?? Data() }

    public static func decode(_ data: Data) -> [ChecklistItem] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
    }

    /// "2 of 5", or nil when there are no steps.
    public static func progress(_ items: [ChecklistItem]) -> (done: Int, total: Int)? {
        items.isEmpty ? nil : (items.filter(\.done).count, items.count)
    }
}
