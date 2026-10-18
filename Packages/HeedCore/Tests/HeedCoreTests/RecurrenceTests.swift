import XCTest
@testable import HeedCore

final class RecurrenceTests: XCTestCase {
    // MARK: Day, month and year rules

    func testDailyWithAnInterval() {
        let rule = Recurrence(unit: .day, interval: 3)
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(14)), T.oct(17))
    }

    func testIntervalNeverDropsBelowOne() {
        XCTAssertEqual(Recurrence(unit: .day, interval: 0).interval, 1)
        XCTAssertEqual(Recurrence(unit: .week, interval: -4).interval, 1)
    }

    func testMonthlyOnThe31stSurvivesShortMonths() {
        let rule = Recurrence.monthly.anchored(to: T.key(2026, 1, 31))
        XCTAssertEqual(rule.dayOfMonth, 31)
        let feb = rule.nextOccurrence(after: T.key(2026, 1, 31))!
        XCTAssertEqual(feb, T.key(2026, 2, 28))
        let mar = rule.nextOccurrence(after: feb)!
        XCTAssertEqual(mar, T.key(2026, 3, 31), "must go back to the 31st, not stay on the 28th")
        XCTAssertEqual(rule.nextOccurrence(after: mar), T.key(2026, 4, 30))
    }

    func testMonthlyInALeapYear() {
        let rule = Recurrence.monthly.anchored(to: T.key(2028, 1, 31))
        XCTAssertEqual(rule.nextOccurrence(after: T.key(2028, 1, 31)), T.key(2028, 2, 29))
    }

    func testEveryTwoMonths() {
        let rule = Recurrence(unit: .month, interval: 2).anchored(to: T.key(2026, 10, 15))
        XCTAssertEqual(rule.nextOccurrence(after: T.key(2026, 10, 15)), T.key(2026, 12, 15))
        XCTAssertEqual(rule.nextOccurrence(after: T.key(2026, 12, 15)), T.key(2027, 2, 15))
    }

    func testYearlyOnLeapDayKeepsAimingForTheLeapDay() {
        let rule = Recurrence.yearly.anchored(to: T.key(2028, 2, 29))
        XCTAssertEqual(rule.month, 2)
        XCTAssertEqual(rule.dayOfMonth, 29)
        let occurrences = rule.occurrences(startingAt: T.key(2028, 2, 29), count: 5)
        XCTAssertEqual(occurrences, [T.key(2028, 2, 29), T.key(2029, 2, 28), T.key(2030, 2, 28), T.key(2031, 2, 28), T.key(2032, 2, 29)])
    }

    func testAnchoringIsIdempotentAndDoesNotOverrideAnExplicitDay() {
        let explicit = Recurrence(unit: .month, dayOfMonth: 15)
        XCTAssertEqual(explicit.anchored(to: T.key(2026, 10, 3)).dayOfMonth, 15)
        let once = Recurrence.yearly.anchored(to: T.today)
        XCTAssertEqual(once.anchored(to: T.key(2030, 1, 1)), once)
    }

    // MARK: Weekly rules

    func testWeeklyOnSelectedWeekdays() {
        let rule = Recurrence(unit: .week, weekdays: [2, 4, 6]) // Mon Wed Fri
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(14)), T.oct(16)) // Wed -> Fri
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(16)), T.oct(19)) // Fri -> Mon
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(12)), T.oct(14)) // Mon -> Wed
    }

    func testWeeklyWithoutWeekdaysRepeatsOnTheSameWeekday() {
        XCTAssertEqual(Recurrence.weekly.nextOccurrence(after: T.oct(14)), T.oct(21))
    }

    func testEveryWeekdaySkipsTheWeekend() {
        XCTAssertEqual(Recurrence.weekdaysOnly.nextOccurrence(after: T.oct(16)), T.oct(19)) // Fri -> Mon
        XCTAssertEqual(Recurrence.weekdaysOnly.nextOccurrence(after: T.oct(17)), T.oct(19)) // Sat -> Mon
    }

    func testEveryWeekendCoversSaturdayAndSunday() {
        XCTAssertEqual(Recurrence.weekends.nextOccurrence(after: T.oct(14)), T.oct(17)) // Wed -> Sat
        XCTAssertEqual(Recurrence.weekends.nextOccurrence(after: T.oct(17)), T.oct(18)) // Sat -> Sun
        XCTAssertEqual(Recurrence.weekends.nextOccurrence(after: T.oct(18)), T.oct(24)) // Sun -> next Sat (week starts Monday)
    }

    func testEveryOtherWeekSkipsAWholeWeek() {
        let rule = Recurrence(unit: .week, interval: 2, weekdays: [2, 5]) // Mon, Thu
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(12)), T.oct(15)) // Mon -> Thu, same week
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(15)), T.oct(26)) // Thu -> Monday two weeks on
    }

    func testWeeklyDependsOnWhichDayStartsTheWeek() {
        let rule = Recurrence(unit: .week, interval: 2, weekdays: [1, 2]) // Sun, Mon
        // Monday-first weeks: Sun 18 belongs to the week of Mon 12, so after Mon 12 comes Sun 18.
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(12), firstWeekday: 2), T.oct(18))
        // Sunday-first weeks: Sun 11 and Mon 12 are together, so the next block is two weeks later.
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(12), firstWeekday: 1), T.oct(25))
    }

    func testWeekdayPickedOutsideTheSetStillFindsTheNextOne() {
        let rule = Recurrence(unit: .week, weekdays: [2]) // Mondays only, but due on a Wednesday
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(14)), T.oct(19))
    }

    // MARK: Ending

    func testARuleEndsAfterItsUntilDay() {
        let rule = Recurrence(unit: .day, until: T.oct(16))
        XCTAssertEqual(rule.nextOccurrence(after: T.oct(15)), T.oct(16))
        XCTAssertNil(rule.nextOccurrence(after: T.oct(16)))
        XCTAssertNil(rule.nextDue(after: T.oct(16), completedOn: T.oct(16)))
    }

    // MARK: Completing

    func testFinishingAnOverdueDailyTaskComesBackTomorrowNotYesterdayPlusOne() {
        let next = Recurrence.daily.nextDue(after: T.oct(9), completedOn: T.oct(14))
        XCTAssertEqual(next, T.oct(15))
    }

    func testFinishingAWeeklyTaskLateStaysOnItsWeekday() {
        let monday = Recurrence(unit: .week, weekdays: [2])
        // Due Monday 5th, ignored for nine days, finished Wednesday 14th: next is Monday 19th.
        XCTAssertEqual(monday.nextDue(after: T.oct(5), completedOn: T.oct(14)), T.oct(19))
    }

    func testFinishingEarlySkipsThisOccurrenceRatherThanRepeatingToday() {
        let friday = Recurrence(unit: .week, weekdays: [6])
        XCTAssertEqual(friday.nextDue(after: T.oct(16), completedOn: T.oct(14)), T.oct(23))
    }

    func testFinishingOnTheDueDayMovesToTheNext() {
        XCTAssertEqual(Recurrence.daily.nextDue(after: T.oct(14), completedOn: T.oct(14)), T.oct(15))
        XCTAssertEqual(Recurrence.monthly.nextDue(after: T.key(2026, 10, 14), completedOn: T.oct(14)), T.key(2026, 11, 14))
    }

    func testAMonthlyTaskFinishedMonthsLateJumpsToTheNextFutureDate() {
        let rule = Recurrence.monthly.anchored(to: T.key(2026, 1, 5))
        XCTAssertEqual(rule.nextDue(after: T.key(2026, 1, 5), completedOn: T.oct(14)), T.key(2026, 11, 5))
    }

    func testATaskIgnoredForTwentyYearsStillResolvesQuickly() {
        let long = T.key(2005, 1, 1)
        XCTAssertEqual(Recurrence.daily.nextDue(after: long, completedOn: T.today), T.today + 1)
        let weekly = Recurrence(unit: .week, weekdays: [2])
        let next = weekly.nextDue(after: T.key(2005, 1, 3), completedOn: T.today)
        XCTAssertEqual(next, T.oct(19))
        XCTAssertEqual(Day.weekday(of: next!), 2)
        let yearly = Recurrence.yearly.anchored(to: T.key(2005, 3, 1))
        XCTAssertEqual(yearly.nextDue(after: T.key(2005, 3, 1), completedOn: T.today), T.key(2027, 3, 1))
    }

    func testAfterCompletionCountsFromTheDayItWasDone() {
        let rule = Recurrence(unit: .day, interval: 3, mode: .afterCompletion)
        XCTAssertEqual(rule.nextDue(after: T.oct(1), completedOn: T.oct(14)), T.oct(17))
        let weeks = Recurrence(unit: .week, interval: 6, mode: .afterCompletion)
        XCTAssertEqual(weeks.nextDue(after: T.oct(1), completedOn: T.oct(14)), T.oct(14) + 42)
        let months = Recurrence(unit: .month, interval: 1, mode: .afterCompletion)
        XCTAssertEqual(months.nextDue(after: T.oct(1), completedOn: T.key(2026, 1, 31)), T.key(2026, 2, 28))
    }

    // MARK: Previews and first dates

    func testOccurrencesListsTheNextDates() {
        let rule = Recurrence(unit: .week, weekdays: [3, 5]) // Tue, Thu
        XCTAssertEqual(rule.occurrences(startingAt: T.oct(15), count: 4), [T.oct(15), T.oct(20), T.oct(22), T.oct(27)])
        XCTAssertEqual(rule.occurrences(startingAt: T.oct(15), count: 0), [])
    }

    func testOccurrencesStopWhenTheRuleEnds() {
        let rule = Recurrence(unit: .day, until: T.oct(16))
        XCTAssertEqual(rule.occurrences(startingAt: T.oct(14), count: 10), [T.oct(14), T.oct(15), T.oct(16)])
    }

    func testFirstOccurrenceForRulesWithoutADate() {
        XCTAssertEqual(Recurrence.daily.firstOccurrence(onOrAfter: T.today), T.today)
        XCTAssertEqual(Recurrence(unit: .week, weekdays: [2, 4]).firstOccurrence(onOrAfter: T.oct(15)), T.oct(19)) // Thu -> Mon
        XCTAssertEqual(Recurrence(unit: .week, weekdays: [4]).firstOccurrence(onOrAfter: T.today), T.today)
        XCTAssertEqual(Recurrence(unit: .month, dayOfMonth: 15).firstOccurrence(onOrAfter: T.today), T.oct(15))
        XCTAssertEqual(Recurrence(unit: .month, dayOfMonth: 10).firstOccurrence(onOrAfter: T.today), T.key(2026, 11, 10))
        XCTAssertEqual(Recurrence(unit: .year, dayOfMonth: 25, month: 12).firstOccurrence(onOrAfter: T.today), T.key(2026, 12, 25))
        XCTAssertEqual(Recurrence(unit: .year, dayOfMonth: 1, month: 3).firstOccurrence(onOrAfter: T.today), T.key(2027, 3, 1))
    }

    // MARK: Words and storage

    func testSummaries() {
        let calendar = T.utc
        XCTAssertEqual(Recurrence.daily.summary(calendar: calendar), "Every day")
        XCTAssertEqual(Recurrence(unit: .day, interval: 3).summary(calendar: calendar), "Every 3 days")
        XCTAssertEqual(Recurrence.weekdaysOnly.summary(calendar: calendar), "Every weekday")
        XCTAssertEqual(Recurrence.weekends.summary(calendar: calendar), "Every weekend")
        XCTAssertEqual(Recurrence(unit: .week, interval: 2, weekdays: [2, 4]).summary(calendar: calendar), "Every 2 weeks on Mon, Wed")
        XCTAssertEqual(Recurrence(unit: .month, dayOfMonth: 1).summary(calendar: calendar), "Every month on the 1st")
        XCTAssertEqual(Recurrence(unit: .month, dayOfMonth: 22).summary(calendar: calendar), "Every month on the 22nd")
        XCTAssertEqual(Recurrence(unit: .month, dayOfMonth: 13).summary(calendar: calendar), "Every month on the 13th")
        XCTAssertEqual(Recurrence(unit: .week, interval: 6, mode: .afterCompletion).summary(calendar: calendar), "6 weeks after completion")
        XCTAssertEqual(Recurrence.yearly.summary(calendar: calendar), "Every year")
    }

    func testSummaryListsWeekdaysFromTheStartOfTheWeek() {
        let rule = Recurrence(unit: .week, weekdays: [1, 2])
        XCTAssertEqual(rule.summary(firstWeekday: 2, calendar: T.utc), "Every week on Mon, Sun")
        XCTAssertEqual(rule.summary(firstWeekday: 1, calendar: T.utc), "Every week on Sun, Mon")
    }

    func testEncodingRoundTrips() {
        let rule = Recurrence(unit: .week, interval: 2, weekdays: [2, 6], mode: .afterCompletion, until: T.oct(30))
        XCTAssertEqual(Recurrence.decode(rule.encoded), rule)
        XCTAssertNil(Recurrence.decode(nil))
        XCTAssertNil(Recurrence.decode(Data()))
        XCTAssertNil(Recurrence.decode(Data("not json".utf8)))
    }

    func testInvalidWeekdaysAreDropped() {
        XCTAssertEqual(Recurrence(unit: .week, weekdays: [0, 2, 9]).weekdays, [2])
    }
}
