import XCTest
@testable import HeedCore

final class ReminderPlannerTests: XCTestCase {
    private func source(_ title: String, due: Int?, minutes: Int? = nil, lead: Int? = 0, rule: Recurrence? = nil,
                        id: UUID = UUID()) -> ReminderSource {
        ReminderSource(id: id, title: title, dueDay: due, dueMinutes: minutes, recurrence: rule, leadMinutes: lead)
    }

    private func plan(_ tasks: [ReminderSource], now: Date = T.now, calendar: Calendar = T.utc, limit: Int = ReminderPlanner.defaultLimit) -> ReminderPlan {
        ReminderPlanner.plan(tasks, now: now, calendar: calendar, limit: limit)
    }

    // MARK: Timing

    func testAReminderAtTheDueTime() {
        let result = plan([source("Call", due: T.oct(15), minutes: 18 * 60)])
        XCTAssertEqual(result.reminders.count, 1)
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 18, 0))
        XCTAssertEqual(result.reminders[0].components.hour, 18)
        XCTAssertEqual(result.reminders[0].components.day, 15)
        XCTAssertEqual(result.deferred, 0)
    }

    func testALeadTimeMovesTheReminderEarlier() {
        let result = plan([source("Call", due: T.oct(15), minutes: 18 * 60, lead: 15)])
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 17, 45))
    }

    func testADateOnlyTaskIsRemindedAtTheDefaultTime() {
        let result = plan([source("Pay rent", due: T.oct(16))])
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 16, 9, 0))
        XCTAssertNil(result.reminders[0].dueMinutes)
    }

    func testADayBeforeReminderOnADateOnlyTask() {
        let result = plan([source("Pay rent", due: T.oct(16), lead: 1440)])
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 9, 0))
    }

    func testALeadTimeCanCrossMidnight() {
        let result = plan([source("Early flight", due: T.oct(16), minutes: 10, lead: 30)])
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 23, 40))
    }

    func testPastRemindersAndTasksWithoutReminderAreLeftOut() {
        let result = plan([
            source("Past", due: T.oct(13), minutes: 9 * 60),
            source("Earlier today", due: T.today, minutes: 9 * 60),
            source("No reminder", due: T.oct(16), lead: nil),
            source("No date", due: nil),
            source("Later today", due: T.today, minutes: 11 * 60),
        ])
        XCTAssertEqual(result.reminders.map(\.title), ["Later today"])
    }

    func testTheDefaultTimeIsConfigurable() {
        let custom = ReminderPlanner.plan([source("Pay", due: T.oct(16))], now: T.now, calendar: T.utc, defaultMinutes: 8 * 60 + 30)
        XCTAssertEqual(custom.reminders[0].fire, T.date(2026, 10, 16, 8, 30))
    }

    // MARK: Repeating tasks

    func testARepeatingTaskPlansSeveralOccurrences() {
        let result = plan([source("Meds", due: T.oct(15), minutes: 8 * 60, rule: .daily)])
        XCTAssertEqual(result.reminders.count, ReminderPlanner.occurrencesPerTask)
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 8, 0))
        XCTAssertEqual(result.reminders[1].fire, T.date(2026, 10, 16, 8, 0))
    }

    func testARepeatingTaskThatIsOverdueSkipsPastOccurrences() {
        let result = plan([source("Meds", due: T.oct(1), minutes: 8 * 60, rule: .daily)])
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 10, 15, 8, 0), "Oct 14 08:00 has passed")
    }

    func testAWeeklyRuleOnlyPlansItsWeekdays() {
        let rule = Recurrence(unit: .week, weekdays: [2, 4]) // Mon, Wed
        let result = plan([source("Gym", due: T.oct(19), minutes: 7 * 60, rule: rule)])
        let weekdays = result.reminders.map { Day.weekday(of: Day.key(for: $0.fire, calendar: T.utc)) }
        XCTAssertTrue(weekdays.allSatisfy { [2, 4].contains($0) })
        XCTAssertEqual(result.reminders.count, ReminderPlanner.occurrencesPerTask)
    }

    func testARuleThatEndsStopsPlanning() {
        let rule = Recurrence(unit: .day, until: T.oct(17))
        let result = plan([source("Course", due: T.oct(15), minutes: 9 * 60, rule: rule)])
        XCTAssertEqual(result.reminders.count, 3)
    }

    // MARK: The system cap

    func testOnlyTheSoonestRemindersAreKept() {
        let tasks = (1...100).map { source("Task \($0)", due: T.today + $0, minutes: 9 * 60) }
        let result = plan(tasks, limit: 58)
        XCTAssertEqual(result.reminders.count, 58)
        XCTAssertEqual(result.deferred, 42)
        XCTAssertEqual(result.reminders.first?.title, "Task 1")
        XCTAssertEqual(result.reminders.last?.title, "Task 58")
        XCTAssertLessThanOrEqual(result.reminders.count, ReminderPlanner.systemLimit)
    }

    func testTheDefaultLimitLeavesRoomUnderTheSystemLimit() {
        XCTAssertLessThan(ReminderPlanner.defaultLimit, ReminderPlanner.systemLimit)
    }

    func testManyRepeatingTasksFillTheWindowAndTheWindowSlidesForward() {
        var tasks = (0..<5).map { source("Daily \($0)", due: T.today + 1, minutes: 7 * 60, rule: .daily) }
        tasks.append(source("Dentist", due: T.today + 12, minutes: 15 * 60))

        let now = plan(tasks)
        XCTAssertEqual(now.reminders.count, ReminderPlanner.defaultLimit)
        XCTAssertGreaterThan(now.deferred, 0, "the health screen reports what is waiting")
        XCTAssertFalse(now.reminders.map(\.title).contains("Dentist"), "twelve days out is beyond the 58 soonest")

        // Five days later the dentist is inside the window.
        let later = plan(tasks, now: T.now.addingTimeInterval(5 * 86_400))
        XCTAssertTrue(later.reminders.map(\.title).contains("Dentist"))
    }

    func testOneRepeatingTaskNeverHogsTheCap() {
        let tasks = [source("Daily", due: T.today + 1, minutes: 7 * 60, rule: .daily)]
            + (1...6).map { source("One-off \($0)", due: T.today + 20 + $0, minutes: 9 * 60) }
        let titles = plan(tasks).reminders.map(\.title)
        XCTAssertEqual(titles.filter { $0 == "Daily" }.count, ReminderPlanner.occurrencesPerTask)
        XCTAssertEqual(titles.filter { $0.hasPrefix("One-off") }.count, 6)
    }

    func testRemindersAreSortedSoonestFirst() {
        let result = plan([source("B", due: T.oct(17), minutes: 600), source("A", due: T.oct(15), minutes: 600)])
        XCTAssertEqual(result.reminders.map(\.title), ["A", "B"])
    }

    // MARK: Identifiers and diffing

    func testIdentifiersAreStableAcrossRuns() {
        let id = UUID()
        let task = source("Call", due: T.oct(15), minutes: 18 * 60, id: id)
        XCTAssertEqual(plan([task]).reminders.map(\.identifier), plan([task]).reminders.map(\.identifier))
        XCTAssertTrue(plan([task]).reminders[0].identifier.hasPrefix(ReminderPlanner.prefix + id.uuidString))
        XCTAssertTrue(ReminderPlanner.isTaskReminder(plan([task]).reminders[0].identifier))
        XCTAssertFalse(ReminderPlanner.isTaskReminder("heed.test"))
    }

    func testAChangedTitleOrTimeChangesTheIdentifier() {
        let id = UUID()
        let base = plan([source("Call", due: T.oct(15), minutes: 600, id: id)]).reminders[0].identifier
        XCTAssertNotEqual(base, plan([source("Call mum", due: T.oct(15), minutes: 600, id: id)]).reminders[0].identifier)
        XCTAssertNotEqual(base, plan([source("Call", due: T.oct(15), minutes: 660, id: id)]).reminders[0].identifier)
        XCTAssertNotEqual(base, plan([source("Call", due: T.oct(15), minutes: 600, lead: 10, id: id)]).reminders[0].identifier)
    }

    func testFingerprintIsDeterministic() {
        XCTAssertEqual(ReminderPlanner.fingerprint("abc"), "1a47e90b")
        XCTAssertEqual(ReminderPlanner.fingerprint(""), "811c9dc5")
    }

    func testDiffTouchesOnlyWhatChanged() {
        let a = source("A", due: T.oct(15), minutes: 600)
        let b = source("B", due: T.oct(16), minutes: 600)
        let first = plan([a, b])
        let pending = Set(first.reminders.map(\.identifier))

        let unchanged = first.diff(existing: pending)
        XCTAssertTrue(unchanged.add.isEmpty)
        XCTAssertTrue(unchanged.remove.isEmpty)

        // B is completed (gone from the plan) and C is added.
        let c = source("C", due: T.oct(17), minutes: 600)
        let next = plan([a, c]).diff(existing: pending)
        XCTAssertEqual(next.add.map(\.title), ["C"])
        XCTAssertEqual(next.remove, [first.reminders[1].identifier])
    }

    func testDiffRemovesEverythingWhenNothingIsPlanned() {
        let pending: Set<String> = ["heed.task.x", "heed.task.y"]
        let diff = plan([]).diff(existing: pending)
        XCTAssertEqual(diff.remove, ["heed.task.x", "heed.task.y"])
        XCTAssertTrue(diff.add.isEmpty)
    }

    // MARK: Daylight saving

    func testADailyReminderStaysOnTheWallClockAcrossSpringForward() {
        let ny = T.calendar("America/New_York")
        let now = T.date(2026, 3, 6, 12, 0, in: ny)
        let rule = Recurrence.daily
        let result = ReminderPlanner.plan([source("Meds", due: Day.key(for: T.date(2026, 3, 7, in: ny), calendar: ny), minutes: 8 * 60, rule: rule)],
                                          now: now, calendar: ny)
        let hours = result.reminders.prefix(4).map { ny.component(.hour, from: $0.fire) }
        XCTAssertEqual(hours, [8, 8, 8, 8], "08:00 stays 08:00 before and after the clocks change on 8 March")
        // 08:00 on 7 March (EST) to 08:00 on 8 March (EDT) is 23 hours; the next day is a normal 24.
        XCTAssertEqual(result.reminders[1].fire.timeIntervalSince(result.reminders[0].fire), 23 * 3600)
        XCTAssertEqual(result.reminders[2].fire.timeIntervalSince(result.reminders[1].fire), 24 * 3600)
    }

    func testAReminderInTheSkippedHourIsNotLost() {
        let ny = T.calendar("America/New_York")
        let now = T.date(2026, 3, 7, 12, 0, in: ny)
        let day = Day.key(for: T.date(2026, 3, 8, in: ny), calendar: ny)
        let result = ReminderPlanner.plan([source("Night job", due: day, minutes: 2 * 60 + 30)], now: now, calendar: ny)
        XCTAssertEqual(result.reminders.count, 1)
        XCTAssertEqual(ny.component(.hour, from: result.reminders[0].fire), 3)
        XCTAssertEqual(result.reminders[0].components.hour, 3, "the trigger describes the moment it really fires")
        XCTAssertEqual(result.reminders[0].components.day, 8)
    }

    func testAReminderInTheRepeatedHourFiresOnce() {
        let ny = T.calendar("America/New_York")
        let now = T.date(2026, 10, 31, 12, 0, in: ny)
        let day = Day.key(for: T.date(2026, 11, 1, in: ny), calendar: ny)
        let result = ReminderPlanner.plan([source("Night job", due: day, minutes: 90)], now: now, calendar: ny)
        XCTAssertEqual(result.reminders.count, 1)
        XCTAssertEqual(result.reminders[0].fire, T.date(2026, 11, 1, 5, 30), "01:30 EDT, the first of the two 01:30s")
    }
}
