import XCTest

@testable import MyTimeCore

/// Old data is pruned only in the update where the daily reset runs (spec §8.2, update step 7).
/// The reset in this test is Tuesday 2026-09-15 at 4:00 AM, so the 14-day booking cutoff is Sep 1 at 4:00 AM.
final class PruningTests: XCTestCase {
    private func booking(start: Date, hours: Double = 0.5, canceledAt: Date? = nil) -> Booking {
        Booking(
            start: start, durationSeconds: Int(hours * 3600), createdAt: start.addingTimeInterval(-86400),
            canceledAt: canceledAt)
    }

    func testPruningRunsWithTheDailyResetAndKeepsRecentData() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.state.daily = ["2026-07-16": DailyStats(), "2026-07-17": DailyStats(), "2026-09-14": DailyStats()]
        core.state.weekly = ["2026-W27": WeeklyStats(), "2026-W28": WeeklyStats(), "2026-W38": WeeklyStats()]
        let canceledLongAgo = booking(start: date(2026, 9, 3, 12), canceledAt: date(2026, 8, 31, 12))
        let canceledRecently = booking(start: date(2026, 9, 3, 12), canceledAt: date(2026, 9, 2, 12))
        let endedLongAgo = booking(start: date(2026, 8, 31, 22))  // ends Aug 31, 10:30 PM
        let endedAfterCutoff = booking(start: date(2026, 8, 31, 22), hours: 8)  // ends Sep 1, 6:00 AM
        let endedRecently = booking(start: date(2026, 9, 2, 22))
        let upcoming = booking(start: date(2026, 9, 16, 20))
        core.state.bookings = [
            canceledLongAgo, canceledRecently, endedLongAgo, endedAfterCutoff, endedRecently, upcoming,
        ]
        core.state.history = (0..<510).map { HistoryEvent(date: core.now, kind: .backedOff, text: "\($0)") }
        let before = core.state

        sim.advance(17 * 3600 + 59 * 60 + 59)  // Tuesday 3:59:59, no reset yet
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.daily, before.daily)
        XCTAssertEqual(core.state.weekly, before.weekly)
        XCTAssertEqual(core.state.bookings, before.bookings)
        XCTAssertEqual(core.state.history.count, 510)

        sim.advance(1)  // Tuesday 4:00, the reset
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.daily.keys.sorted(), ["2026-07-17", "2026-09-14"])
        XCTAssertEqual(core.state.weekly.keys.sorted(), ["2026-W28", "2026-W38"])
        XCTAssertEqual(
            core.state.bookings.map(\.id), [canceledRecently.id, endedAfterCutoff.id, endedRecently.id, upcoming.id])
        XCTAssertEqual(core.state.history.count, 500)
        XCTAssertEqual(core.state.history.first?.text, "10")
    }
}
