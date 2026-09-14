import XCTest

@testable import MyTimeCore

final class ClaimTests: XCTestCase {
    func testClaimIsCappedByTheDailyBudget() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 2400 }
        XCTAssertEqual(core.claimableSeconds, 1800, accuracy: 0.001)
        core.confirmClaim()
        XCTAssertEqual(core.today.claimedAwaySeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertEqual(core.state.history.last?.kind, .awayClaimed)
        XCTAssertEqual(core.state.history.last?.text, "Counted 30 min away as focus")

        core.updateToday { $0.unclaimedAwaySeconds = 600 }
        XCTAssertEqual(core.claimableSeconds, 0)
        core.confirmClaim()
        XCTAssertEqual(core.today.focusSeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
    }

    func testDismissClearsWithoutCrediting() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 900 }
        core.dismissClaim()
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertEqual(core.claimableSeconds, 0)
    }

    func testClaimWorksWithoutAFocusSession() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 300 }
        core.confirmClaim()
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.progressSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(core.state.history.last?.text, "Counted 5 min away as focus")
    }

    func testANewDayStartsWithNothingToClaim() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 0))
        core.updateToday { $0.unclaimedAwaySeconds = 900 }
        sim.advance(3600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.claimableSeconds, 0)
    }
}
