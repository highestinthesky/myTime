import XCTest
@testable import MyTimeCore

final class DurationFormatTests: XCTestCase {
    let enUS = Locale(identifier: "en_US")

    func testClockCountsUpToTheNextWholeSecond() {
        XCTAssertEqual(DurationFormat.clock(0), "0:00")
        XCTAssertEqual(DurationFormat.clock(4.2), "0:05")
        XCTAssertEqual(DurationFormat.clock(60), "1:00")
        XCTAssertEqual(DurationFormat.clock(3723), "1:02:03")
        XCTAssertEqual(DurationFormat.clock(-5), "0:00")
    }

    func testShort() {
        XCTAssertEqual(DurationFormat.short(45), "45 s")
        XCTAssertEqual(DurationFormat.short(59.6), "1 min")
        XCTAssertEqual(DurationFormat.short(720), "12 min")
        XCTAssertEqual(DurationFormat.short(3600), "1h")
        XCTAssertEqual(DurationFormat.short(7800), "2h 10m")
    }

    func testHourOfDayUsesPlainSpaces() {
        XCTAssertEqual(DurationFormat.hourOfDay(4, locale: enUS), "4:00 AM")
        XCTAssertEqual(DurationFormat.hourOfDay(16, locale: enUS), "4:00 PM")
    }

    func testSettingFormatting() {
        XCTAssertEqual(DurationFormat.setting(.weeklyAllowanceSeconds, 18000, locale: enUS), "5h")
        XCTAssertEqual(DurationFormat.setting(.quickLookMaxTokens, 3, locale: enUS), "3")
        XCTAssertEqual(DurationFormat.setting(.dayStartHour, 4, locale: enUS), "4:00 AM")
    }
}
