import Foundation
@testable import HeedCore

/// Shared fixtures. The pretend "now" is Wednesday 14 October 2026, 10:00, with weeks starting on Monday.
///
///     Mon 12  Tue 13  Wed 14  Thu 15  Fri 16  Sat 17  Sun 18  Mon 19 ... Mon 26
enum T {
    static func calendar(_ id: String = "UTC", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: id)!
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static let utc = calendar()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = utc) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func key(_ year: Int, _ month: Int, _ day: Int) -> Int { Day.key(year: year, month: month, day: day) }

    static let now = date(2026, 10, 14, 10, 0)
    static let today = key(2026, 10, 14)

    /// A day by its date in October 2026.
    static func oct(_ day: Int) -> Int { key(2026, 10, day) }

    static func task(_ title: String, due: Int? = nil, minutes: Int? = nil, priority: Priority = .none, list: UUID? = nil,
                     tags: [String] = [], order: Int = 0, created: TimeInterval = 0, done: Int? = nil,
                     recurrence: Recurrence? = nil, notes: String = "", checklist: [ChecklistItem] = []) -> TaskSummary {
        TaskSummary(title: title, notes: notes, dueDay: due, dueMinutes: minutes, recurrence: recurrence, priority: priority,
                    listID: list, tags: tags, checklist: checklist, sortOrder: order, createdAt: created, completedDay: done)
    }
}
