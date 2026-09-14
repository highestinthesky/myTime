import XCTest

@testable import MyTimeCore

final class SamplingIndependenceTests: XCTestCase {
    /// 25-minute script, in seconds from focus start:
    /// 0–600 typing · 600–1005 away (no input) · 1005–1500 typing · Discord open 1200–1320.
    /// Samples run at a fixed cadence plus at Discord's launch/quit, which the real app receives as events.
    private func run(every cadence: Double) -> (focus: Double, unclaimed: Double) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.startFocus()
        func lastInput(at t: Double) -> Double { t <= 600 ? t : (t < 1005 ? 600 : t) }
        var times = Set(stride(from: cadence, through: 1500, by: cadence))
        times.formUnion([1200, 1320, 1500])
        var previous = 0.0
        for t in times.sorted() {
            sim.advance(t - previous)
            previous = t
            sim.idle = t - lastInput(at: t)
            sim.running = (1200..<1320).contains(t) ? [discord] : []
            _ = core.update(sim.input)
        }
        core.endFocus()
        return (core.today.focusSeconds, core.today.unclaimedAwaySeconds)
    }

    func testFocusPlusAwayTimeDoesNotDependOnHowOftenTheEngineChecks() {
        let fine = run(every: 1)
        let sparse = run(every: 30)
        XCTAssertEqual(fine.focus, 975, accuracy: 2)
        XCTAssertEqual(fine.unclaimed, 405, accuracy: 2)
        XCTAssertEqual(fine.focus + fine.unclaimed, sparse.focus + sparse.unclaimed, accuracy: 2)
        // Coming back is noticed at the next check, so at most one interval moves from focus to away time.
        XCTAssertEqual(fine.focus, sparse.focus, accuracy: 30 + 2)
    }
}
