import XCTest

@testable import MyTimeCore

final class UnlockPricingTests: XCTestCase {
    private let day = "2026-09-14"
    private let dayStart = date(2026, 9, 15, 4)

    func testFirstUnlockOfTheDayIsOneTimes() {
        let quote = UnlockPricing.quote(after: nil, at: date(2026, 9, 14, 14), dayKey: day, nextDayStart: dayStart)
        XCTAssertEqual(quote.multiplier, 1)
        XCTAssertEqual(quote.options.map(\.lengthSeconds), [60, 120, 300, 600])
        XCTAssertEqual(quote.options.map(\.cost), [1, 2, 5, 10])
        XCTAssertNil(quote.resetsAt)
    }

    func testGapJustUnderFifteenMinutesDoubles() {
        let previous = UnlockStreak(lastMultiplier: 1, lastEnd: date(2026, 9, 14, 14, 5), dayKey: day)
        let at = date(2026, 9, 14, 14, 19, 59)
        XCTAssertEqual(UnlockPricing.multiplier(after: previous, at: at, dayKey: day), 2)
    }

    func testGapOfExactlyFifteenMinutesResets() {
        let previous = UnlockStreak(lastMultiplier: 4, lastEnd: date(2026, 9, 14, 14, 5), dayKey: day)
        let at = date(2026, 9, 14, 14, 20)
        XCTAssertEqual(UnlockPricing.multiplier(after: previous, at: at, dayKey: day), 1)
    }

    func testMultiplierDoublesWithoutACap() {
        let previous = UnlockStreak(lastMultiplier: 32, lastEnd: date(2026, 9, 14, 14, 5), dayKey: day)
        let at = date(2026, 9, 14, 14, 6)
        let quote = UnlockPricing.quote(after: previous, at: at, dayKey: day, nextDayStart: dayStart)
        XCTAssertEqual(quote.multiplier, 64)
        XCTAssertEqual(quote.options.map(\.cost), [64, 128, 320, 640])
    }

    func testADifferentDayStartsFresh() {
        let previous = UnlockStreak(lastMultiplier: 2, lastEnd: date(2026, 9, 14, 4, 5), dayKey: "2026-09-13")
        let at = date(2026, 9, 14, 4, 10)
        XCTAssertEqual(UnlockPricing.multiplier(after: previous, at: at, dayKey: day), 1)
    }

    func testResetTimeIsTheEndPlusTheGap() {
        let previous = UnlockStreak(lastMultiplier: 2, lastEnd: date(2026, 9, 14, 14, 13), dayKey: day)
        let at = date(2026, 9, 14, 14, 14)
        let quote = UnlockPricing.quote(after: previous, at: at, dayKey: day, nextDayStart: dayStart)
        XCTAssertEqual(quote.multiplier, 4)
        XCTAssertEqual(quote.resetsAt, date(2026, 9, 14, 14, 28))
    }

    func testResetTimeStopsAtTheDayStart() {
        let previous = UnlockStreak(lastMultiplier: 1, lastEnd: date(2026, 9, 15, 3, 50), dayKey: day)
        let at = date(2026, 9, 15, 3, 51)
        let quote = UnlockPricing.quote(after: previous, at: at, dayKey: day, nextDayStart: dayStart)
        XCTAssertEqual(quote.multiplier, 2)
        XCTAssertEqual(quote.resetsAt, dayStart)
    }
}
