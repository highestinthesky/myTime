import XCTest
@testable import MyTimeCore

final class DailyResetTests: XCTestCase {
    func testTokensAndProgressClearAtDayStart() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 50), tokens: 3)
        core.state.progressSeconds = 120
        sim.advance(9 * 60)  // 3:59
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 3)
        sim.advance(2 * 60)  // 4:01
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 0)
        XCTAssertEqual(core.state.progressSeconds, 0)
        XCTAssertEqual(core.state.tokensDayKey, "2026-09-14")
        XCTAssertEqual(core.state.history.filter { $0.kind == .dayReset }.count, 1)
        XCTAssertEqual(core.state.history.last?.text, "New day · 3 unused tokens cleared")
        sim.advance(60)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.history.filter { $0.kind == .dayReset }.count, 1)
    }

    func testStartAfterOvernightShutdownClearsYesterdaysTokens() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 23), timeZone: testTZ)
        state.tokens = 5
        state.clock = TrustedClockState(
            lastWall: date(2026, 9, 14, 23).timeIntervalSince1970,
            lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 15, 9), continuous: 20, uptime: 20, boot: "BOOT-B")
        let result = core.start(sim.input)
        XCTAssertEqual(core.now, date(2026, 9, 15, 9))
        XCTAssertEqual(core.state.tokens, 0)
        XCTAssertEqual(result.nextWakeUp, WakeUp(date: date(2026, 9, 16, 4), critical: false))
    }

    func testEmptyDayKeyForcesResetWithoutHistoryWhenNoTokens() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.state.tokensDayKey = ""
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokensDayKey, "2026-09-14")
        XCTAssertTrue(core.state.history.filter { $0.kind == .dayReset }.isEmpty)
    }

    func testVestMintsTokensAndCarriesRemainder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.vest(1000)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.state.progressSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(core.today.focusSeconds, 1000, accuracy: 0.001)
        XCTAssertEqual(core.today.tokensEarned, 1)
        XCTAssertEqual(core.state.history.last?.text, "Earned a token")
        XCTAssertEqual(core.secondsToNextToken, 800, accuracy: 0.001)
    }
}
