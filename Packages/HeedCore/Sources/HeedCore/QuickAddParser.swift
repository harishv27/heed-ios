import Foundation

/// What the quick-add line understood.
public struct ParsedTask: Equatable, Sendable {
    public var title: String
    public var dueDay: Int?
    /// Minutes after midnight, when a time was given.
    public var minutes: Int?
    public var recurrence: Recurrence?
    public var priority: Priority
    /// `#list` (matched to an existing list by name, or created).
    public var listName: String?
    /// `@tag`.
    public var tags: [String]

    public init(title: String, dueDay: Int? = nil, minutes: Int? = nil, recurrence: Recurrence? = nil,
                priority: Priority = .none, listName: String? = nil, tags: [String] = []) {
        self.title = title
        self.dueDay = dueDay
        self.minutes = minutes
        self.recurrence = recurrence
        self.priority = priority
        self.listName = listName
        self.tags = tags
    }

    /// True when anything beyond the title was recognised.
    public var hasDetails: Bool {
        dueDay != nil || minutes != nil || recurrence != nil || priority != .none || listName != nil || !tags.isEmpty
    }
}

/// Turns "Call mum friday 6pm every week !1 #family @phone" into a title, a date, a time, a repeat rule, a priority,
/// a list and a tag. It runs entirely on the device and needs no network.
///
/// Rules of thumb, chosen so a normal sentence is rarely misread:
/// - Words are matched left to right; the first date, time, rule, priority and list win and later look-alikes stay in
///   the title.
/// - A weekday name on its own means the *next* such day after today ("friday"); "next friday" is the one in the
///   following calendar week. Three-letter abbreviations ("fri") count only after on / next / this / by / every.
/// - A time needs am/pm or a colon ("6pm", "6:30pm", "18:30"). A bare "at 6" is left alone because it could mean
///   either half of the day. Times without am/pm are read on the 24-hour clock.
/// - "morning / afternoon / evening" are times only right after a date ("friday evening"), so "Morning pages" stays a
///   title.
/// - A time with no date means today, or tomorrow if that time has already passed.
public enum QuickAddParser {
    // MARK: Entry point

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ParsedTask {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let context = Context(today: Day.key(for: now, calendar: calendar),
                              nowMinutes: (nowParts.hour ?? 0) * 60 + (nowParts.minute ?? 0),
                              firstWeekday: calendar.firstWeekday)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map { Word(raw: String($0)) }

        var draft = Draft()
        var index = 0
        var lastWasDate = false
        while index < words.count {
            let word = words[index]

            if draft.priority == nil, let priority = priority(word.key) {
                draft.priority = priority
                index += 1
                continue
            }
            if word.key.hasPrefix("#"), word.key.count > 1, draft.list == nil {
                draft.list = String(word.cleaned.dropFirst())
                index += 1
                continue
            }
            if word.key.hasPrefix("@"), word.key.count > 1 {
                let tag = String(word.cleaned.dropFirst())
                if !draft.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { draft.tags.append(tag) }
                index += 1
                continue
            }

            // A leading "at / on / by" belongs to the date or time that follows it, not to the title.
            let leadsIn = fillers.contains(word.key) && index + 1 < words.count
            let start = leadsIn ? index + 1 : index
            let allowAbbreviation = leadsIn || ["next", "this", "every"].contains(word.key)

            if draft.rule == nil, let match = recurrence(words, start, context) {
                match.apply(&draft)
                index = start + match.consumed
                lastWasDate = false
                continue
            }
            if draft.minutes == nil, let match = time(words, start, context, afterDate: lastWasDate) {
                match.apply(&draft)
                index = start + match.consumed
                continue
            }
            if draft.due == nil, let match = date(words, start, context, allowAbbreviation: allowAbbreviation) {
                match.apply(&draft)
                index = start + match.consumed
                lastWasDate = true
                continue
            }

            draft.title.append(word.raw)
            lastWasDate = false
            index += 1
        }

        return finish(draft, original: trimmed, context)
    }

    // MARK: Draft

    private struct Context {
        let today: Int
        let nowMinutes: Int
        let firstWeekday: Int
    }

    private struct Draft {
        var title: [String] = []
        var due: Int?
        var minutes: Int?
        var rule: Recurrence?
        var priority: Priority?
        var list: String?
        var tags: [String] = []
        var tonight = false
    }

    private struct Match {
        var consumed: Int
        var apply: (inout Draft) -> Void
    }

    private struct Word {
        let raw: String
        /// Lower-cased, without trailing punctuation.
        let key: String
        /// Original case, without trailing punctuation.
        let cleaned: String

        init(raw: String) {
            self.raw = raw
            var trimmed = Substring(raw)
            while let last = trimmed.last, ",.;:?".contains(last) { trimmed = trimmed.dropLast() }
            self.cleaned = String(trimmed)
            self.key = cleaned.lowercased()
        }
    }

    private static let fillers: Set<String> = ["at", "on", "by", "due", "until"]

    private static func finish(_ draft: Draft, original: String, _ context: Context) -> ParsedTask {
        var due = draft.due
        var minutes = draft.minutes
        var rule = draft.rule

        if draft.tonight, minutes == nil { minutes = 20 * 60 }

        if let current = rule, due == nil {
            // "every monday" starts on the next Monday; "every day" starts today, or tomorrow if today's time is gone.
            var first = current.firstOccurrence(onOrAfter: context.today)
            if first == context.today, let minutes, minutes <= context.nowMinutes {
                first = current.nextOccurrence(after: first, firstWeekday: context.firstWeekday) ?? first
            }
            due = first
        }
        if due == nil, let minutes {
            // A bare time means the next time that clock reads that.
            due = minutes > context.nowMinutes ? context.today : context.today + 1
        }
        if let current = rule, let due { rule = current.anchored(to: due) }

        let title = draft.title.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–"))
        guard !title.isEmpty else {
            // The whole line was "tomorrow 6pm" or similar: keep it as the title rather than save a blank task.
            return ParsedTask(title: original)
        }
        return ParsedTask(title: title, dueDay: due, minutes: minutes, recurrence: rule,
                          priority: draft.priority ?? .none, listName: draft.list, tags: draft.tags)
    }

    // MARK: Priority

    private static func priority(_ key: String) -> Priority? {
        switch key {
        case "!1", "p1": return .high
        case "!2", "p2": return .medium
        case "!3", "p3": return .low
        default: return nil
        }
    }

    // MARK: Time

    private static func time(_ words: [Word], _ i: Int, _ context: Context, afterDate: Bool) -> Match? {
        guard i < words.count else { return nil }
        let key = words[i].key

        switch key {
        case "noon", "midday": return Match(consumed: 1) { $0.minutes = 12 * 60 }
        case "midnight": return Match(consumed: 1) { $0.minutes = 0 }
        case "morning" where afterDate: return Match(consumed: 1) { $0.minutes = 9 * 60 }
        case "afternoon" where afterDate: return Match(consumed: 1) { $0.minutes = 15 * 60 }
        case "evening" where afterDate: return Match(consumed: 1) { $0.minutes = 18 * 60 }
        default: break
        }

        // "6 pm", "6:30 pm"
        if i + 1 < words.count, ["am", "pm"].contains(words[i + 1].key), let value = clock(key + words[i + 1].key) {
            return Match(consumed: 2) { $0.minutes = value }
        }
        if let value = clock(key) { return Match(consumed: 1) { $0.minutes = value } }

        // "in 30 minutes", "in 2 hours": an exact moment relative to now.
        if key == "in", let amount = relativeAmount(words, i + 1), i + 2 < words.count {
            let unit = words[i + 2].key
            let minutes: Int?
            switch unit {
            case "min", "mins", "minute", "minutes": minutes = amount
            case "hr", "hrs", "hour", "hours": minutes = amount * 60
            default: minutes = nil
            }
            if let minutes {
                let total = context.nowMinutes + minutes
                return Match(consumed: 3) {
                    $0.due = context.today + total / 1440
                    $0.minutes = total % 1440
                }
            }
        }
        return nil
    }

    /// 6pm, 6:30pm, 18:30. Nil for anything that is not unambiguously a time.
    static func clock(_ key: String) -> Int? {
        var text = Substring(key)
        var isPM: Bool?
        if text.hasSuffix("am") { isPM = false; text = text.dropLast(2) }
        else if text.hasSuffix("pm") { isPM = true; text = text.dropLast(2) }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let hour = Int(parts[0])!
        let minute = parts.count == 2 ? Int(parts[1])! : 0
        guard minute < 60 else { return nil }
        if parts.count == 2, parts[1].count != 2 { return nil }

        if let isPM {
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12 + (isPM ? 12 : 0)) * 60 + minute
        }
        guard parts.count == 2, hour < 24 else { return nil }
        return hour * 60 + minute
    }

    // MARK: Date

    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let weekdayAbbreviations: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]
    private static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10,
        "nov": 11, "dec": 12,
    ]

    private static func weekday(_ key: String, allowAbbreviation: Bool) -> Int? {
        weekdayNames[key] ?? (allowAbbreviation ? weekdayAbbreviations[key] : nil)
    }

    private static func date(_ words: [Word], _ i: Int, _ context: Context, allowAbbreviation: Bool) -> Match? {
        guard i < words.count else { return nil }
        let key = words[i].key
        let today = context.today
        func next(_ n: Int) -> String? { i + n < words.count ? words[i + n].key : nil }

        switch key {
        case "today", "tod": return Match(consumed: 1) { $0.due = today }
        case "tomorrow", "tmr", "tmrw", "tom": return Match(consumed: 1) { $0.due = today + 1 }
        case "tonight": return Match(consumed: 1) { $0.due = today; $0.tonight = true }
        case "day" where next(1) == "after" && next(2) == "tomorrow": return Match(consumed: 3) { $0.due = today + 2 }
        case "weekend": return Match(consumed: 1) { $0.due = upcomingWeekend(from: today) }
        default: break
        }

        if let target = weekday(key, allowAbbreviation: allowAbbreviation) {
            return Match(consumed: 1) { $0.due = nextWeekday(target, after: today) }
        }

        if key == "this" || key == "next", let following = next(1) {
            if let target = weekday(following, allowAbbreviation: true) {
                if key == "this" { return Match(consumed: 2) { $0.due = nextWeekday(target, after: today) } }
                let nextWeek = Day.weekStart(of: today, firstWeekday: context.firstWeekday) + 7
                let offset = (target - context.firstWeekday + 7) % 7
                return Match(consumed: 2) { $0.due = nextWeek + offset }
            }
            if following == "weekend", key == "this" { return Match(consumed: 2) { $0.due = upcomingWeekend(from: today) } }
            if following == "week", key == "next" {
                return Match(consumed: 2) { $0.due = Day.weekStart(of: today, firstWeekday: context.firstWeekday) + 7 }
            }
            if following == "month", key == "next" {
                return Match(consumed: 2) { $0.due = Day.adding(months: 1, to: Day.monthStart(of: today), aimingFor: 1) }
            }
        }

        // "in 3 days", "in a week"
        if key == "in", let amount = relativeAmount(words, i + 1), let unit = next(2) {
            switch unit {
            case "day", "days": return Match(consumed: 3) { $0.due = today + amount }
            case "week", "weeks": return Match(consumed: 3) { $0.due = today + 7 * amount }
            case "month", "months": return Match(consumed: 3) { $0.due = Day.adding(months: amount, to: today) }
            case "year", "years": return Match(consumed: 3) { $0.due = Day.adding(months: 12 * amount, to: today) }
            default: break
            }
        }

        // 2026-10-25
        if let iso = isoDate(key) { return Match(consumed: 1) { $0.due = iso } }

        // "oct 25", "october 25th 2027"
        if let month = monthNames[key], let day = dayNumber(next(1)) {
            var consumed = 2
            var year: Int?
            if let value = next(2).flatMap(yearNumber) { year = value; consumed = 3 }
            if let resolved = resolve(month: month, day: day, year: year, today: today) {
                return Match(consumed: consumed) { $0.due = resolved }
            }
        }

        // "25 oct", "25th of october 2027"
        if let day = dayNumber(key) {
            var monthIndex = 1
            if next(1) == "of" { monthIndex = 2 }
            if let month = next(monthIndex).flatMap({ monthNames[$0] }) {
                var consumed = monthIndex + 1
                var year: Int?
                if let value = next(consumed).flatMap(yearNumber) { year = value; consumed += 1 }
                if let resolved = resolve(month: month, day: day, year: year, today: today) {
                    return Match(consumed: consumed) { $0.due = resolved }
                }
            }
        }

        // "the 15th": the next 15th.
        if key == "the", let ordinal = next(1), ordinal.count > 2, let day = dayNumber(ordinal), hasOrdinalSuffix(ordinal) {
            return Match(consumed: 2) { $0.due = nextDayOfMonth(day, from: today) }
        }
        return nil
    }

    /// 1...31 with an optional st / nd / rd / th.
    private static func dayNumber(_ key: String?) -> Int? {
        guard let key else { return nil }
        var text = Substring(key)
        if hasOrdinalSuffix(key) { text = text.dropLast(2) }
        guard text.count <= 2, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (1...31).contains(value)
        else { return nil }
        return value
    }

    private static func hasOrdinalSuffix(_ key: String) -> Bool {
        ["st", "nd", "rd", "th"].contains { key.hasSuffix($0) } && key.dropLast(2).allSatisfy { $0.isASCII && $0.isNumber }
            && !key.dropLast(2).isEmpty
    }

    private static func yearNumber(_ key: String) -> Int? {
        guard key.count == 4, let value = Int(key), (2000...2100).contains(value) else { return nil }
        return value
    }

    private static func isoDate(_ key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...Day.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        return Day.key(year: year, month: month, day: day)
    }

    /// With no year given, a date that has already passed this year means next year.
    private static func resolve(month: Int, day: Int, year: Int?, today: Int) -> Int? {
        let currentYear = Day.ymd(today).year
        func make(_ year: Int) -> Int? {
            day <= Day.daysInMonth(year: year, month: month) ? Day.key(year: year, month: month, day: day) : nil
        }
        if let year { return make(year) }
        if let thisYear = make(currentYear), thisYear >= today { return thisYear }
        return make(currentYear + 1) ?? make(currentYear + 2)
    }

    /// "a", "an" or a number.
    private static func relativeAmount(_ words: [Word], _ i: Int) -> Int? {
        guard i < words.count else { return nil }
        let key = words[i].key
        if key == "a" || key == "an" { return 1 }
        guard key.count <= 3, let value = Int(key), value > 0 else { return nil }
        return value
    }

    static func nextWeekday(_ weekday: Int, after day: Int) -> Int {
        let delta = (weekday - Day.weekday(of: day) + 7) % 7
        return day + (delta == 0 ? 7 : delta)
    }

    /// Saturday on or after `day`; on a Sunday, today.
    static func upcomingWeekend(from day: Int) -> Int {
        let weekday = Day.weekday(of: day)
        if weekday == 1 { return day }
        return day + (7 - weekday)
    }

    private static func nextDayOfMonth(_ day: Int, from today: Int) -> Int {
        let parts = Day.ymd(today)
        let thisMonth = Day.clampedKey(year: parts.year, month: parts.month, day: day)
        return thisMonth >= today ? thisMonth : Day.adding(months: 1, to: Day.monthStart(of: today), aimingFor: day)
    }

    // MARK: Recurrence

    private static func recurrence(_ words: [Word], _ i: Int, _ context: Context) -> Match? {
        guard i < words.count else { return nil }
        let key = words[i].key

        switch key {
        case "daily", "everyday": return Match(consumed: 1) { $0.rule = Recurrence.daily }
        case "weekly": return Match(consumed: 1) { $0.rule = Recurrence.weekly }
        case "monthly": return Match(consumed: 1) { $0.rule = Recurrence.monthly }
        case "yearly", "annually": return Match(consumed: 1) { $0.rule = Recurrence.yearly }
        case "fortnightly", "biweekly": return Match(consumed: 1) { $0.rule = Recurrence(unit: .week, interval: 2) }
        case "weekdays": return Match(consumed: 1) { $0.rule = Recurrence.weekdaysOnly }
        case "weekends": return Match(consumed: 1) { $0.rule = Recurrence.weekends }
        default: break
        }
        guard key == "every" || key == "every!" else { return nil }
        let mode: Recurrence.Mode = key == "every!" ? .afterCompletion : .fixed
        var j = i + 1
        guard j < words.count else { return nil }

        // "every other ..." / "every 3 ..."
        var interval = 1
        if words[j].key == "other" { interval = 2; j += 1 }
        else if let count = Int(words[j].key), (1...99).contains(count), j + 1 < words.count, unit(words[j + 1].key) != nil {
            interval = count
            j += 1
        }
        guard j < words.count else { return nil }

        if let unit = unit(words[j].key) {
            var rule = Recurrence(unit: unit, interval: interval, mode: mode)
            j += 1
            // "every month on the 15th", "every 2 weeks on monday and friday"
            if unit == .month {
                var k = j
                if k < words.count, words[k].key == "on" { k += 1 }
                if k < words.count, words[k].key == "the" { k += 1 }
                if k < words.count, hasOrdinalSuffix(words[k].key), let day = dayNumber(words[k].key) {
                    rule.dayOfMonth = day
                    j = k + 1
                }
            } else if unit == .week {
                var k = j
                if k < words.count, words[k].key == "on" { k += 1 }
                let (days, end) = weekdayList(words, from: k)
                if !days.isEmpty { rule.weekdays = days; j = end }
            }
            let built = rule
            return Match(consumed: j - i) { $0.rule = built }
        }

        if words[j].key == "weekday" {
            return Match(consumed: j + 1 - i) { $0.rule = Recurrence(unit: .week, interval: interval, weekdays: [2, 3, 4, 5, 6], mode: mode) }
        }
        if words[j].key == "weekend" {
            return Match(consumed: j + 1 - i) { $0.rule = Recurrence(unit: .week, interval: interval, weekdays: [1, 7], mode: mode) }
        }

        // "every 15th", "every 1st"
        if hasOrdinalSuffix(words[j].key), let day = dayNumber(words[j].key) {
            let rule = Recurrence(unit: .month, interval: interval, dayOfMonth: day, mode: mode)
            return Match(consumed: j + 1 - i) { $0.rule = rule }
        }

        // "every mon", "every mon, wed and fri"
        let (days, end) = weekdayList(words, from: j)
        if !days.isEmpty {
            let rule = Recurrence(unit: .week, interval: interval, weekdays: days, mode: mode)
            return Match(consumed: end - i) { $0.rule = rule }
        }
        return nil
    }

    private static func unit(_ key: String) -> Recurrence.Unit? {
        switch key {
        case "day", "days": return .day
        case "week", "weeks": return .week
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    /// Reads "mon", "mon wed and fri", "monday, thursday" starting at `index`. Returns the days and where it stopped.
    private static func weekdayList(_ words: [Word], from index: Int) -> (Set<Int>, Int) {
        var days = Set<Int>()
        var j = index
        while j < words.count {
            let key = words[j].key
            if let day = weekday(key, allowAbbreviation: true) {
                days.insert(day)
                j += 1
            } else if ["and", "&"].contains(key), !days.isEmpty, j + 1 < words.count,
                      weekday(words[j + 1].key, allowAbbreviation: true) != nil {
                j += 1
            } else {
                break
            }
        }
        return (days, j)
    }
}
