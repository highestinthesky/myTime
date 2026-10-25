import XCTest

@testable import MyTimeCore

final class UnlockPersistenceTests: XCTestCase {
    func testStatsDecodeMissingFieldsIndependently() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(DailyStats.self, from: Data("{}".utf8)), DailyStats())
        XCTAssertEqual(try decoder.decode(WeeklyStats.self, from: Data("{}".utf8)), WeeklyStats())
        XCTAssertEqual(
            try decoder.decode(DailyStats.self, from: Data("{\"tokensSpent\":7,\"replies\":2}".utf8)),
            DailyStats(tokensSpent: 7, replies: 2))
        XCTAssertEqual(
            try decoder.decode(WeeklyStats.self, from: Data("{\"emergencyUses\":1}".utf8)),
            WeeklyStats(emergencyUses: 1))
    }

    func testUnlockAndStreakRoundTripThroughStateCodec() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 20)
        try f.buy(60)
        f.advance(to: date(2026, 9, 14, 14, 1))
        try f.buy(120)
        let data = try StateCodec.encode(f.core.state)
        XCTAssertEqual(StateCodec.decode(data), .ok(f.core.state))
    }

    func testUsedSecondsStayWithThePurchaseDayAndWeek() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 3, 55), tokens: 20)
        let purchaseDay = f.core.state.tokensDayKey
        let purchaseWeek = CalendarKeys.weekKey(f.core.now, dayStartHour: 4, timeZone: testTZ)
        try f.buy(600)
        f.advance(to: date(2026, 9, 14, 4, 5))
        XCTAssertEqual(f.core.state.daily[purchaseDay]?.unlockSeconds, 600)
        XCTAssertEqual(f.core.state.weekly[purchaseWeek]?.unlockSeconds, 600)
        XCTAssertEqual(f.core.today.unlockSeconds, 0)
        XCTAssertEqual(f.core.today.unlocks, 0)
        let currentWeek = CalendarKeys.weekKey(f.core.now, dayStartHour: 4, timeZone: testTZ)
        XCTAssertNotEqual(purchaseWeek, currentWeek)
        XCTAssertNil(f.core.state.weekly[currentWeek])
    }

    func testGrantAndUnlockExpiryDeduplicateTermination() throws {
        var f = makeUnlockFixture(at: date(2026, 9, 14, 14), tokens: 10)
        let unlock = try f.buy(60)
        f.core.state.grants.append(
            AccessGrant(
                appID: f.discord, kind: .emergency, createdAt: f.core.now,
                expiresAt: unlock.endsAt, tokensSpent: 0))
        let effects = f.advance(to: unlock.endsAt).effects
        XCTAssertEqual(effects.filter { $0 == .terminateIfNotAllowed(appID: f.discord) }.count, 1)
        XCTAssertEqual(effects.last, .unlockEnded)
    }
}
