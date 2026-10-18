import XCTest
@testable import HeedCore

final class PlanningTests: XCTestCase {
    // MARK: Ordering

    func testTimedTasksComeFirstInClockOrder() {
        let tasks = [
            T.task("No time, high", priority: .high),
            T.task("Late", minutes: 18 * 60),
            T.task("Early", minutes: 8 * 60),
        ]
        XCTAssertEqual(Planning.ordered(tasks).map(\.title), ["Early", "Late", "No time, high"])
    }

    func testUntimedTasksSortByPriorityThenManualOrderThenAge() {
        let tasks = [
            T.task("low", priority: .low, order: 0),
            T.task("high second", priority: .high, order: 2),
            T.task("high first", priority: .high, order: 1),
            T.task("none old", order: 5, created: 1),
            T.task("none new", order: 5, created: 2),
        ]
        XCTAssertEqual(Planning.ordered(tasks).map(\.title), ["high first", "high second", "low", "none old", "none new"])
    }

    func testOrderingIsStableForIdenticalTasks() {
        let tasks = (0..<20).map { T.task("same \($0)") }
        XCTAssertEqual(Planning.ordered(tasks), Planning.ordered(tasks.reversed()))
    }

    // MARK: Today

    func testDayPlanSplitsOverdueTodayAndDone() {
        let tasks = [
            T.task("two days ago", due: T.today - 2),
            T.task("yesterday", due: T.today - 1),
            T.task("today", due: T.today),
            T.task("tomorrow", due: T.today + 1),
            T.task("no date"),
            T.task("done today", due: T.today, done: T.today),
            T.task("done last week", due: T.today - 7, done: T.today - 6),
        ]
        let plan = Planning.dayPlan(tasks, today: T.today)
        XCTAssertEqual(plan.overdue.map(\.title), ["two days ago", "yesterday"])
        XCTAssertEqual(plan.today.map(\.title), ["today"])
        XCTAssertEqual(plan.doneToday.map(\.title), ["done today"])
        XCTAssertEqual(plan.openCount, 3)
        XCTAssertEqual(plan.totalToday, 2)
        XCTAssertFalse(plan.isEmpty)
    }

    func testOverdueIsOldestFirstThenByPriority() {
        let tasks = [
            T.task("b", due: T.today - 1, priority: .low),
            T.task("a-high", due: T.today - 1, priority: .high),
            T.task("oldest", due: T.today - 5),
        ]
        XCTAssertEqual(Planning.dayPlan(tasks, today: T.today).overdue.map(\.title), ["oldest", "a-high", "b"])
    }

    func testAnEmptyDayPlan() {
        XCTAssertTrue(Planning.dayPlan([], today: T.today).isEmpty)
        XCTAssertTrue(Planning.dayPlan([T.task("someday")], today: T.today).isEmpty)
    }

    // MARK: Upcoming

    func testUpcomingGroupsByDayAndSeparatesLaterTasks() {
        let tasks = [
            T.task("today", due: T.today),
            T.task("tomorrow b", due: T.today + 1, order: 2),
            T.task("tomorrow a", due: T.today + 1, order: 1),
            T.task("in ten days", due: T.today + 10),
            T.task("next month", due: T.today + 40),
            T.task("far", due: T.today + 90),
            T.task("done", due: T.today + 2, done: T.today),
            T.task("no date"),
        ]
        let (groups, later) = Planning.upcoming(tasks, today: T.today, horizon: 14)
        XCTAssertEqual(groups.map(\.day), [T.today + 1, T.today + 10])
        XCTAssertEqual(groups[0].tasks.map(\.title), ["tomorrow a", "tomorrow b"])
        XCTAssertEqual(later.map(\.title), ["next month", "far"])
    }

    func testOpenCountByDayIgnoresCompletedAndUndated() {
        let tasks = [
            T.task("a", due: T.today), T.task("b", due: T.today), T.task("c", due: T.today + 1),
            T.task("x", due: T.today, done: T.today), T.task("y"),
        ]
        XCTAssertEqual(Planning.openCountByDay(tasks), [T.today: 2, T.today + 1: 1])
    }

    // MARK: Search

    func testSearchMatchesEveryWordAnywhere() {
        let task = T.task("Book flights", tags: ["Travel"], notes: "Compare prices on Skyscanner",
                          checklist: [ChecklistItem(title: "Passport check")])
        XCTAssertTrue(Planning.matches(task, query: "flights"))
        XCTAssertTrue(Planning.matches(task, query: "book skyscanner"))
        XCTAssertTrue(Planning.matches(task, query: "travel"))
        XCTAssertTrue(Planning.matches(task, query: "passport"))
        XCTAssertFalse(Planning.matches(task, query: "book hotel"))
        XCTAssertTrue(Planning.matches(task, query: "   "))
    }

    func testSearchIgnoresCaseAndAccents() {
        let task = T.task("Reserve café table")
        XCTAssertTrue(Planning.matches(task, query: "CAFE"))
        XCTAssertTrue(Planning.matches(task, query: "café"))
    }

    // MARK: Rescheduling

    func testRescheduleTargetsFromAWednesday() {
        XCTAssertEqual(Reschedule.today.target(from: T.today), T.today)
        XCTAssertEqual(Reschedule.tomorrow.target(from: T.today), T.oct(15))
        XCTAssertEqual(Reschedule.weekend.target(from: T.today), T.oct(17))
        XCTAssertEqual(Reschedule.nextWeek.target(from: T.today), T.oct(19))
        XCTAssertEqual(Reschedule.nextMonth.target(from: T.today), T.key(2026, 11, 1))
    }

    func testWeekendFromTheWeekend() {
        XCTAssertEqual(Reschedule.weekend.target(from: T.oct(17)), T.oct(18), "on Saturday, 'this weekend' is tomorrow")
        XCTAssertEqual(Reschedule.weekend.target(from: T.oct(18)), T.oct(24), "on Sunday it means the next one")
        XCTAssertEqual(Reschedule.weekend.target(from: T.oct(16)), T.oct(17))
    }

    func testNextWeekStartsOnTheCalendarsFirstWeekday() {
        XCTAssertEqual(Reschedule.nextWeek.target(from: T.today, firstWeekday: 1), T.oct(18))
        XCTAssertEqual(Reschedule.nextWeek.target(from: T.oct(18), firstWeekday: 2), T.oct(19))
    }

    func testEveryOptionMovesOutOfOverdue() {
        for option in Reschedule.allCases {
            XCTAssertGreaterThanOrEqual(option.target(from: T.today), T.today, option.label)
        }
    }

    // MARK: Completing

    func testAOneOffTaskFinishes() {
        XCTAssertEqual(Completion.complete(due: T.today, recurrence: nil, today: T.today), .finished)
        XCTAssertEqual(Completion.complete(due: nil, recurrence: nil, today: T.today), .finished)
    }

    func testARepeatingTaskAdvances() {
        XCTAssertEqual(Completion.complete(due: T.today, recurrence: .daily, today: T.today), .advanced(to: T.today + 1))
        XCTAssertEqual(Completion.complete(due: T.today - 4, recurrence: .daily, today: T.today), .advanced(to: T.today + 1))
        XCTAssertEqual(Completion.complete(due: T.oct(12), recurrence: Recurrence(unit: .week, weekdays: [2]), today: T.today),
                       .advanced(to: T.oct(19)))
    }

    func testARepeatingTaskWithNoDateCountsFromToday() {
        XCTAssertEqual(Completion.complete(due: nil, recurrence: .daily, today: T.today), .advanced(to: T.today + 1))
    }

    func testAnEndedRuleFinishesTheTask() {
        let rule = Recurrence(unit: .day, until: T.today)
        XCTAssertEqual(Completion.complete(due: T.today, recurrence: rule, today: T.today), .finished)
    }

    func testCompletionKeepsAMonthEndRuleAiming() {
        let rule = Recurrence.monthly.anchored(to: T.key(2026, 1, 31))
        let first = Completion.complete(due: T.key(2026, 1, 31), recurrence: rule, today: T.key(2026, 1, 31))
        XCTAssertEqual(first, .advanced(to: T.key(2026, 2, 28)))
        let second = Completion.complete(due: T.key(2026, 2, 28), recurrence: rule, today: T.key(2026, 2, 28))
        XCTAssertEqual(second, .advanced(to: T.key(2026, 3, 31)))
    }

    // MARK: Trash

    func testTrashKeepsTasksForThirtyDays() {
        let deleted = T.date(2026, 10, 1, 9, 0)
        XCTAssertFalse(Trash.isExpired(deletedAt: deleted, now: T.date(2026, 10, 30, 9, 0)))
        XCTAssertTrue(Trash.isExpired(deletedAt: deleted, now: T.date(2026, 10, 31, 9, 0)))
        XCTAssertEqual(Trash.daysLeft(deletedAt: deleted, now: deleted), 30)
        XCTAssertEqual(Trash.daysLeft(deletedAt: deleted, now: T.date(2026, 10, 30, 10, 0)), 1)
        XCTAssertEqual(Trash.daysLeft(deletedAt: deleted, now: T.date(2027, 1, 1, 0, 0)), 0)
    }

    // MARK: Month grid

    func testMonthGridCoversWholeWeeks() {
        let weeks = MonthGrid.weeks(year: 2026, month: 10, firstWeekday: 2)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks[0][0].day, T.key(2026, 9, 28))
        XCTAssertFalse(weeks[0][0].inMonth)
        XCTAssertEqual(weeks[0][3].day, T.oct(1))
        XCTAssertTrue(weeks[0][3].inMonth)
        XCTAssertEqual(weeks[4][6].day, T.key(2026, 11, 1))
        XCTAssertFalse(weeks[4][6].inMonth)
        XCTAssertEqual(weeks.flatMap { $0 }.filter(\.inMonth).count, 31)
    }

    func testMonthGridFebruaryFitsFourWeeksWhenItStartsOnTheFirstWeekday() {
        // 1 February 2026 is a Sunday.
        let sundayFirst = MonthGrid.weeks(year: 2026, month: 2, firstWeekday: 1)
        XCTAssertEqual(sundayFirst.count, 4)
        XCTAssertTrue(sundayFirst.flatMap { $0 }.allSatisfy(\.inMonth))
        XCTAssertEqual(MonthGrid.weeks(year: 2026, month: 2, firstWeekday: 2).count, 5)
    }

    func testMonthGridCanNeedSixWeeks() {
        // 1 March 2025 is a Saturday: Monday-first needs six rows.
        XCTAssertEqual(MonthGrid.weeks(year: 2025, month: 3, firstWeekday: 2).count, 6)
    }
}

final class RepeatingDoneTodayTests: XCTestCase {
    func testARepeatingTaskTickedTodayCountsAsDoneAndIsNotListedAsOpen() {
        let meds = TaskSummary(title: "Meds", dueDay: T.today + 1, recurrence: .daily, lastDoneDay: T.today)
        let plan = Planning.dayPlan([meds, T.task("Other", due: T.today)], today: T.today)
        XCTAssertEqual(plan.doneToday.map(\.title), ["Meds"])
        XCTAssertEqual(plan.today.map(\.title), ["Other"])
        XCTAssertEqual(plan.totalToday, 2, "ticking a repeating task must not shrink the 'x of y' total")
    }

    func testATickFromAnEarlierDayDoesNotCount() {
        let meds = TaskSummary(title: "Meds", dueDay: T.today, recurrence: .daily, lastDoneDay: T.today - 1)
        let plan = Planning.dayPlan([meds], today: T.today)
        XCTAssertTrue(plan.doneToday.isEmpty)
        XCTAssertEqual(plan.today.map(\.title), ["Meds"])
    }
}
