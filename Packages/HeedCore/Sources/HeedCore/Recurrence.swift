import Foundation

/// How a task repeats.
///
/// Two behaviours, because people mean two different things:
/// - `.fixed`: the calendar decides ("every Monday", "the 1st of each month"). Finishing a task late or early never
///   moves the schedule.
/// - `.afterCompletion`: the gap decides ("2 weeks after I last did it"). Good for oil changes and haircuts.
///
/// All of the date maths works on day keys (see `Day`), so it is exact across daylight saving and month ends.
public struct Recurrence: Codable, Equatable, Hashable, Sendable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case day, week, month, year
    }

    public enum Mode: String, Codable, Sendable {
        case fixed, afterCompletion
    }

    public var unit: Unit
    /// Every `interval` units. Always at least 1.
    public var interval: Int
    /// For weekly rules: which weekdays (1 = Sunday ... 7 = Saturday). Empty means "the weekday of the due date".
    public var weekdays: Set<Int>
    /// For monthly and yearly rules: the day of the month to aim for, so "the 31st" survives a short February.
    public var dayOfMonth: Int?
    /// For yearly rules: the month (1...12).
    public var month: Int?
    public var mode: Mode
    /// Last day (inclusive) the rule may produce, or nil for forever.
    public var until: Int?

    public init(unit: Unit, interval: Int = 1, weekdays: Set<Int> = [], dayOfMonth: Int? = nil, month: Int? = nil,
                mode: Mode = .fixed, until: Int? = nil) {
        self.unit = unit
        self.interval = max(1, interval)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.dayOfMonth = dayOfMonth.map { min(max($0, 1), 31) }
        self.month = month.map { min(max($0, 1), 12) }
        self.mode = mode
        self.until = until
    }

    public static let daily = Recurrence(unit: .day)
    public static let weekdaysOnly = Recurrence(unit: .week, weekdays: [2, 3, 4, 5, 6])
    public static let weekends = Recurrence(unit: .week, weekdays: [1, 7])
    public static let weekly = Recurrence(unit: .week)
    public static let monthly = Recurrence(unit: .month)
    public static let yearly = Recurrence(unit: .year)

    // MARK: Anchoring

    /// Fills in the day-of-month / month a rule aims for from the due date it starts on, so the rule keeps hitting
    /// the same day even after a short month. Idempotent.
    public func anchored(to due: Int) -> Recurrence {
        var copy = self
        let parts = Day.ymd(due)
        if unit == .month || unit == .year, copy.dayOfMonth == nil { copy.dayOfMonth = parts.day }
        if unit == .year, copy.month == nil { copy.month = parts.month }
        return copy
    }

    /// The first day the rule fires on or after `day`. Used when a task is given a rule but no date ("every Monday").
    public func firstOccurrence(onOrAfter day: Int) -> Int {
        switch unit {
        case .day:
            return day
        case .week:
            guard !weekdays.isEmpty else { return day }
            return (0..<7).map { day + $0 }.first { weekdays.contains(Day.weekday(of: $0)) } ?? day
        case .month:
            guard let target = dayOfMonth else { return day }
            let parts = Day.ymd(day)
            let thisMonth = Day.clampedKey(year: parts.year, month: parts.month, day: target)
            return thisMonth >= day ? thisMonth : Day.adding(months: 1, to: Day.monthStart(of: day), aimingFor: target)
        case .year:
            guard let target = dayOfMonth, let month else { return day }
            let year = Day.ymd(day).year
            let thisYear = Day.clampedKey(year: year, month: month, day: target)
            return thisYear >= day ? thisYear : Day.clampedKey(year: year + 1, month: month, day: target)
        }
    }

    // MARK: Next occurrence

    /// The next day strictly after `due` that the calendar rule produces, or nil once `until` is passed.
    /// Only meaningful for `.fixed` rules; see `nextDue(after:completedOn:firstWeekday:)` for the full picture.
    public func nextOccurrence(after due: Int, firstWeekday: Int = 2) -> Int? {
        let rule = anchored(to: due)
        let next: Int
        switch unit {
        case .day:
            next = due + interval
        case .week:
            next = Self.nextWeekly(after: due, interval: interval, weekdays: weekdays, firstWeekday: firstWeekday)
        case .month:
            // Aim for the rule's day of month, counting from the month of `due`.
            next = Day.adding(months: interval, to: Day.monthStart(of: due), aimingFor: dayOfMonth)
        case .year:
            let year = Day.ymd(due).year + interval
            next = Day.clampedKey(year: year, month: rule.month ?? Day.ymd(due).month, day: rule.dayOfMonth ?? Day.ymd(due).day)
        }
        if let until, next > until { return nil }
        return next
    }

    /// What a task's due date becomes when it is completed on `completedOn`.
    ///
    /// - Fixed rules keep their rhythm: the result is the first occurrence after both the old due date and the
    ///   completion day. An overdue "daily" task finished today comes back tomorrow, not "yesterday + 1"; one finished
    ///   early skips ahead to the next occurrence rather than repeating today.
    /// - After-completion rules count from `completedOn`.
    /// - Returns nil when the rule has ended.
    public func nextDue(after due: Int, completedOn: Int, firstWeekday: Int = 2) -> Int? {
        switch mode {
        case .afterCompletion:
            let next: Int
            switch unit {
            case .day: next = completedOn + interval
            case .week: next = completedOn + 7 * interval
            case .month: next = Day.adding(months: interval, to: completedOn)
            case .year: next = Day.adding(months: 12 * interval, to: completedOn)
            }
            if let until, next > until { return nil }
            return next
        case .fixed:
            // Anchor once, so a "the 31st" rule keeps aiming at the 31st through short months.
            let rule = anchored(to: due)
            guard var next = rule.nextOccurrence(after: due, firstWeekday: firstWeekday) else { return nil }
            if next <= completedOn { next = rule.fastForward(next, to: completedOn) }
            // After the jump only a few steps remain.
            var guardCount = 0
            while next <= completedOn {
                guard let following = rule.nextOccurrence(after: next, firstWeekday: firstWeekday) else { return nil }
                next = following
                guardCount += 1
                if guardCount > 1_000 { return nil }
            }
            if let until, next > until { return nil }
            return next
        }
    }

    /// Skips whole repeat periods so a task ignored for years does not take years of loop iterations. The result is
    /// still an occurrence of the rule and still at or before `target`'s neighbourhood: at most two periods short.
    private func fastForward(_ next: Int, to target: Int) -> Int {
        switch unit {
        case .day:
            return next + max(0, (target - next) / interval - 1) * interval
        case .week:
            let period = 7 * interval
            return next + max(0, (target - next) / period - 1) * period
        case .month:
            let a = Day.ymd(next), b = Day.ymd(target)
            let months = (b.year * 12 + b.month) - (a.year * 12 + a.month)
            let jump = max(0, months / interval - 1) * interval
            return Day.adding(months: jump, to: Day.monthStart(of: next), aimingFor: dayOfMonth)
        case .year:
            let years = Day.ymd(target).year - Day.ymd(next).year
            let jump = max(0, years / interval - 1) * interval
            return Day.adding(months: 12 * jump, to: Day.monthStart(of: next), aimingFor: dayOfMonth)
        }
    }

    /// The next `count` days (starting with `start` itself) the rule fires on, for previews and reminder planning.
    public func occurrences(startingAt start: Int, count: Int, firstWeekday: Int = 2) -> [Int] {
        guard count > 0 else { return [] }
        var result = [start]
        var current = start
        while result.count < count, let next = nextOccurrence(after: current, firstWeekday: firstWeekday) {
            result.append(next)
            current = next
        }
        return result
    }

    // MARK: Weekly

    private static func nextWeekly(after due: Int, interval: Int, weekdays: Set<Int>, firstWeekday: Int) -> Int {
        let days = weekdays.isEmpty ? [Day.weekday(of: due)] : weekdays.sorted()
        // Position of a weekday within a week that starts on `firstWeekday`.
        func offset(_ weekday: Int) -> Int { (weekday - firstWeekday + 7) % 7 }
        let ordered = days.sorted { offset($0) < offset($1) }
        let start = Day.weekStart(of: due, firstWeekday: firstWeekday)
        let dueOffset = due - start
        if let later = ordered.map(offset).first(where: { $0 > dueOffset }) {
            return start + later
        }
        return start + 7 * interval + offset(ordered[0])
    }

    // MARK: Description

    /// "Every day", "Every 2 weeks on Mon, Wed", "Monthly on the 15th", "2 weeks after completion".
    public func summary(firstWeekday: Int = 2, calendar: Calendar = .current) -> String {
        let names = calendar.shortWeekdaySymbols
        let plural: String = interval == 1 ? unit.rawValue : "\(interval) \(unit.rawValue)s"
        if mode == .afterCompletion { return "\(interval) \(unit.rawValue)\(interval == 1 ? "" : "s") after completion" }
        switch unit {
        case .day:
            return interval == 1 ? "Every day" : "Every \(plural)"
        case .week:
            if weekdays == [2, 3, 4, 5, 6], interval == 1 { return "Every weekday" }
            if weekdays == [1, 7], interval == 1 { return "Every weekend" }
            let list = weekdays.sorted { (($0 - firstWeekday + 7) % 7) < (($1 - firstWeekday + 7) % 7) }
                .map { names[$0 - 1] }.joined(separator: ", ")
            let base = interval == 1 ? "Every week" : "Every \(plural)"
            return weekdays.isEmpty ? base : "\(base) on \(list)"
        case .month:
            let base = interval == 1 ? "Every month" : "Every \(plural)"
            return dayOfMonth.map { "\(base) on the \(Self.ordinal($0))" } ?? base
        case .year:
            return interval == 1 ? "Every year" : "Every \(plural)"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: Storage

    public var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data?) -> Recurrence? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Recurrence.self, from: data)
    }
}
