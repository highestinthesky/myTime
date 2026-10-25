import XCTest

@testable import MyTimeCore

final class UnlockTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testBuyingSpendsTokensAndCoversEveryUnlockApp() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 12)
        let unlock = try f.buy(300)
        XCTAssertEqual(f.core.state.tokens, 7)
        XCTAssertEqual(unlock.multiplier, 1)
        XCTAssertEqual(unlock.cost, 5)
        XCTAssertEqual(unlock.endsAt, date(2026, 9, 14, 14, 5))
        XCTAssertEqual(f.core.activeUnlock, unlock)
        XCTAssertTrue(f.core.isAllowed(appID: f.discord))
        XCTAssertTrue(f.core.isAllowed(appID: f.textEdit))
        XCTAssertFalse(f.core.isAllowed(appID: f.notes))
        XCTAssertEqual(f.core.today.unlocks, 1)
        XCTAssertEqual(f.core.today.unlockTokens, 5)
        XCTAssertEqual(f.core.today.tokensSpent, 5)
        XCTAssertEqual(f.core.today.highestMultiplier, 1)
        let week = CalendarKeys.weekKey(f.core.now, dayStartHour: 4, timeZone: testTZ)
        XCTAssertEqual(f.core.state.weekly[week]?.unlocks, 1)
        XCTAssertEqual(f.core.state.history.last?.text, "Unlock in Discord · 5 min · 1× · 5 ◆")
    }

    func testBuyErrorsInOrder() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 3)
        func expect(_ error: EngineError, app: UUID, length: Int, cost: Int) {
            XCTAssertThrowsError(try f.core.buyUnlock(appID: app, lengthSeconds: length, expectedCost: cost)) {
                XCTAssertEqual($0 as? EngineError, error)
            }
        }
        expect(.unknownApp, app: UUID(), length: 60, cost: 1)
        expect(.modeNotAllowed, app: f.notes, length: 60, cost: 1)
        f.core.startFocus()
        expect(.focusActive, app: f.discord, length: 60, cost: 1)
        f.core.endFocus()
        expect(.invalidLength, app: f.discord, length: 90, cost: 1)
        expect(.priceChanged, app: f.discord, length: 60, cost: 2)
        expect(.notEnoughTokens, app: f.discord, length: 300, cost: 5)
        try f.buy(60)
        expect(.unlockActive, app: f.textEdit, length: 60, cost: 2)
        XCTAssertEqual(f.core.state.tokens, 2)
    }

    func testStreakTableFromTheProposal() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 40)
        XCTAssertEqual(try f.buy(300).cost, 5)
        f.advance(to: date(2026, 9, 14, 14, 8))
        XCTAssertEqual(try f.buy(300).cost, 10)
        f.advance(to: date(2026, 9, 14, 14, 16))
        let third = try f.buy(120)
        XCTAssertEqual(third.multiplier, 4)
        XCTAssertEqual(third.cost, 8)
        f.advance(to: date(2026, 9, 14, 14, 21))
        let fourth = try f.buy(60)
        XCTAssertEqual(fourth.multiplier, 8)
        XCTAssertEqual(fourth.cost, 8)
        f.advance(to: date(2026, 9, 14, 14, 40))
        let fifth = try f.buy(300)
        XCTAssertEqual(fifth.multiplier, 1)
        XCTAssertEqual(f.core.state.tokens, 4)
        XCTAssertEqual(f.core.today.highestMultiplier, 8)
    }

    func testHistoryNotesTheGapSinceTheLastUnlock() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 20)
        try f.buy(300)
        f.advance(to: date(2026, 9, 14, 14, 8))
        try f.buy(60)
        XCTAssertEqual(f.core.state.history.last?.text, "Unlock in Discord · 1 min · 2× · 2 ◆ · 3 min after the last")
    }

    func testExpiryQuitsCoveredAppsAndRecordsTheStreak() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        let result = f.advance(to: date(2026, 9, 14, 14, 5))
        XCTAssertTrue(result.effects.contains(.terminateIfNotAllowed(appID: f.discord)))
        XCTAssertTrue(result.effects.contains(.terminateIfNotAllowed(appID: f.textEdit)))
        XCTAssertFalse(result.effects.contains(.terminateIfNotAllowed(appID: f.notes)))
        XCTAssertTrue(result.effects.contains(.unlockEnded))
        XCTAssertNil(f.core.state.unlock)
        let streak = UnlockStreak(lastMultiplier: 1, lastEnd: date(2026, 9, 14, 14, 5), dayKey: "2026-09-14")
        XCTAssertEqual(f.core.state.unlockStreak, streak)
        XCTAssertEqual(f.core.state.history.last?.text, "Unlock ended · 5 min used")
        XCTAssertEqual(f.core.today.unlockSeconds, 300, accuracy: 0.001)
    }

    func testEndingEarlyStartsTheGapAtOnce() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 20)
        try f.buy(600)
        f.advance(to: date(2026, 9, 14, 14, 2))
        f.core.endUnlock()
        let result = f.core.update(f.sim.input)
        XCTAssertTrue(result.effects.contains(.terminateIfNotAllowed(appID: f.discord)))
        XCTAssertTrue(result.effects.contains(.terminateIfNotAllowed(appID: f.textEdit)))
        XCTAssertTrue(result.effects.contains(.unlockEnded))
        XCTAssertNil(f.core.activeUnlock)
        XCTAssertEqual(f.core.state.tokens, 10)
        XCTAssertEqual(f.core.state.unlockStreak?.lastEnd, date(2026, 9, 14, 14, 2))
        XCTAssertEqual(f.core.state.history.last?.text, "Unlock ended early · 2 min used")
        f.advance(to: date(2026, 9, 14, 14, 16))
        XCTAssertEqual(f.core.unlockQuote(at: f.core.now).multiplier, 2)
        f.advance(to: date(2026, 9, 14, 14, 18))
        XCTAssertEqual(f.core.unlockQuote(at: f.core.now).multiplier, 1)
    }

    func testANewDayStartsAtOneTimes() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 3, 55), tokens: 20)
        try f.buy(600)
        f.advance(to: date(2026, 9, 14, 4, 5))
        f.core.state.tokens = 10
        f.advance(to: date(2026, 9, 14, 4, 10))
        XCTAssertEqual(f.core.unlockQuote(at: f.core.now).multiplier, 1)
        XCTAssertEqual(try f.buy(60).cost, 1)
    }

    func testDayResetWhileTheGateIsOpenRefusesThePurchase() {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 3, 59), tokens: 5)
        let shown = f.core.unlockQuote(at: f.core.now).options[0].cost
        f.advance(to: date(2026, 9, 14, 4, 0, 30))
        XCTAssertThrowsError(try f.core.buyUnlock(appID: f.discord, lengthSeconds: 60, expectedCost: shown)) {
            XCTAssertEqual($0 as? EngineError, .notEnoughTokens)
        }
        XCTAssertEqual(f.core.state.tokens, 0)
        XCTAssertNil(f.core.state.unlock)
    }

    func testPriceThatChangedSinceItWasShownIsRefused() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 20)
        try f.buy(60)
        f.advance(to: date(2026, 9, 14, 14, 10))
        let shown = f.core.unlockQuote(at: f.core.now).options[0].cost
        XCTAssertEqual(shown, 2)
        f.advance(to: date(2026, 9, 14, 14, 16))
        XCTAssertThrowsError(try f.core.buyUnlock(appID: f.discord, lengthSeconds: 60, expectedCost: shown)) {
            XCTAssertEqual($0 as? EngineError, .priceChanged)
        }
        XCTAssertEqual(f.core.state.tokens, 19)
    }

    func testUnlockThatEndsDuringSleepClosesAppsAtWake() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        f.sim.running = [f.discord]
        try f.buy(300)
        f.advance(to: date(2026, 9, 14, 14, 2))
        _ = f.core.handleWillSleep(f.sim.input)
        f.sim.wall = date(2026, 9, 14, 14, 17)
        f.sim.continuous += 900
        let woke = f.core.handleDidWake(f.sim.input)
        XCTAssertTrue(woke.effects.contains(.terminateIfNotAllowed(appID: f.discord)))
        XCTAssertFalse(woke.effects.contains(.unlockWarning))
        XCTAssertEqual(f.core.state.unlockStreak?.lastEnd, date(2026, 9, 14, 14, 5))
        f.sim.running = []
        f.advance(to: date(2026, 9, 14, 14, 21))
        XCTAssertEqual(f.core.unlockQuote(at: f.core.now).multiplier, 1)
    }

    func testRestartKeepsTheSameEnd() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        let unlock = try f.buy(300)
        f.sim.advance(60)
        var restarted = EngineCore(state: f.core.state, timeZone: testTZ)
        _ = restarted.start(f.sim.input)
        XCTAssertEqual(restarted.activeUnlock?.endsAt, unlock.endsAt)
        XCTAssertTrue(restarted.isAllowed(appID: f.discord))
    }

    func testWallClockJumpDoesNotShortenTheUnlock() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        f.sim.wall = f.sim.wall.addingTimeInterval(3 * 3600 + 60)
        f.sim.continuous += 60
        f.sim.uptime += 60
        _ = f.core.update(f.sim.input)
        let unlock = try XCTUnwrap(f.core.activeUnlock)
        XCTAssertEqual(f.core.remaining(of: unlock), 240, accuracy: 1)
    }

    func testBookingKeepsItsAppsOpenWhenTheUnlockEnds() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        let booking = Booking(
            start: date(2026, 9, 14, 14, 3), durationSeconds: 3600, createdAt: date(2026, 9, 14, 13))
        f.core.state.bookings.append(booking)
        f.sim.running = [f.discord]
        try f.buy(300)
        let nearEnd = f.advance(to: date(2026, 9, 14, 14, 4, 30))
        XCTAssertFalse(nearEnd.effects.contains(.unlockWarning))
        f.advance(to: date(2026, 9, 14, 14, 5))
        XCTAssertTrue(f.core.isAllowed(appID: f.discord))
        XCTAssertFalse(f.core.isAllowed(appID: f.textEdit))
        XCTAssertEqual(f.core.state.unlockStreak?.lastEnd, date(2026, 9, 14, 14, 5))
    }

    func testTurningOffUnlockForOneAppKeepsTheOthers() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        let result = f.core.submit(.setMode(appID: f.textEdit, mode: .unlock, enabled: false), locale: en)
        XCTAssertEqual(result, .applied)
        XCTAssertFalse(f.core.isAllowed(appID: f.textEdit))
        XCTAssertTrue(f.core.isAllowed(appID: f.discord))
        XCTAssertEqual(f.core.activeUnlock?.endsAt, date(2026, 9, 14, 14, 5))
    }

    func testFocusCanStartDuringAnUnlock() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        try f.buy(300)
        f.core.startFocus()
        XCTAssertNotNil(f.core.state.focus)
        XCTAssertTrue(f.core.isAllowed(appID: f.discord))
    }

    func testGatePauseGrowsWithTheStreak() {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 0)
        XCTAssertEqual(f.core.gatePauseSeconds(appID: f.discord, at: f.core.now), 5)
        for (last, expected) in [(1, 10), (2, 20), (4, 30), (8, 30)] {
            f.core.state.unlockStreak = UnlockStreak(
                lastMultiplier: last, lastEnd: f.core.now, dayKey: "2026-09-14")
            XCTAssertEqual(f.core.gatePauseSeconds(appID: f.discord, at: f.core.now), expected)
        }
        XCTAssertEqual(f.core.gatePauseSeconds(appID: f.notes, at: f.core.now), 5)
    }
}
