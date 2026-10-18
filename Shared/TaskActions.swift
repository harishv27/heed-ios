import Foundation
import SwiftData
import HeedCore

/// Something the user just did that can be taken back. The app shows it as a banner with an Undo button.
struct UndoAction {
    let message: String
    let revert: () -> Void
}

/// Every change to a task goes through here, so each one saves, refreshes the widget and re-plans the reminders the
/// same way. That is what keeps a completed task from still buzzing your phone.
enum TaskActions {
    static var today: Int { Day.key(for: .now) }

    /// Saves, then refreshes the widget and re-plans reminders.
    static func commit(_ context: ModelContext) {
        try? context.save()
        SharedStore.reloadWidgets()
        Task { await Reminders.syncAll() }
    }

    // MARK: Completing

    @discardableResult
    static func complete(_ item: TodoItem, in context: ModelContext, today: Int = TaskActions.today) -> UndoAction {
        let before = (due: item.dueDay, completedAt: item.completedAt, lastDone: item.lastDoneAt, checklist: item.checklistData,
                      times: item.timesCompleted, modified: item.modifiedAt)
        let outcome = Completion.complete(due: item.dueDay, recurrence: item.recurrence, today: today,
                                          firstWeekday: Calendar.current.firstWeekday)
        let message: String
        switch outcome {
        case .finished:
            item.completedAt = .now
            message = "Completed"
        case .advanced(let next):
            item.dueDay = next
            item.lastDoneAt = .now
            // A repeating task starts its next round with a clean checklist.
            item.checklist = item.checklist.map { ChecklistItem(id: $0.id, title: $0.title, done: false) }
            message = "Done · next \(DateText.day(next, today: today))"
        }
        item.timesCompleted += 1
        item.touch()
        commit(context)
        return UndoAction(message: message) {
            item.dueDay = before.due
            item.completedAt = before.completedAt
            item.lastDoneAt = before.lastDone
            item.checklistData = before.checklist
            item.timesCompleted = before.times
            item.modifiedAt = before.modified
            commit(context)
        }
    }

    static func reopen(_ item: TodoItem, in context: ModelContext) {
        item.completedAt = nil
        item.touch()
        commit(context)
    }

    /// Ticks an open task or reopens a finished one. Returns an undo for ticking.
    @discardableResult
    static func toggle(_ item: TodoItem, in context: ModelContext) -> UndoAction? {
        if item.isCompleted {
            reopen(item, in: context)
            return nil
        }
        return complete(item, in: context)
    }

    // MARK: Trash

    @discardableResult
    static func trash(_ item: TodoItem, in context: ModelContext) -> UndoAction {
        item.deletedAt = .now
        item.touch()
        commit(context)
        return UndoAction(message: "Moved to Trash") {
            item.deletedAt = nil
            item.touch()
            commit(context)
        }
    }

    static func restore(_ item: TodoItem, in context: ModelContext) {
        item.deletedAt = nil
        item.touch()
        commit(context)
    }

    /// Permanent. Only reachable from the Trash screen, behind a confirmation, or after the 30 days are up.
    static func deleteForever(_ items: [TodoItem], in context: ModelContext) {
        for item in items { context.delete(item) }
        commit(context)
    }

    static func purgeExpiredTrash(in context: ModelContext) {
        let trashed = (try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        let expired = trashed.filter { $0.deletedAt.map { Trash.isExpired(deletedAt: $0) } ?? false }
        if !expired.isEmpty { deleteForever(expired, in: context) }
    }

    // MARK: Scheduling

    @discardableResult
    static func reschedule(_ item: TodoItem, to day: Int?, in context: ModelContext) -> UndoAction {
        let before = (item.dueDay, item.modifiedAt)
        item.dueDay = day
        // Moving a task out of "someday" or away from a date should not leave a time hanging off nothing.
        if day == nil { item.dueMinutes = nil }
        item.touch()
        commit(context)
        let label = day.map { DateText.day($0, today: today) } ?? "no date"
        return UndoAction(message: "Moved to \(label)") {
            item.dueDay = before.0
            item.modifiedAt = before.1
            commit(context)
        }
    }

    // MARK: Creating

    /// Adds a task from the quick-add line. A `#list` that does not exist yet is created.
    @discardableResult
    static func add(_ parsed: ParsedTask, in context: ModelContext, defaultList: UUID? = nil) -> TodoItem {
        var listID = defaultList
        if let name = parsed.listName {
            let lists = (try? context.fetch(FetchDescriptor<TodoList>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
            if let match = lists.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                listID = match.id
            } else {
                let list = TodoList(name: name, colorIndex: lists.count, sortOrder: (lists.map(\.sortOrder).max() ?? -1) + 1)
                context.insert(list)
                listID = list.id
            }
        }
        var newest = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        newest.fetchLimit = 1
        let order = ((try? context.fetch(newest))?.first?.sortOrder ?? -1) + 1

        let item = TodoItem(title: parsed.title, dueDay: parsed.dueDay, dueMinutes: parsed.minutes, recurrence: parsed.recurrence,
                            priority: parsed.priority, listID: listID, tags: parsed.tags,
                            reminderLead: parsed.minutes != nil ? 0 : nil, sortOrder: order)
        context.insert(item)
        commit(context)
        return item
    }

    // MARK: Ordering

    /// Rewrites `sortOrder` to match the given order, after the user drags rows.
    static func applyOrder(_ items: [TodoItem], in context: ModelContext) {
        for (index, item) in items.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.touch()
        }
        try? context.save()
    }
}
