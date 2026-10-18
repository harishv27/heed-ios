import Foundation

/// A task as the reminder planner sees it.
public struct ReminderSource: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var dueDay: Int?
    /// Minutes after midnight, or nil for a date-only task (reminded at the default time).
    public var dueMinutes: Int?
    public var recurrence: Recurrence?
    /// Minutes before the due moment, or nil for no reminder. 0 means "at the due time".
    public var leadMinutes: Int?

    public init(id: UUID, title: String, dueDay: Int?, dueMinutes: Int?, recurrence: Recurrence? = nil, leadMinutes: Int?) {
        self.id = id
        self.title = title
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.recurrence = recurrence
        self.leadMinutes = leadMinutes
    }
}

/// One local notification Heed wants pending.
public struct PlannedReminder: Equatable, Hashable, Sendable {
    /// Stable and content-addressed: it names the task, the occurrence and a fingerprint of what the notification
    /// says, so the same plan always yields the same identifiers and a changed title yields a new one.
    public var identifier: String
    public var taskID: UUID
    public var title: String
    public var dueDay: Int
    public var dueMinutes: Int?
    public var leadMinutes: Int
    public var fire: Date
    /// Year...minute in the planning calendar, for a calendar trigger that follows the wall clock.
    public var components: DateComponents
}

public struct ReminderPlan: Equatable, Sendable {
    /// What should be pending now, soonest first.
    public var reminders: [PlannedReminder]
    /// Reminders that exist but do not fit under the system's cap yet. They are planned again as time passes.
    public var deferred: Int

    /// Which pending identifiers to add and which to remove to reach this plan, leaving untouched everything that is
    /// already right. Nothing is cleared first, so there is never a moment with no reminders scheduled.
    public func diff(existing: Set<String>) -> (add: [PlannedReminder], remove: [String]) {
        let wanted = Set(reminders.map(\.identifier))
        return (reminders.filter { !existing.contains($0.identifier) }, existing.subtracting(wanted).sorted())
    }
}

/// Decides which notifications iOS should hold.
///
/// iOS keeps at most 64 pending local notifications per app and silently drops the rest, which is a classic way for
/// to-do apps to lose reminders. So Heed never hands iOS everything: it plans the soonest `limit` reminders (expanding
/// repeating tasks a few occurrences ahead) and plans again whenever the app opens, a task changes, or a reminder is
/// handled, so the window keeps sliding forward.
public enum ReminderPlanner {
    /// Identifier prefix for task reminders. The test notification uses a different one, so planning never touches it.
    public static let prefix = "heed.task."
    public static let systemLimit = 64
    /// Leaves room for the "send a test" notification and a little slack.
    public static let defaultLimit = 58
    /// How many occurrences of one repeating task are planned ahead. More would only crowd out other tasks.
    public static let occurrencesPerTask = 14

    public static func isTaskReminder(_ identifier: String) -> Bool { identifier.hasPrefix(prefix) }

    public static func plan(_ tasks: [ReminderSource], now: Date, calendar: Calendar = .current,
                            defaultMinutes: Int = 9 * 60, limit: Int = defaultLimit) -> ReminderPlan {
        var all: [PlannedReminder] = []
        for task in tasks {
            guard let lead = task.leadMinutes, let due = task.dueDay else { continue }
            all.append(contentsOf: reminders(for: task, firstDue: due, lead: lead, now: now, calendar: calendar,
                                             defaultMinutes: defaultMinutes))
        }
        all.sort { a, b in a.fire != b.fire ? a.fire < b.fire : a.identifier < b.identifier }
        let kept = Array(all.prefix(max(0, limit)))
        return ReminderPlan(reminders: kept, deferred: max(0, all.count - kept.count))
    }

    private static func reminders(for task: ReminderSource, firstDue: Int, lead: Int, now: Date, calendar: Calendar,
                                  defaultMinutes: Int) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        var day = firstDue
        var steps = 0
        let rule = task.recurrence?.anchored(to: firstDue)
        while steps < 400, result.count < occurrencesPerTask {
            steps += 1
            if let planned = reminder(for: task, dueDay: day, lead: lead, now: now, calendar: calendar,
                                      defaultMinutes: defaultMinutes) {
                result.append(planned)
                if rule == nil { break }
            }
            guard let rule, let next = rule.nextOccurrence(after: day, firstWeekday: calendar.firstWeekday) else { break }
            day = next
        }
        return result
    }

    private static func reminder(for task: ReminderSource, dueDay: Int, lead: Int, now: Date, calendar: Calendar,
                                 defaultMinutes: Int) -> PlannedReminder? {
        // Count back in wall-clock minutes so "9:00" stays 9:00 across a daylight-saving change.
        let total = (task.dueMinutes ?? defaultMinutes) - lead
        let dayShift = Int((Double(total) / 1440).rounded(.down))
        let minutes = total - dayShift * 1440
        let fireDay = dueDay + dayShift
        let fire = Day.date(for: fireDay, minutes: minutes, calendar: calendar)
        guard fire > now.addingTimeInterval(1) else { return nil }

        // Read the fields back from the real moment, so a time that does not exist (the clocks jumped forward) is
        // described by the time it actually lands on.
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let fingerprint = Self.fingerprint("\(task.title)|\(task.dueMinutes ?? -1)|\(lead)")
        return PlannedReminder(identifier: "\(prefix)\(task.id.uuidString).\(dueDay).\(fingerprint)", taskID: task.id,
                               title: task.title, dueDay: dueDay, dueMinutes: task.dueMinutes, leadMinutes: lead,
                               fire: fire, components: components)
    }

    /// FNV-1a, 32 bit, as 8 hex digits. `String.hashValue` is randomised per launch, which would change every
    /// identifier on every start.
    static func fingerprint(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }
}
