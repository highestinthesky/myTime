import XCTest

@testable import MyTimeCore

final class SleepAndLaunchTests: XCTestCase {
    func testTimeAsleepIsNeverClaimable() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        sim.advance(60)
        _ = core.update(sim.input)
        _ = core.handleWillSleep(sim.input)
        XCTAssertTrue(core.isAway)
        // Asleep for 10 minutes: wall and continuous clocks move, uptime does not.
        sim.wall = sim.wall.addingTimeInterval(600)
        sim.continuous += 600
        sim.idle = 600
        _ = core.handleDidWake(sim.input)
        XCTAssertNotNil(core.state.focus)
        sim.advance(20)
        sim.idle = 0
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 60, accuracy: 0.001)
    }

    func testLongSleepEndsFocus() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        _ = core.handleWillSleep(sim.input)
        sim.wall = sim.wall.addingTimeInterval(3600)
        sim.continuous += 3600
        sim.idle = 3600
        _ = core.handleDidWake(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended · Mac was asleep")
        XCTAssertNil(core.runtime.sleepStartContinuous)
    }

    func testRestartAfterDowntimeEndsFocusWithoutCredit() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        state.focus = FocusSession(startedAt: date(2026, 9, 14, 9, 30), creditedSeconds: 1200)
        state.clock = TrustedClockState(
            lastWall: date(2026, 9, 14, 10).timeIntervalSince1970, lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 14, 10, 10), continuous: 50, uptime: 50, boot: "BOOT-B")
        _ = core.start(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertTrue(core.state.history.contains { $0.text == "Focus ended · myTime wasn't running" })
    }

    func testQuickRelaunchKeepsFocus() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        state.focus = FocusSession(startedAt: date(2026, 9, 14, 9, 30))
        state.clock = TrustedClockState(
            lastWall: date(2026, 9, 14, 10).timeIntervalSince1970, lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 14, 10, 0, 5), continuous: 5_005, uptime: 900, boot: "BOOT-A")
        _ = core.start(sim.input)
        XCTAssertNotNil(core.state.focus)
    }
}
