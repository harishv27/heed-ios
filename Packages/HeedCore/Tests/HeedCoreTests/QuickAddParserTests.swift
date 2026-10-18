import XCTest
@testable import HeedCore

final class QuickAddParserTests: XCTestCase {
    private func parse(_ text: String, now: Date = T.now) -> ParsedTask {
        QuickAddParser.parse(text, now: now, calendar: T.utc)
    }

    // MARK: Plain text

    func testPlainTextIsJustATitle() {
        let task = parse("Buy milk")
        XCTAssertEqual(task, ParsedTask(title: "Buy milk"))
        XCTAssertFalse(task.hasDetails)
    }

    func testEmptyAndWhitespaceInput() {
        XCTAssertEqual(parse("").title, "")
        XCTAssertEqual(parse("   \n ").title, "")
    }

    func testALineThatIsOnlyADateStaysAsTheTitle() {
        let task = parse("tomorrow")
        XCTAssertEqual(task.title, "tomorrow")
        XCTAssertNil(task.dueDay)
    }

    func testOriginalCaseIsKept() {
        XCTAssertEqual(parse("Call MUM TOMORROW").title, "Call MUM")
    }

    func testPunctuationAroundDatesDoesNotLeakIntoTheTitle() {
        let task = parse("Call mum, tomorrow, at 6pm.")
        XCTAssertEqual(task.title, "Call mum")
        XCTAssertEqual(task.dueDay, T.today + 1)
        XCTAssertEqual(task.minutes, 18 * 60)
    }

    // MARK: Relative days

    func testTodayAndTomorrow() {
        XCTAssertEqual(parse("Pay bill today").dueDay, T.today)
        XCTAssertEqual(parse("Pay bill tomorrow").dueDay, T.today + 1)
        XCTAssertEqual(parse("Pay bill tmr").dueDay, T.today + 1)
        XCTAssertEqual(parse("Pay bill day after tomorrow").dueDay, T.today + 2)
        XCTAssertEqual(parse("Pay bill day after tomorrow").title, "Pay bill")
    }

    func testTonightMeansTodayAtEight() {
        let task = parse("Dinner with Sam tonight")
        XCTAssertEqual(task.dueDay, T.today)
        XCTAssertEqual(task.minutes, 20 * 60)
        XCTAssertEqual(parse("Dinner tonight at 7pm").minutes, 19 * 60)
    }

    func testInSomeDays() {
        XCTAssertEqual(parse("Submit report in 3 days").dueDay, T.today + 3)
        XCTAssertEqual(parse("Submit report in a week").dueDay, T.today + 7)
        XCTAssertEqual(parse("Submit report in 2 weeks").dueDay, T.today + 14)
        XCTAssertEqual(parse("Renew in 2 months").dueDay, T.key(2026, 12, 14))
        XCTAssertEqual(parse("Renew in 1 year").dueDay, T.key(2027, 10, 14))
        XCTAssertEqual(parse("Submit report in 3 days").title, "Submit report")
    }

    func testInSomeHoursIsAnExactMoment() {
        let two = parse("Call back in 2 hours")
        XCTAssertEqual(two.dueDay, T.today)
        XCTAssertEqual(two.minutes, 12 * 60)
        XCTAssertEqual(two.title, "Call back")
        XCTAssertEqual(parse("Check oven in 30 min").minutes, 10 * 60 + 30)
    }

    func testInSomeHoursCanCrossMidnight() {
        let late = T.date(2026, 10, 14, 23, 30)
        let task = parse("Stretch in 2 hours", now: late)
        XCTAssertEqual(task.dueDay, T.today + 1)
        XCTAssertEqual(task.minutes, 90)
    }

    // MARK: Weekdays

    func testAWeekdayMeansTheNextOneAfterToday() {
        XCTAssertEqual(parse("Report friday").dueDay, T.oct(16))
        XCTAssertEqual(parse("Report wednesday").dueDay, T.oct(21), "today is Wednesday, so 'wednesday' is next week's")
        XCTAssertEqual(parse("Report monday").dueDay, T.oct(19))
        XCTAssertEqual(parse("Report on friday").title, "Report")
    }

    func testThisAndNextWeekday() {
        XCTAssertEqual(parse("Report this friday").dueDay, T.oct(16))
        XCTAssertEqual(parse("Report next friday").dueDay, T.oct(23))
        XCTAssertEqual(parse("Report next monday").dueDay, T.oct(19))
        XCTAssertEqual(parse("Report next sunday").dueDay, T.oct(25))
    }

    func testAbbreviationsNeedAContextWord() {
        XCTAssertEqual(parse("Meet fri").dueDay, nil)
        XCTAssertEqual(parse("Meet fri").title, "Meet fri")
        XCTAssertEqual(parse("Meet on fri").dueDay, T.oct(16))
        XCTAssertEqual(parse("Meet next thu").dueDay, T.oct(22))
        XCTAssertNil(parse("Watch the sun set").dueDay)
    }

    func testNextWeekAndNextMonth() {
        XCTAssertEqual(parse("Plan trip next week").dueDay, T.oct(19))
        XCTAssertEqual(parse("Plan trip next month").dueDay, T.key(2026, 11, 1))
    }

    func testWeekend() {
        XCTAssertEqual(parse("Hike this weekend").dueDay, T.oct(17))
        XCTAssertEqual(parse("Hike weekend").dueDay, T.oct(17))
        let sunday = T.date(2026, 10, 18, 9, 0)
        XCTAssertEqual(parse("Hike this weekend", now: sunday).dueDay, T.oct(18))
    }

    func testWeeksStartingOnSundayChangeNextWeek() {
        let sundayFirst = T.calendar(firstWeekday: 1)
        XCTAssertEqual(QuickAddParser.parse("Plan next week", now: T.now, calendar: sundayFirst).dueDay, T.oct(18))
    }

    // MARK: Calendar dates

    func testMonthAndDay() {
        XCTAssertEqual(parse("Doctor oct 25").dueDay, T.oct(25))
        XCTAssertEqual(parse("Doctor October 25th").dueDay, T.oct(25))
        XCTAssertEqual(parse("Doctor 25 oct").dueDay, T.oct(25))
        XCTAssertEqual(parse("Doctor 25th of october").dueDay, T.oct(25))
        XCTAssertEqual(parse("Doctor on dec 1").dueDay, T.key(2026, 12, 1))
        XCTAssertEqual(parse("Doctor oct 25").title, "Doctor")
    }

    func testADatePassedThisYearMeansNextYear() {
        XCTAssertEqual(parse("Doctor oct 5").dueDay, T.key(2027, 10, 5))
        XCTAssertEqual(parse("Doctor oct 14").dueDay, T.today, "today itself has not passed")
    }

    func testExplicitYearsAndISODates() {
        XCTAssertEqual(parse("Doctor oct 25 2027").dueDay, T.key(2027, 10, 25))
        XCTAssertEqual(parse("Doctor 25 oct 2028").dueDay, T.key(2028, 10, 25))
        XCTAssertEqual(parse("Visa expires 2026-12-01").dueDay, T.key(2026, 12, 1))
        XCTAssertNil(parse("Visa 2026-13-45").dueDay)
    }

    func testImpossibleDatesAreLeftAlone() {
        let task = parse("Party feb 30")
        XCTAssertNil(task.dueDay)
        XCTAssertEqual(task.title, "Party feb 30")
    }

    func testMonthNamesWithoutADayAreWords() {
        XCTAssertEqual(parse("Plan march madness").title, "Plan march madness")
        XCTAssertNil(parse("Plan march madness").dueDay)
        XCTAssertNil(parse("Buy 2 apples").dueDay)
    }

    func testTheOrdinalDay() {
        XCTAssertEqual(parse("Pay rent on the 20th").dueDay, T.oct(20))
        XCTAssertEqual(parse("Pay rent on the 10th").dueDay, T.key(2026, 11, 10))
        XCTAssertEqual(parse("Pay rent on the 20th").title, "Pay rent")
    }

    // MARK: Times

    func testTimesWithAMeridiem() {
        XCTAssertEqual(parse("Call dentist at 6pm").minutes, 18 * 60)
        XCTAssertEqual(parse("Call dentist at 6:30pm").minutes, 18 * 60 + 30)
        XCTAssertEqual(parse("Call dentist 6 pm").minutes, 18 * 60)
        XCTAssertEqual(parse("Call dentist 6:30 pm").minutes, 18 * 60 + 30)
        XCTAssertEqual(parse("Run 7am").minutes, 7 * 60)
        XCTAssertEqual(parse("Lunch 12pm").minutes, 12 * 60)
        XCTAssertEqual(parse("Wake 12am").minutes, 0)
    }

    func testTwentyFourHourTimesNeedAColon() {
        XCTAssertEqual(parse("Standup tomorrow 14:30").minutes, 14 * 60 + 30)
        XCTAssertEqual(parse("Standup tomorrow at 09:05").minutes, 9 * 60 + 5)
        XCTAssertNil(parse("Standup tomorrow at 25:00").minutes)
    }

    func testABareNumberIsNotATime() {
        let task = parse("Call Sam at 5")
        XCTAssertNil(task.minutes)
        XCTAssertEqual(task.title, "Call Sam at 5")
    }

    func testNamedTimes() {
        XCTAssertEqual(parse("Lunch tomorrow noon").minutes, 12 * 60)
        XCTAssertEqual(parse("Lock up midnight").minutes, 0)
    }

    func testPartsOfTheDayOnlyCountRightAfterADate() {
        let task = parse("Gym tomorrow morning")
        XCTAssertEqual(task.minutes, 9 * 60)
        XCTAssertEqual(task.title, "Gym")
        XCTAssertEqual(parse("Call friday afternoon").minutes, 15 * 60)
        XCTAssertEqual(parse("Dinner tomorrow evening").minutes, 18 * 60)
        let title = parse("Morning pages")
        XCTAssertEqual(title.title, "Morning pages")
        XCTAssertNil(title.minutes)
    }

    func testATimeWithNoDateMeansTheNextTimeItOccurs() {
        XCTAssertEqual(parse("Call dentist at 6pm").dueDay, T.today)
        XCTAssertEqual(parse("Call dentist at 8am").dueDay, T.today + 1, "8am has already passed at 10:00")
    }

    func testADateAndATimeInEitherOrder() {
        let a = parse("Review at 3pm friday")
        let b = parse("Review friday at 3pm")
        XCTAssertEqual(a.dueDay, T.oct(16))
        XCTAssertEqual(a.minutes, 15 * 60)
        XCTAssertEqual(a, b)
    }

    // MARK: Repeating

    func testDailyWeeklyMonthlyYearly() {
        XCTAssertEqual(parse("Journal every day").recurrence, .daily)
        XCTAssertEqual(parse("Journal daily").recurrence, .daily)
        XCTAssertEqual(parse("Journal everyday").recurrence, .daily)
        XCTAssertEqual(parse("Review weekly").recurrence, .weekly)
        XCTAssertEqual(parse("Review every week").recurrence, .weekly)
        XCTAssertEqual(parse("Rent monthly").recurrence?.unit, .month)
        XCTAssertEqual(parse("Birthday yearly").recurrence?.unit, .year)
        XCTAssertEqual(parse("Journal every day").title, "Journal")
    }

    func testARuleWithoutADateStartsToday() {
        XCTAssertEqual(parse("Journal every day").dueDay, T.today)
    }

    func testDailyAtATimeThatHasPassedStartsTomorrow() {
        XCTAssertEqual(parse("Stretch every day at 8am").dueDay, T.today + 1)
        XCTAssertEqual(parse("Stretch every day at 6pm").dueDay, T.today)
    }

    func testEveryWeekdayAndWeekend() {
        XCTAssertEqual(parse("Standup every weekday").recurrence, Recurrence.weekdaysOnly)
        XCTAssertEqual(parse("Standup weekdays").recurrence, Recurrence.weekdaysOnly)
        XCTAssertEqual(parse("Laundry every weekend").recurrence, Recurrence.weekends)
        XCTAssertEqual(parse("Standup every weekday 9:30").dueDay, T.oct(15), "9:30 has passed on Wednesday, so Thursday")
    }

    func testEveryNamedWeekdays() {
        let task = parse("Gym every mon wed fri at 7am")
        XCTAssertEqual(task.recurrence?.weekdays, [2, 4, 6])
        XCTAssertEqual(task.recurrence?.unit, .week)
        XCTAssertEqual(task.minutes, 7 * 60)
        XCTAssertEqual(task.dueDay, T.oct(16), "Wednesday 7am has passed, so the first one is Friday")
        XCTAssertEqual(task.title, "Gym")

        XCTAssertEqual(parse("Class every monday and thursday").recurrence?.weekdays, [2, 5])
        XCTAssertEqual(parse("Class every mon, wed & fri").recurrence?.weekdays, [2, 4, 6])
        XCTAssertEqual(parse("Class every tuesday").recurrence?.weekdays, [3])
    }

    func testEveryNUnits() {
        let days = parse("Water plants every 3 days").recurrence
        XCTAssertEqual(days?.unit, .day)
        XCTAssertEqual(days?.interval, 3)
        XCTAssertEqual(parse("Sync every 2 weeks").recurrence?.interval, 2)
        XCTAssertEqual(parse("Sync every 6 months").recurrence?.unit, .month)
        XCTAssertEqual(parse("Sync every 1 week").recurrence, .weekly)
        XCTAssertEqual(parse("Review every other week").recurrence, Recurrence(unit: .week, interval: 2))
        XCTAssertEqual(parse("Review biweekly").recurrence, Recurrence(unit: .week, interval: 2))
    }

    func testMonthlyOnADay() {
        let a = parse("Pay rent every month on the 1st")
        XCTAssertEqual(a.recurrence?.unit, .month)
        XCTAssertEqual(a.recurrence?.dayOfMonth, 1)
        XCTAssertEqual(a.dueDay, T.key(2026, 11, 1))
        XCTAssertEqual(a.title, "Pay rent")

        let b = parse("Pay rent every 15th")
        XCTAssertEqual(b.recurrence?.dayOfMonth, 15)
        XCTAssertEqual(b.dueDay, T.oct(15))
    }

    func testEveryWeekOnSomeDays() {
        let task = parse("Plan every 2 weeks on monday and friday")
        XCTAssertEqual(task.recurrence?.interval, 2)
        XCTAssertEqual(task.recurrence?.weekdays, [2, 6])
    }

    func testBangEveryRepeatsAfterCompletion() {
        let task = parse("Haircut every! 6 weeks")
        XCTAssertEqual(task.recurrence?.mode, .afterCompletion)
        XCTAssertEqual(task.recurrence?.interval, 6)
        XCTAssertEqual(task.recurrence?.unit, .week)
        XCTAssertEqual(task.title, "Haircut")
    }

    func testARuleWithADateIsAnchoredToIt() {
        let task = parse("Pay card monthly from oct 31")
        XCTAssertEqual(task.recurrence?.dayOfMonth, 31)
        XCTAssertEqual(task.dueDay, T.oct(31))
    }

    func testEveryWithNothingRecognisableStaysInTheTitle() {
        XCTAssertEqual(parse("Do every thing").title, "Do every thing")
        XCTAssertNil(parse("Do every thing").recurrence)
    }

    // MARK: Priority, lists, tags

    func testPriorities() {
        XCTAssertEqual(parse("Fix bug !1").priority, .high)
        XCTAssertEqual(parse("Fix bug !2").priority, .medium)
        XCTAssertEqual(parse("Fix bug !3").priority, .low)
        XCTAssertEqual(parse("Fix bug p1").priority, .high)
        XCTAssertEqual(parse("!1 Fix bug").title, "Fix bug")
        XCTAssertEqual(parse("Fix bug").priority, .none)
    }

    func testOnlyTheFirstPriorityCounts() {
        let task = parse("Fix bug !1 !3")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.title, "Fix bug !3")
    }

    func testListAndTags() {
        let task = parse("Buy eggs #groceries @errand @shop")
        XCTAssertEqual(task.title, "Buy eggs")
        XCTAssertEqual(task.listName, "groceries")
        XCTAssertEqual(task.tags, ["errand", "shop"])
    }

    func testDuplicateTagsAreCollapsed() {
        XCTAssertEqual(parse("Buy eggs @Shop @shop").tags, ["Shop"])
    }

    func testALoneHashOrAtIsText() {
        XCTAssertEqual(parse("Issue # 42").title, "Issue # 42")
        XCTAssertEqual(parse("Email @ work").title, "Email @ work")
    }

    func testEverythingAtOnce() {
        let task = parse("Submit expense report friday 5pm every week !1 #work @finance")
        XCTAssertEqual(task.title, "Submit expense report")
        XCTAssertEqual(task.dueDay, T.oct(16))
        XCTAssertEqual(task.minutes, 17 * 60)
        XCTAssertEqual(task.recurrence?.unit, .week)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.listName, "work")
        XCTAssertEqual(task.tags, ["finance"])
        XCTAssertTrue(task.hasDetails)
    }

    // MARK: Time zones

    func testTodayFollowsTheCalendarsTimeZone() {
        // 22:00 UTC on the 14th is already the 15th in Kolkata.
        let moment = T.date(2026, 10, 14, 22, 0)
        let kolkata = T.calendar("Asia/Kolkata")
        let task = QuickAddParser.parse("Pay bill today", now: moment, calendar: kolkata)
        XCTAssertEqual(task.dueDay, T.oct(15))
    }

    func testClockHelper() {
        XCTAssertEqual(QuickAddParser.clock("6pm"), 1080)
        XCTAssertEqual(QuickAddParser.clock("6:30am"), 390)
        XCTAssertEqual(QuickAddParser.clock("13:05"), 785)
        XCTAssertNil(QuickAddParser.clock("13pm"))
        XCTAssertNil(QuickAddParser.clock("0pm"))
        XCTAssertNil(QuickAddParser.clock("6"))
        XCTAssertNil(QuickAddParser.clock("6:5"))
        XCTAssertNil(QuickAddParser.clock("6:75"))
        XCTAssertNil(QuickAddParser.clock("am"))
        XCTAssertNil(QuickAddParser.clock("tomorrow"))
    }
}
