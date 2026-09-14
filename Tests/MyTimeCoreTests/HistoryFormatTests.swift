import XCTest

@testable import MyTimeCore

/// Day headings in the Settings History tab (spec §7.9), by calendar day.
final class HistoryFormatTests: XCTestCase {
    func testHistoryDayLabels() {
        let now = date(2026, 9, 14, 10)  // Monday
        func label(_ day: Date) -> String {
            DurationFormat.historyDay(day, now: now, timeZone: testTZ, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(label(date(2026, 9, 14, 0, 5)), "Today")
        XCTAssertEqual(label(date(2026, 9, 13, 23, 55)), "Yesterday")
        XCTAssertEqual(label(date(2026, 9, 10, 9)), "Thursday, Sep 10")
    }
}
