import XCTest
@testable import HeedCore

final class DayTests: XCTestCase {
    func testKeyMatchesFoundationForKnownDates() {
        let cases = [(1970, 1, 1), (2000, 2, 29), (2024, 12, 31), (2026, 10, 14), (2100, 3, 1), (1969, 12, 31)]
        for (y, m, d) in cases {
            let date = T.date(y, m, d)
            XCTAssertEqual(Day.key(year: y, month: m, day: d), Int((date.timeIntervalSince1970 / 86_400).rounded(.down)),
                           "\(y)-\(m)-\(d)")
        }
    }

    func testKeyAndYMDRoundTripOverCenturies() {
        for key in stride(from: -800_000, through: 800_000, by: 997) {
            let (y, m, d) = Day.ymd(key)
            XCTAssertEqual(Day.key(year: y, month: m, day: d), key)
            XCTAssertTrue((1...12).contains(m) && (1...Day.daysInMonth(year: y, month: m)).contains(d))
        }
    }

    func testWeekdays() {
        XCTAssertEqual(Day.weekday(of: 0), 5) // 1970-01-01 was a Thursday
        XCTAssertEqual(Day.weekday(of: T.today), 4) // Wednesday
        XCTAssertEqual(Day.weekday(of: T.oct(18)), 1) // Sunday
        XCTAssertEqual(Day.weekday(of: -1), 4)
    }

    func testWeekStartRespectsTheFirstWeekday() {
        XCTAssertEqual(Day.weekStart(of: T.today, firstWeekday: 2), T.oct(12)) // Monday
        XCTAssertEqual(Day.weekStart(of: T.today, firstWeekday: 1), T.oct(11)) // Sunday
        XCTAssertEqual(Day.weekStart(of: T.oct(18), firstWeekday: 2), T.oct(12)) // Sunday belongs to the week before
    }

    func testLeapYears() {
        XCTAssertTrue(Day.isLeapYear(2028))
        XCTAssertTrue(Day.isLeapYear(2000))
        XCTAssertFalse(Day.isLeapYear(2100))
        XCTAssertFalse(Day.isLeapYear(2026))
        XCTAssertEqual(Day.daysInMonth(year: 2028, month: 2), 29)
        XCTAssertEqual(Day.daysInMonth(year: 2026, month: 2), 28)
    }

    func testAddingMonthsClampsToTheEndOfShortMonths() {
        XCTAssertEqual(Day.adding(months: 1, to: T.key(2026, 1, 31)), T.key(2026, 2, 28))
        XCTAssertEqual(Day.adding(months: 1, to: T.key(2028, 1, 31)), T.key(2028, 2, 29))
        XCTAssertEqual(Day.adding(months: 2, to: T.key(2026, 1, 31)), T.key(2026, 3, 31))
        XCTAssertEqual(Day.adding(months: 12, to: T.key(2028, 2, 29)), T.key(2029, 2, 28))
    }

    func testAddingMonthsCrossesYearsBothWays() {
        XCTAssertEqual(Day.adding(months: 3, to: T.key(2026, 11, 15)), T.key(2027, 2, 15))
        XCTAssertEqual(Day.adding(months: -2, to: T.key(2026, 1, 15)), T.key(2025, 11, 15))
        XCTAssertEqual(Day.adding(months: -13, to: T.key(2026, 1, 15)), T.key(2024, 12, 15))
    }

    func testAddingMonthsCanAimForADayThatIsNotTheCurrentOne() {
        // A "the 31st" rule sitting on 28 February still means the 31st next month.
        XCTAssertEqual(Day.adding(months: 1, to: T.key(2026, 2, 28), aimingFor: 31), T.key(2026, 3, 31))
    }

    func testMonthStart() {
        XCTAssertEqual(Day.monthStart(of: T.today), T.oct(1))
    }

    func testKeyUsesTheLocalCalendarDate() {
        let kolkata = T.calendar("Asia/Kolkata")
        let late = T.date(2026, 10, 14, 23, 30, in: kolkata) // still the 14th locally, 18:00 UTC
        let early = T.date(2026, 10, 14, 0, 5, in: kolkata)
        XCTAssertEqual(Day.key(for: late, calendar: kolkata), Day.key(for: early, calendar: kolkata))
        XCTAssertEqual(Day.key(for: early, calendar: T.calendar("Pacific/Honolulu")), Day.key(for: early, calendar: kolkata) - 1)
    }

    func testDateForKeyRoundTripsAcrossDaylightSaving() {
        let ny = T.calendar("America/New_York")
        for (y, m, d) in [(2026, 3, 8), (2026, 3, 9), (2026, 11, 1), (2026, 11, 2)] {
            let key = T.key(y, m, d)
            XCTAssertEqual(Day.key(for: Day.date(for: key, calendar: ny), calendar: ny), key)
        }
    }

    func testATimeThatDoesNotExistLandsOnTheNextValidMoment() {
        // 2026-03-08 02:30 never happened in New York: the clocks went from 02:00 to 03:00.
        let ny = T.calendar("America/New_York")
        let moment = Day.date(for: T.key(2026, 3, 8), minutes: 150, calendar: ny)
        let parts = ny.dateComponents([.day, .hour, .minute], from: moment)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 3, "the first valid moment after the gap")
        XCTAssertEqual(parts.minute, 0)
    }

    func testARepeatedTimeUsesTheFirstOccurrence() {
        // 2026-11-01 01:30 happened twice in New York; the first one is 01:30 EDT = 05:30 UTC.
        let ny = T.calendar("America/New_York")
        let moment = Day.date(for: T.key(2026, 11, 1), minutes: 90, calendar: ny)
        XCTAssertEqual(moment, T.date(2026, 11, 1, 5, 30))
    }
}
