import XCTest
@testable import MyTimeCore

final class GrantTests: XCTestCase {
    private var discord: UUID!

    private func engine(tokens: Int) -> (EngineCore, Sim) {
        let pair = makeEngine(at: date(2026, 9, 14, 10), tokens: tokens)
        discord = pair.0.state.settings.apps[0].id
        return pair
    }

    /// No launch grace: the countdown starts the moment access is bought. The app relaunches within about a second,
    /// and a frozen countdown read as broken (user feedback after Run 2).
    func testCountdownStartsAtPurchase() throws {
        var (core, sim) = engine(tokens: 5)
        let g = AccessGrant(
            appID: discord, kind: .emergency, createdAt: core.now,
            expiresAt: core.now.addingTimeInterval(30))
        core.state.grants.append(g)
        XCTAssertEqual(core.remaining(of: g), 30, accuracy: 0.001)
        sim.advance(10)
        _ = core.update(sim.input)
        XCTAssertEqual(core.remaining(of: g), 20, accuracy: 0.001)
    }

    func testExpiryRemovesGrantAndAsksToTerminate() throws {
        var (core, sim) = engine(tokens: 1)
        core.state.grants.append(
            AccessGrant(
                appID: discord, kind: .emergency, createdAt: core.now,
                expiresAt: core.now.addingTimeInterval(30)))
        sim.advance(29)
        var r = core.update(sim.input)
        XCTAssertEqual(r.effects, [])
        XCTAssertEqual(r.nextWakeUp, WakeUp(date: core.now.addingTimeInterval(1), critical: true))
        sim.advance(1)
        r = core.update(sim.input)
        XCTAssertEqual(r.effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertTrue(core.state.grants.isEmpty)
        XCTAssertFalse(core.isAllowed(appID: discord))
    }

    func testManualClockJumpDoesNotShortenAccess() throws {
        var (core, sim) = engine(tokens: 1)
        core.state.grants.append(
            AccessGrant(
                appID: discord, kind: .emergency, createdAt: core.now,
                expiresAt: core.now.addingTimeInterval(30)))
        sim.wall = sim.wall.addingTimeInterval(3 * 3600)
        sim.continuous += 1
        sim.uptime += 1
        let r = core.update(sim.input)
        XCTAssertEqual(r.effects, [])
        let grant = try XCTUnwrap(core.activeGrant(appID: discord))
        XCTAssertEqual(core.remaining(of: grant), 29, accuracy: 0.01)
    }

    func testActiveBookingAllowsOnlyBookedModeApps() {
        var (core, sim) = engine(tokens: 0)
        core.state.bookings = [
            Booking(
                start: core.now.addingTimeInterval(-60), durationSeconds: 1800,
                createdAt: core.now.addingTimeInterval(-3600))
        ]
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertNotNil(core.activeBooking)
        XCTAssertTrue(core.isAllowed(appID: discord))
        core.state.settings.apps[0].modes = [.unlock]
        XCTAssertFalse(core.isAllowed(appID: discord))
    }

    func testBackedOffIsCounted() {
        var (core, _) = engine(tokens: 0)
        core.recordBackedOff(appID: discord)
        XCTAssertEqual(core.today.backedOff, 1)
        XCTAssertEqual(core.state.history.last?.kind, .backedOff)
        XCTAssertEqual(core.state.history.last?.text, "Backed off from Discord")
    }

    func testLookups() {
        let (core, _) = engine(tokens: 0)
        XCTAssertEqual(core.app(bundleID: "com.hnc.DiscordPTB")?.id, discord)
        XCTAssertNil(core.app(bundleID: "com.hnc.Discord.helper"))
        XCTAssertEqual(core.setting(.gatePauseSeconds), 5)
        XCTAssertEqual(core.nextDayStart, date(2026, 9, 15, 4))
    }
}
