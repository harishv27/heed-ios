import Foundation
import SwiftData
import HeedCore

/// Sample lists and tasks for screenshots and trying the app. Debug builds only: runs when launched with `-seedDemo`
/// and only into an empty store, so it can never overwrite real tasks.
enum DemoData {
    @MainActor
    static func seedIfRequested(_ container: ModelContainer) async {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo") else { return }
        let context = container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<TodoItem>())) ?? 0) == 0 else { return }

        let today = TaskActions.today
        let calendar = Calendar.current

        let work = TodoList(name: "Work", symbol: "briefcase", colorIndex: 1, sortOrder: 0)
        let home = TodoList(name: "Home", symbol: "house", colorIndex: 3, sortOrder: 1)
        let health = TodoList(name: "Health", symbol: "heart", colorIndex: 5, sortOrder: 2)
        [work, home, health].forEach(context.insert)

        // (title, list, day offset, time, priority, repeat, tags, reminder, checklist, done)
        typealias Spec = (String, TodoList?, Int?, Int?, Priority, Recurrence?, [String], Int?, [String], Bool)
        let specs: [Spec] = [
            ("Send invoice to Acme", work, -3, nil, .high, nil, ["finance"], nil, [], false),
            ("Reply to Priya about the offsite", work, -1, nil, .medium, nil, ["email"], nil, [], false),
            ("Submit expense report", work, 0, 17 * 60, .high, .weekly, ["finance"], 0, [], false),
            ("Team standup", work, 0, 9 * 60 + 30, .none, .weekdaysOnly, [], 0, [], true),
            ("Prep slides for Thursday review", work, 0, nil, .medium, nil, [], nil, ["Outline", "Numbers from Q3", "Screenshots", "Rehearse"], false),
            ("Take vitamins", health, 0, 8 * 60, .none, .daily, [], 0, [], true),
            ("Call mum", home, 0, 18 * 60 + 30, .none, nil, ["phone"], 0, [], false),
            ("Water the plants", home, 0, nil, .low, Recurrence(unit: .day, interval: 3), [], nil, [], false),
            ("Book dentist", health, 1, 10 * 60, .none, nil, ["phone"], 15, [], false),
            ("Pay rent", home, 3, nil, .high, Recurrence(unit: .month, dayOfMonth: 1), ["bills"], 0, [], false),
            ("Gym", health, 2, 7 * 60, .none, Recurrence(unit: .week, weekdays: [2, 4, 6]), [], 0, [], false),
            ("Renew passport", nil, 9, nil, .medium, nil, ["admin"], 1440, ["Photos", "Form", "Payment"], false),
            ("Plan weekend hike", home, 4, nil, .none, nil, [], nil, [], false),
            ("Read “Four Thousand Weeks”", nil, nil, nil, .none, nil, [], nil, [], false),
            ("Fix the leaking tap", home, nil, nil, .low, nil, [], nil, [], false),
            ("Oil change", nil, 21, nil, .none, Recurrence(unit: .month, interval: 6, mode: .afterCompletion), [], nil, [], false),
        ]

        for (index, spec) in specs.enumerated() {
            let (title, list, offset, minutes, priority, rule, tags, lead, steps, done) = spec
            // A date that a rule would never produce (a Sunday for a Mon/Wed/Fri task) snaps to the rule's next day.
            let due = offset.map { rule?.firstOccurrence(onOrAfter: today + $0) ?? today + $0 }
            let item = TodoItem(title: title, dueDay: due, dueMinutes: minutes, recurrence: due.map { day in rule?.anchored(to: day) } ?? nil,
                                priority: priority, listID: list?.id, tags: tags, reminderLead: lead, sortOrder: index)
            item.checklist = steps.enumerated().map { ChecklistItem(title: $0.element, done: $0.offset == 0 && steps.count > 3) }
            item.createdAt = calendar.date(byAdding: .day, value: -(index % 6) - 1, to: .now) ?? .now
            if done { item.completedAt = .now }
            context.insert(item)
        }
        // One finished earlier in the week, one in the trash, so the Logbook and Trash screens have something to show.
        let earlier = TodoItem(title: "Book flights for March", listID: home.id, sortOrder: 90)
        earlier.completedAt = calendar.date(byAdding: .day, value: -2, to: .now)
        context.insert(earlier)
        let trashed = TodoItem(title: "Old idea: reorganise the garage", sortOrder: 91)
        trashed.deletedAt = calendar.date(byAdding: .day, value: -4, to: .now)
        context.insert(trashed)

        context.insert(SavedFilter(name: "Work, not email", symbol: "briefcase", filter: TaskFilter(listIDs: [work.id], excludedTags: ["email"]), sortOrder: 0))
        try? context.save()
        SharedStore.reloadWidgets()
        #endif
    }
}
