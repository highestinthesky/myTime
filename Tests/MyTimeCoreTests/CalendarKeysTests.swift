import XCTest
@testable import MyTimeCore

final class CalendarKeysTests: XCTestCase {
    func testDayKeyFlipsAtDayStartHour() {
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 3, 59), dayStartHour: 4, timeZone: testTZ), "2026-09-13")
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 4, 0), dayStartHour: 4, timeZone: testTZ), "2026-09-14")
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 0, 30), dayStartHour: 0, timeZone: testTZ), "2026-09-14")
    }

    func testWeekStartsMondayAtDayStartHour() {
        let sundayNight = CalendarKeys.weekKey(date(2026, 9, 13, 23), dayStartHour: 4, timeZone: testTZ)
        let mondayEarly = CalendarKeys.weekKey(date(2026, 9, 14, 3), dayStartHour: 4, timeZone: testTZ)
        let mondayLater = CalendarKeys.weekKey(date(2026, 9, 14, 4), dayStartHour: 4, timeZone: testTZ)
        XCTAssertEqual(sundayNight, mondayEarly)
        XCTAssertNotEqual(mondayEarly, mondayLater)
        XCTAssertEqual(mondayLater, "2026-W38")
    }

    func testNextDayStartIsStrictlyAfter() {
        XCTAssertEqual(
            CalendarKeys.nextDayStart(after: date(2026, 9, 14, 3), dayStartHour: 4, timeZone: testTZ),
            date(2026, 9, 14, 4))
        XCTAssertEqual(
            CalendarKeys.nextDayStart(after: date(2026, 9, 14, 5), dayStartHour: 4, timeZone: testTZ),
            date(2026, 9, 15, 4))
        XCTAssertEqual(
            CalendarKeys.nextDayStart(after: date(2026, 9, 14, 4), dayStartHour: 4, timeZone: testTZ),
            date(2026, 9, 15, 4))
    }

    func testNextWeekStart() {
        XCTAssertEqual(
            CalendarKeys.nextWeekStart(after: date(2026, 9, 13, 12), dayStartHour: 4, timeZone: testTZ),
            date(2026, 9, 14, 4))
        XCTAssertEqual(
            CalendarKeys.nextWeekStart(after: date(2026, 9, 14, 5), dayStartHour: 4, timeZone: testTZ),
            date(2026, 9, 21, 4))
    }
}
