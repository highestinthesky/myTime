import XCTest

@testable import MyTimeCore

/// Typed setting values in the General tab (spec §7.9): any whole number in a unit, shown exactly.
/// Tests see release ranges.
final class SettingInputTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    func testNaturalUnitIsTheLargestThatFitsExactly() {
        XCTAssertEqual(DurationUnit.natural(for: 18000), .hours)
        XCTAssertEqual(DurationUnit.natural(for: 5400), .minutes)
        XCTAssertEqual(DurationUnit.natural(for: 900), .minutes)
        XCTAssertEqual(DurationUnit.natural(for: 915), .seconds)
        XCTAssertEqual(DurationUnit.natural(for: 15), .seconds)
        XCTAssertEqual(DurationUnit.natural(for: 0), .minutes)
    }

    func testExactDurations() {
        XCTAssertEqual(DurationFormat.exact(0), "0 s")
        XCTAssertEqual(DurationFormat.exact(45), "45 s")
        XCTAssertEqual(DurationFormat.exact(900), "15 min")
        XCTAssertEqual(DurationFormat.exact(915), "15 min 15 s")
        XCTAssertEqual(DurationFormat.exact(3600), "1h")
        XCTAssertEqual(DurationFormat.exact(5400), "1h 30m")
        XCTAssertEqual(DurationFormat.exact(3605), "1h 0m 5s")
    }

    func testSettingValuesAreShownExactly() {
        XCTAssertEqual(DurationFormat.setting(.focusSecondsPerToken, 915, locale: enUS), "15 min 15 s")
        XCTAssertEqual(DurationFormat.setting(.weeklyAllowanceSeconds, 5400, locale: enUS), "1h 30m")
    }

    func testRangeMessages() {
        XCTAssertEqual(SettingKey.focusSecondsPerToken.rangeMessage(locale: enUS), "Choose between 5 min and 1h.")
        XCTAssertEqual(SettingKey.replyPerDay.rangeMessage(locale: enUS), "Choose between 0 and 10.")
    }
}
