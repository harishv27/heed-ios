import Foundation
import SwiftData
import HeedCore

/// One task. Shared by the app, the widget and Shortcuts.
///
/// Every property has a default and nothing is unique-constrained, which keeps the schema compatible with CloudKit
/// sync if it is switched on (see the README). Lists are referenced by id rather than a relationship, so deleting a
/// list can never cascade into deleting tasks.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Day key (see `Day`), or nil for "someday".
    var dueDay: Int?
    /// Minutes after midnight, or nil when the task only has a date.
    var dueMinutes: Int?
    var recurrenceData: Data?
    var priorityRaw: Int = 0
    var listID: UUID?
    var tags: [String] = []
    var checklistData: Data = Data()
    /// Minutes before the due moment to remind, or nil for no reminder. 0 means at the due time (or at the default
    /// time of day for a date-only task).
    var reminderLead: Int?
    var sortOrder: Int = 0
    /// How many times a repeating task has been ticked off.
    var timesCompleted: Int = 0
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now
    var completedAt: Date?
    /// For a repeating task: when it was last ticked off (it has moved on to its next date).
    var lastDoneAt: Date?
    /// Set when moved to Trash. The task stays recoverable until `Trash.retentionDays` have passed.
    var deletedAt: Date?

    init(title: String, dueDay: Int? = nil, dueMinutes: Int? = nil, recurrence: Recurrence? = nil, priority: Priority = .none,
         listID: UUID? = nil, tags: [String] = [], reminderLead: Int? = nil, sortOrder: Int = 0) {
        self.title = title
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.recurrenceData = recurrence?.encoded
        self.priorityRaw = priority.rawValue
        self.listID = listID
        self.tags = tags
        self.reminderLead = reminderLead
        self.sortOrder = sortOrder
    }
}

extension TodoItem {
    var recurrence: Recurrence? {
        get { Recurrence.decode(recurrenceData) }
        set { recurrenceData = newValue?.encoded }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var checklist: [ChecklistItem] {
        get { Checklist.decode(checklistData) }
        set { checklistData = Checklist.encode(newValue) }
    }

    var isCompleted: Bool { completedAt != nil }
    var isTrashed: Bool { deletedAt != nil }

    func touch() { modifiedAt = .now }

    /// The plain-value copy the planning, filtering and reminder logic works on.
    var summary: TaskSummary {
        TaskSummary(id: id, title: title, notes: notes, dueDay: dueDay, dueMinutes: dueMinutes, recurrence: recurrence,
                    priority: priority, listID: listID, tags: tags, checklist: checklist, sortOrder: sortOrder,
                    createdAt: createdAt.timeIntervalSince1970, completedDay: completedAt.map { Day.key(for: $0) },
                    lastDoneDay: lastDoneAt.map { Day.key(for: $0) })
    }

    var reminderSource: ReminderSource {
        ReminderSource(id: id, title: title, dueDay: dueDay, dueMinutes: dueMinutes, recurrence: recurrence, leadMinutes: reminderLead)
    }
}

/// A list of tasks. Tasks with no list are in the Inbox.
@Model
final class TodoList {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol name.
    var symbol: String = "list.bullet"
    /// Index into `HeedPalette`.
    var colorIndex: Int = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    init(name: String, symbol: String = "list.bullet", colorIndex: Int = 0, sortOrder: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
    }
}

/// A saved filter, stored as its encoded `TaskFilter`.
@Model
final class SavedFilter {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "line.3.horizontal.decrease"
    var filterData: Data = Data()
    var sortOrder: Int = 0
    var modifiedAt: Date = Date.now

    init(name: String, symbol: String = "line.3.horizontal.decrease", filter: TaskFilter, sortOrder: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.filterData = filter.encoded
        self.sortOrder = sortOrder
    }

    var filter: TaskFilter {
        get { TaskFilter.decode(filterData) }
        set { filterData = newValue.encoded }
    }
}
