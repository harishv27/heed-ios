import Foundation

/// A calendar day as a plain integer: days since 1970-01-01 on the local calendar.
///
/// Due dates are stored as these integers instead of `Date`s, so "is this due today?" never depends on a time zone,
/// daylight saving or the time of day. Everything below is integer arithmetic on the proleptic Gregorian calendar
/// (Howard Hinnant's civil-date algorithms), so recurrence maths is exact and fast and needs no `Calendar`.
public enum Day {
    /// The day key for the local calendar date of `date`.
    public static func key(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Start of the local day for a key.
    public static func date(for key: Int, calendar: Calendar = .current) -> Date {
        let (year, month, day) = ymd(key)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The moment `minutes` after local midnight on `key`. Uses the calendar's own rules, so on a daylight-saving
    /// change a time that does not exist (02:30 when the clocks jump forward) lands on the next valid moment instead
    /// of being skipped.
    public static func date(for key: Int, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = date(for: key, calendar: calendar)
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? start
    }

    /// Weekday of a key in `Calendar` numbering: 1 = Sunday ... 7 = Saturday. 1970-01-01 was a Thursday.
    public static func weekday(of key: Int) -> Int {
        (((key % 7) + 7 + 4) % 7) + 1
    }

    /// First day of the week containing `key`, where `firstWeekday` uses the same 1 = Sunday numbering.
    public static func weekStart(of key: Int, firstWeekday: Int) -> Int {
        key - ((weekday(of: key) - firstWeekday + 7) % 7)
    }

    // MARK: Civil dates

    public static func key(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public static func ymd(_ key: Int) -> (year: Int, month: Int, day: Int) {
        let z = key + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// The key for `day` of the month, pulled back to the last day when the month is shorter (31 -> 28 in February).
    public static func clampedKey(year: Int, month: Int, day: Int) -> Int {
        key(year: year, month: month, day: min(day, daysInMonth(year: year, month: month)))
    }

    /// Same day-of-month `months` later (or earlier), clamped to the end of a shorter month. `day` overrides the
    /// day-of-month to aim for, so a rule that means "the 31st" does not drift to the 28th after February.
    public static func adding(months: Int, to key: Int, aimingFor day: Int? = nil) -> Int {
        let parts = ymd(key)
        let index = parts.year * 12 + (parts.month - 1) + months
        let year = Int((Double(index) / 12).rounded(.down))
        let month = index - year * 12 + 1
        return clampedKey(year: year, month: month, day: day ?? parts.day)
    }

    /// First day of the month containing `key`.
    public static func monthStart(of key: Int) -> Int {
        let parts = ymd(key)
        return Self.key(year: parts.year, month: parts.month, day: 1)
    }
}
