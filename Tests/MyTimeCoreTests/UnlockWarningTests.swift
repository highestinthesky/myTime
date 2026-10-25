import XCTest

@testable import MyTimeCore

final class UnlockWarningTests: XCTestCase {
    func testWarnsOnceThirtySecondsBeforeTheEnd() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        f.sim.running = [f.discord]
        try f.buy(300)
        XCTAssertFalse(f.advance(to: date(2026, 9, 14, 14, 4, 29)).effects.contains(.unlockWarning))
        XCTAssertTrue(f.advance(to: date(2026, 9, 14, 14, 4, 30)).effects.contains(.unlockWarning))
        XCTAssertEqual(f.core.state.unlock?.warned, true)
        XCTAssertFalse(f.advance(to: date(2026, 9, 14, 14, 4, 31)).effects.contains(.unlockWarning))
    }

    func testWaitsForACoveredAppToRun() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        XCTAssertFalse(f.advance(to: date(2026, 9, 14, 14, 4, 30)).effects.contains(.unlockWarning))
        XCTAssertEqual(f.core.state.unlock?.warned, false)
        f.sim.running = [f.textEdit]
        XCTAssertTrue(f.advance(to: date(2026, 9, 14, 14, 4, 40)).effects.contains(.unlockWarning))
    }

    func testRestartDoesNotRepeatTheWarning() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        f.sim.running = [f.discord]
        try f.buy(300)
        XCTAssertTrue(f.advance(to: date(2026, 9, 14, 14, 4, 30)).effects.contains(.unlockWarning))
        f.sim.advance(10)
        var restarted = EngineCore(state: f.core.state, timeZone: testTZ)
        let started = restarted.start(f.sim.input)
        XCTAssertFalse(started.effects.contains(.unlockWarning))
        f.sim.advance(20)
        let ended = restarted.update(f.sim.input)
        XCTAssertTrue(ended.effects.contains(.terminateIfNotAllowed(appID: f.discord)))
        XCTAssertTrue(ended.effects.contains(.unlockEnded))
    }

    func testLateWakeWithUnderFiveSecondsLeftSkipsTheWarning() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        f.sim.running = [f.discord]
        try f.buy(300)
        f.advance(to: date(2026, 9, 14, 14, 2))
        _ = f.core.handleWillSleep(f.sim.input)
        f.sim.wall = date(2026, 9, 14, 14, 4, 57)
        f.sim.continuous += 177
        let woke = f.core.handleDidWake(f.sim.input)
        XCTAssertFalse(woke.effects.contains(.unlockWarning))
        let ended = f.advance(to: date(2026, 9, 14, 14, 5))
        XCTAssertFalse(ended.effects.contains(.unlockWarning))
        XCTAssertTrue(ended.effects.contains(.terminateIfNotAllowed(appID: f.discord)))
    }

    func testShortUnlockWarnsAtTheHalfwayPoint() {
        let unlock = ActiveUnlock(
            appID: UUID(), startedAt: date(2026, 9, 14, 14), endsAt: date(2026, 9, 14, 14, 0, 40),
            lengthSeconds: 40, multiplier: 1, cost: 1, dayKey: "2026-09-14", warned: false, endedAt: nil)
        XCTAssertEqual(unlock.warningAt, date(2026, 9, 14, 14, 0, 20))
    }

    func testWakeUpsCoverTheWarningAndTheEnd() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        let bought = f.core.update(f.sim.input)
        XCTAssertEqual(bought.nextWakeUp, WakeUp(date: date(2026, 9, 14, 14, 4, 30), critical: false))
        f.sim.running = [f.discord]
        let warned = f.advance(to: date(2026, 9, 14, 14, 4, 30))
        XCTAssertEqual(warned.nextWakeUp, WakeUp(date: date(2026, 9, 14, 14, 5), critical: true))
    }
}
