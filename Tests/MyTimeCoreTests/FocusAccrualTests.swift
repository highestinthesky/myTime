import XCTest

@testable import MyTimeCore

final class FocusAccrualTests: XCTestCase {
    /// Engine at 10:00 with a focus session just started. `Sim` starts at uptime 1000 with idle 0.
    private func focusing(tokens: Int = 0) -> (EngineCore, Sim) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: tokens)
        core.startFocus()
        return (core, sim)
    }

    func testNothingIsCreditedWithoutAFocusSession() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertEqual(core.state.progressSeconds, 0)
    }

    func testStartFocusRecordsHistoryAndIsIdempotent() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        let started = core.state.focus?.startedAt
        core.startFocus()
        XCTAssertEqual(core.state.focus?.startedAt, started)
        XCTAssertEqual(core.state.history.filter { $0.kind == .focusStarted }.count, 1)
        XCTAssertEqual(core.state.history.last?.text, "Started focus")
    }

    func testTimeBeforeTheLastInputVestsAndTheRestStaysUnvested() {
        var (core, sim) = focusing()
        sim.advance(60)
        sim.idle = 10
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 50, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(core.state.focus?.creditedSeconds ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(core.secondsToNextToken, 840, accuracy: 0.001)
    }

    func testTokensMintAndProgressCarriesAcrossSessions() {
        var (core, sim) = focusing()
        sim.advance(1000)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.state.progressSeconds, 100, accuracy: 0.001)
        core.endFocus()
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended · 17 min")
        sim.advance(300)
        _ = core.update(sim.input)
        core.startFocus()
        sim.advance(800)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertEqual(core.state.progressSeconds, 0, accuracy: 0.001)
    }

    func testEndFocusVestsUnvestedTime() {
        var (core, sim) = focusing()
        sim.advance(40)
        sim.idle = 15
        _ = core.update(sim.input)
        core.endFocus()
        XCTAssertEqual(core.today.focusSeconds, 40, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 0)
    }

    func testCrossingTheIdleThresholdDiscardsTheIdleMinutes() {
        var (core, sim) = focusing()
        sim.advance(100)
        _ = core.update(sim.input)
        sim.advance(300)
        sim.idle = 300
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        XCTAssertEqual(core.today.focusSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 0)
        XCTAssertEqual(core.runtime.awayStartUptime ?? 0, sim.uptime - 300, accuracy: 0.001)
    }

    func testNoCreditForIntervalsThatStartWithABlockedAppRunning() {
        var (core, sim) = focusing()
        let discord = core.state.settings.apps[0].id
        sim.running = [discord]
        sim.advance(1)
        _ = core.update(sim.input)
        sim.advance(100)
        _ = core.update(sim.input)
        sim.running = []
        sim.advance(1)
        _ = core.update(sim.input)
        sim.advance(10)
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 11, accuracy: 0.001)
    }

    func testLockingEntersAwayImmediatelyAndUnlockingReturns() {
        var (core, sim) = focusing()
        sim.advance(60)
        _ = core.update(sim.input)
        sim.locked = true
        sim.advance(10)
        sim.idle = 10
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        sim.advance(170)
        sim.idle = 180
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        sim.locked = false
        sim.idle = 0
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.focusSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 181, accuracy: 0.001)
    }

    func testShortAwayGapsAreNotClaimable() {
        var (core, sim) = focusing()
        sim.locked = true
        sim.advance(30)
        sim.idle = 30
        _ = core.update(sim.input)
        sim.locked = false
        sim.idle = 0
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
    }

    func testLongAbsenceEndsFocusButTheGapIsStillRecorded() {
        var (core, sim) = focusing()
        sim.advance(10)
        _ = core.update(sim.input)
        sim.advance(300)
        sim.idle = 300
        _ = core.update(sim.input)
        sim.advance(1500)
        sim.idle = 1800
        _ = core.update(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended after 30 min away")
        XCTAssertTrue(core.isAway)
        sim.advance(10)
        sim.idle = 0
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 1810, accuracy: 0.001)
        XCTAssertEqual(core.today.focusSeconds, 10, accuracy: 0.001)
    }

    func testFocusKeepsTheEngineWakingEveryCheckInterval() {
        var (core, sim) = focusing()
        sim.advance(1)
        let result = core.update(sim.input)
        XCTAssertEqual(
            result.nextWakeUp, WakeUp(date: core.now.addingTimeInterval(Constants.focusCheckInterval), critical: false))
    }
}
