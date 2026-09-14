import XCTest

@testable import MyTimeCore

/// Booking transitions in `update` step 6 (spec §5.4). Heads-up is 5 minutes before the end in release builds.
final class BookingTransitionTests: XCTestCase {
    /// A 30-minute session from 10:15 to 10:45, booked at 10:00 on Monday. Discord has Sessions on; "Notes" doesn't.
    private func scenario() throws -> (core: EngineCore, sim: Sim, booking: Booking, discord: UUID, notes: UUID) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let notes = BlockedApp(name: "Notes", bundleIDs: ["com.example.notes"], modes: [.quickLook])
        core.state.settings.apps.append(notes)
        let booking = try core.createBooking(start: date(2026, 9, 14, 10, 15), durationSeconds: 1800)
        return (core, sim, booking, core.state.settings.apps[0].id, notes.id)
    }

    func testOpeningABookedAppDuringTheSessionIsRecorded() throws {
        var (core, sim, booking, discord, notes) = try scenario()
        sim.running = [discord]
        sim.advance(600)  // 10:10, before the start
        _ = core.update(sim.input)
        XCTAssertFalse(core.state.bookings[0].appOpened)
        XCTAssertFalse(core.isAllowed(appID: discord))
        sim.advance(360)  // 10:16
        _ = core.update(sim.input)
        XCTAssertEqual(core.activeBooking?.id, booking.id)
        XCTAssertTrue(core.state.bookings[0].appOpened)
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertFalse(core.isAllowed(appID: notes))
    }

    func testHeadsUpIsEmittedOnceFiveMinutesBeforeTheEnd() throws {
        var (core, sim, booking, _, _) = try scenario()
        sim.advance(20 * 60)  // 10:20
        XCTAssertEqual(core.update(sim.input).effects, [])
        sim.advance(19 * 60 + 59)  // 10:39:59
        XCTAssertEqual(core.update(sim.input).effects, [])
        sim.advance(1)  // 10:40:00
        XCTAssertEqual(core.update(sim.input).effects, [.bookingHeadsUp(bookingID: booking.id)])
        XCTAssertTrue(core.state.bookings[0].warned)
        sim.advance(30)
        XCTAssertEqual(core.update(sim.input).effects, [])
    }

    func testSessionEndClosesOnlyAppsWithSessionsOn() throws {
        var (core, sim, _, discord, _) = try scenario()
        sim.advance(20 * 60)  // 10:20
        _ = core.update(sim.input)
        sim.advance(25 * 60)  // 10:45, the end
        let result = core.update(sim.input)
        XCTAssertNil(core.activeBooking)
        XCTAssertEqual(result.effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertEqual(core.state.history.last?.kind, .bookingEnded)
        XCTAssertEqual(core.state.history.last?.text, "Session ended")
        XCTAssertFalse(core.isAllowed(appID: discord))
        sim.advance(60)
        XCTAssertEqual(core.update(sim.input).effects, [])
        XCTAssertEqual(core.state.history.filter { $0.kind == .bookingEnded }.count, 1)
    }

    func testEndingEarlyClosesAppsOnTheNextUpdateAndChargesOnlyTheMinutesUsed() throws {
        var (core, sim, booking, discord, _) = try scenario()
        sim.running = [discord]
        sim.advance(16 * 60)  // 10:16
        _ = core.update(sim.input)
        sim.advance(4 * 60 + 30)  // 10:20:30
        _ = core.update(sim.input)
        core.endBooking(id: booking.id)
        XCTAssertEqual(core.state.bookings[0].endedAt, core.now)
        XCTAssertNil(core.activeBooking)
        sim.advance(1)
        XCTAssertEqual(core.update(sim.input).effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[0]), 360)  // 5 min 30 s, rounded up
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 360)
    }

    func testEndBookingIgnoresSessionsThatAreNotLive() throws {
        var (core, _, booking, _, _) = try scenario()
        core.endBooking(id: booking.id)
        core.endBooking(id: UUID())
        XCTAssertNil(core.state.bookings[0].endedAt)
    }

    func testGrantExpiryAndSessionEndInTheSameUpdateCloseTheAppOnce() throws {
        var (core, sim, _, discord, _) = try scenario()
        sim.advance(1600)  // 10:26:40
        _ = core.update(sim.input)
        core.state.grants = [
            AccessGrant(appID: discord, kind: .quickLook, createdAt: core.now, expiresAt: date(2026, 9, 14, 10, 45))
        ]
        sim.advance(18 * 60 + 20)  // 10:45
        XCTAssertEqual(core.update(sim.input).effects, [.terminateIfNotAllowed(appID: discord)])
    }
}
