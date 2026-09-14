import XCTest
@testable import MyTimeCore

final class SettingKeyTests: XCTestCase {
    func testDefaultsMatchSpec() {
        XCTAssertEqual(SettingKey.allCases.count, 19)
        XCTAssertEqual(SettingKey.focusSecondsPerToken.defaultValue, 900)
        XCTAssertEqual(SettingKey.dayStartHour.defaultValue, 4)
        XCTAssertEqual(SettingKey.quickLookSecondsPerToken.defaultValue, 30)
        XCTAssertEqual(SettingKey.quickLookMaxTokens.defaultValue, 3)
        XCTAssertEqual(SettingKey.gatePauseSeconds.defaultValue, 5)
        XCTAssertEqual(SettingKey.weeklyAllowanceSeconds.defaultValue, 18000)
        XCTAssertEqual(SettingKey.bookingLeadSeconds.defaultValue, 600)
        XCTAssertEqual(SettingKey.looseningDelaySeconds.defaultValue, 86400)
        XCTAssertEqual(SettingKey.focusSecondsPerToken.title, "Focus per token")
        XCTAssertEqual(SettingKey.dayStartHour.unit, .hourOfDay)
        XCTAssertEqual(SettingKey.bookingLeadSeconds.group, .sessions)
    }

    func testEveryDefaultIsInsideItsRange() {
        for key in SettingKey.allCases {
            XCTAssertTrue(key.range.contains(key.defaultValue), key.rawValue)
        }
    }

    func testLooseningDirections() {
        XCTAssertEqual(SettingKey.focusSecondsPerToken.looserWhen, .lower)
        XCTAssertEqual(SettingKey.weeklyAllowanceSeconds.looserWhen, .higher)
        XCTAssertEqual(SettingKey.dayStartHour.looserWhen, .anyChange)
        XCTAssertEqual(SettingKey.replyTokenCost.looserWhen, .lower)
        XCTAssertEqual(SettingKey.looseningDelaySeconds.looserWhen, .lower)
    }

    func testClamp() {
        XCTAssertEqual(SettingKey.quickLookMaxTokens.clamp(99), 10)
        XCTAssertEqual(SettingKey.dayStartHour.clamp(-3), 0)
        XCTAssertEqual(SettingKey.gatePauseSeconds.clamp(7), 7)
    }

    func testReleaseConstants() {
        XCTAssertFalse(Constants.isDev)
        XCTAssertEqual(Constants.extendWindow, 10)
        XCTAssertEqual(Constants.focusCheckInterval, 30)
        XCTAssertEqual(Constants.bookingHeadsUp, 300)
        XCTAssertEqual(Constants.bookingStartStepSeconds, 300)
        XCTAssertEqual(Constants.gateTimeout, 60)
        XCTAssertEqual(Constants.historyCap, 500)
    }
}
