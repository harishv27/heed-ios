import Foundation

/// What belongs on the Today screen.
public struct DayPlan: Equatable, Sendable {
    /// Open tasks due before today, oldest first.
    public var overdue: [TaskSummary]
    /// Open tasks due today.
    public var today: [TaskSummary]
    /// Tasks finished today (one-off tasks, and repeating tasks that moved on to their next date), so a tick does not
    /// make a task vanish without a trace.
    public var doneToday: [TaskSummary]

    public var openCount: Int { overdue.count + today.count }
    /// Tasks that were on today's list, finished or not. The denominator for "3 of 8 done".
    public var totalToday: Int { today.count + doneToday.count }
    public var isEmpty: Bool { overdue.isEmpty && today.isEmpty && doneToday.isEmpty }
}

/// A day on the Upcoming screen.
public struct UpcomingGroup: Equatable, Sendable {
    public var day: Int
    public var tasks: [TaskSummary]
}

public enum Planning {
    // MARK: Ordering

    /// Timed tasks first, in clock order; then untimed ones by priority (high first), then manual order, then age.
    public static func ordered(_ tasks: [TaskSummary]) -> [TaskSummary] {
        tasks.sorted(by: areInOrder)
    }

    public static func areInOrder(_ a: TaskSummary, _ b: TaskSummary) -> Bool {
        switch (a.dueMinutes, b.dueMinutes) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if a.priority != b.priority { return a.priority > b.priority }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    // MARK: Today

    public static func dayPlan(_ tasks: [TaskSummary], today: Int) -> DayPlan {
        var overdue: [TaskSummary] = []
        var due: [TaskSummary] = []
        var done: [TaskSummary] = []
        for task in tasks {
            if let completed = task.completedDay {
                if completed == today { done.append(task) }
                continue
            }
            if task.lastDoneDay == today { done.append(task) }
            guard let day = task.dueDay else { continue }
            if day < today { overdue.append(task) } else if day == today { due.append(task) }
        }
        overdue.sort { a, b in
            if a.dueDay != b.dueDay { return a.dueDay! < b.dueDay! }
            return areInOrder(a, b)
        }
        return DayPlan(overdue: overdue, today: ordered(due), doneToday: ordered(done))
    }

    // MARK: Upcoming

    /// Open tasks due after today, grouped by day for the next `horizon` days. `later` holds anything beyond that.
    public static func upcoming(_ tasks: [TaskSummary], today: Int, horizon: Int = 14)
        -> (groups: [UpcomingGroup], later: [TaskSummary]) {
        var byDay: [Int: [TaskSummary]] = [:]
        var later: [TaskSummary] = []
        for task in tasks where !task.isCompleted {
            guard let day = task.dueDay, day > today else { continue }
            if day <= today + horizon { byDay[day, default: []].append(task) } else { later.append(task) }
        }
        let groups = byDay.keys.sorted().map { UpcomingGroup(day: $0, tasks: ordered(byDay[$0]!)) }
        later.sort { a, b in a.dueDay! != b.dueDay! ? a.dueDay! < b.dueDay! : areInOrder(a, b) }
        return (groups, later)
    }

    /// How many open tasks fall on each day, for the dots on the month calendar.
    public static func openCountByDay(_ tasks: [TaskSummary]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for task in tasks where !task.isCompleted {
            if let day = task.dueDay { counts[day, default: 0] += 1 }
        }
        return counts
    }

    // MARK: Search

    /// Every word of the query must appear in the title, notes, a tag or a checklist step. Ignores case and accents.
    public static func matches(_ task: TaskSummary, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !terms.isEmpty else { return true }
        let haystack = fold(([task.title, task.notes] + task.tags + task.checklist.map(\.title)).joined(separator: "\n"))
        return terms.allSatisfy { haystack.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Where an overdue or unscheduled task can be moved with one tap.
public enum Reschedule: String, CaseIterable, Sendable {
    case today, tomorrow, weekend, nextWeek, nextMonth

    public var label: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .weekend: return "This weekend"
        case .nextWeek: return "Next week"
        case .nextMonth: return "Next month"
        }
    }

    public var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .tomorrow: return "sunrise"
        case .weekend: return "beach.umbrella"
        case .nextWeek: return "calendar"
        case .nextMonth: return "calendar.badge.clock"
        }
    }

    /// The day this option means, counted from `today`. Always a day that makes the task not overdue; never earlier
    /// than the option's name suggests (a Saturday's "This weekend" is tomorrow, not today).
    public func target(from today: Int, firstWeekday: Int = 2) -> Int {
        switch self {
        case .today:
            return today
        case .tomorrow:
            return today + 1
        case .weekend:
            let weekday = Day.weekday(of: today)
            switch weekday {
            case 7: return today + 1 // Saturday -> Sunday
            case 1: return today + 6 // Sunday -> next Saturday
            default: return today + (7 - weekday)
            }
        case .nextWeek:
            return Day.weekStart(of: today, firstWeekday: firstWeekday) + 7
        case .nextMonth:
            return Day.adding(months: 1, to: Day.monthStart(of: today), aimingFor: 1)
        }
    }
}

public enum CompletionOutcome: Equatable, Sendable {
    /// The task is done for good.
    case finished
    /// A repeating task: it stays open and moves to this day.
    case advanced(to: Int)
}

public enum Completion {
    /// What ticking a task does. One-off tasks finish. Repeating tasks move to their next date and never pile up as
    /// duplicates; a rule that has ended (past its `until`) finishes the task.
    public static func complete(due: Int?, recurrence: Recurrence?, today: Int, firstWeekday: Int = 2) -> CompletionOutcome {
        guard let recurrence else { return .finished }
        let anchoredDue = due ?? today
        let rule = recurrence.anchored(to: anchoredDue)
        guard let next = rule.nextDue(after: anchoredDue, completedOn: today, firstWeekday: firstWeekday) else {
            return .finished
        }
        return .advanced(to: next)
    }
}

/// Trash keeps deleted tasks recoverable for a month, then lets them go.
public enum Trash {
    public static let retentionDays = 30

    public static func expiry(of deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(TimeInterval(retentionDays) * 86_400)
    }

    public static func isExpired(deletedAt: Date, now: Date = .now) -> Bool {
        now >= expiry(of: deletedAt)
    }

    /// Whole days left, rounded up, never negative.
    public static func daysLeft(deletedAt: Date, now: Date = .now) -> Int {
        max(0, Int((expiry(of: deletedAt).timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

/// The month grid for the calendar view.
public struct MonthCell: Equatable, Sendable {
    public var day: Int
    public var inMonth: Bool
}

public enum MonthGrid {
    /// Whole weeks (Monday-first or Sunday-first, per `firstWeekday`) covering the month, with leading and trailing
    /// days from the neighbouring months flagged `inMonth == false`.
    public static func weeks(year: Int, month: Int, firstWeekday: Int = 2) -> [[MonthCell]] {
        let first = Day.key(year: year, month: month, day: 1)
        let last = first + Day.daysInMonth(year: year, month: month) - 1
        let start = Day.weekStart(of: first, firstWeekday: firstWeekday)
        let end = Day.weekStart(of: last, firstWeekday: firstWeekday) + 6
        return stride(from: start, through: end, by: 7).map { weekStart in
            (0..<7).map { MonthCell(day: weekStart + $0, inMonth: ($0 + weekStart) >= first && ($0 + weekStart) <= last) }
        }
    }
}
