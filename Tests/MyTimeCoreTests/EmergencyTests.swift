import XCTest

@testable import MyTimeCore

/// Emergency pass (spec §5.5). Release values: 1 per week, 10 minutes of access, reason of at least 15 characters.
/// 2026-09-14 is a Monday; its week key is "2026-W38".
final class EmergencyTests: XCTestCase {
    func testEmergencyGrantsAccessOncePerWeekWhateverTheAppsModes() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.state.settings.apps[0].modes = []
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 1)
        let grant = try core.useEmergency(appID: discord, reason: "  teammate needs the build link  ")
        XCTAssertEqual(grant.kind, .emergency)
        XCTAssertEqual(grant.tokensSpent, 0)
        XCTAssertEqual(grant.note, "teammate needs the build link")
        XCTAssertEqual(grant.expiresAt, core.now.addingTimeInterval(600))
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 0)
        XCTAssertEqual(core.state.weekly["2026-W38"]?.emergencyUses, 1)
        XCTAssertEqual(core.state.history.last?.kind, .emergency)
        XCTAssertEqual(
            core.state.history.last?.text, "Emergency access to Discord — “teammate needs the build link”")
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "teammate needs the build link")) {
            XCTAssertEqual($0 as? EngineError, .emergencyUnavailable)
        }
    }

    func testEmergencyErrorsInOrder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        XCTAssertThrowsError(try core.useEmergency(appID: UUID(), reason: "teammate needs the build link")) {
            XCTAssertEqual($0 as? EngineError, .unknownApp)
        }
        core.state.weekly["2026-W38"] = WeeklyStats(emergencyUses: 1)
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "  abcdefghijklmn  ")) {
            XCTAssertEqual($0 as? EngineError, .reasonTooShort)
        }
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "abcdefghijklmno")) {
            XCTAssertEqual($0 as? EngineError, .emergencyUnavailable)
        }
        XCTAssertTrue(core.state.grants.isEmpty)
        core.state.weekly = [:]
        XCTAssertNoThrow(try core.useEmergency(appID: discord, reason: "abcdefghijklmno"))
    }

    func testEmergencyEndsFocusAndKeepsItsCredit() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.startFocus()
        sim.advance(100)
        sim.idle = 20
        _ = core.update(sim.input)
        _ = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.today.focusSeconds, 100, accuracy: 0.001)
        XCTAssertTrue(core.state.history.contains { $0.text == "Focus ended · 2 min" })
    }

    func testThePassReturnsMondayAtDayStart() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 20, 23))
        let discord = core.state.settings.apps[0].id
        _ = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        sim.advance(4 * 3600 + 59 * 60)  // Monday 03:59
        _ = core.update(sim.input)
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 0)
        sim.advance(60)  // Monday 04:00
        _ = core.update(sim.input)
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 1)
    }

    func testEmergencyAccessCannotBeExtended() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: 3)
        let discord = core.state.settings.apps[0].id
        let grant = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        sim.advance(595)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: grant.id))
    }
}
