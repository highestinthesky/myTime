import XCTest

@testable import MyTimeCore

/// Labels for session times in the panel, the gate, and the booking window (spec §7.2, §7.3, §7.8).
/// "Today" and "Tomorrow" follow calendar days, not the 4 AM day start.
final class SessionTimeFormatTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let now = date(2026, 9, 14, 22)  // Monday 10 PM

    private func day(_ date: Date) -> String {
        DurationFormat.dayLabel(date, now: now, timeZone: testTZ, locale: locale)
    }

    private func start(_ date: Date) -> String {
        DurationFormat.sessionStart(date, now: now, timeZone: testTZ, locale: locale)
    }

    func testDayLabels() {
        XCTAssertEqual(day(date(2026, 9, 14, 23, 55)), "Today")
        XCTAssertEqual(day(date(2026, 9, 15, 0, 0)), "Tomorrow")
        XCTAssertEqual(day(date(2026, 9, 16, 9)), "Wed")
        XCTAssertEqual(day(date(2026, 9, 20, 9)), "Sun")
    }

    func testTimeOfDayAndSessionStart() {
        XCTAssertEqual(DurationFormat.timeOfDay(date(2026, 9, 14, 20, 5), timeZone: testTZ, locale: locale), "8:05 PM")
        XCTAssertEqual(start(date(2026, 9, 14, 22, 5)), "Today 10:05 PM")
        XCTAssertEqual(start(date(2026, 9, 15, 8, 0)), "Tomorrow 8:00 AM")
        XCTAssertEqual(start(date(2026, 9, 17, 19, 30)), "Thu 7:30 PM")
    }
}
