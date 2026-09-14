import XCTest

@testable import MyTimeCore

/// Booked sessions (spec §5.4). Release values: book ≥ 10 min ahead and ≤ 7 days ahead; 30 min–3 h in 15 min steps;
/// 5 h per week; one +15 min extension; start slots every 5 min.
final class BookingRulesTests: XCTestCase {
    private let monday10 = date(2026, 9, 14, 10)

    func testValidationRulesInOrder() throws {
        var (core, _) = makeEngine(at: monday10)
        let now = core.now
        func check(_ minutesAhead: Double, _ duration: Int) -> EngineError? {
            core.validateBooking(start: now.addingTimeInterval(minutesAhead * 60), durationSeconds: duration)
        }
        XCTAssertEqual(check(9, 1800), .bookingTooSoon(leadSeconds: 600))
        XCTAssertEqual(check(9, 900), .bookingTooSoon(leadSeconds: 600))
        XCTAssertNil(check(10, 1800))
        XCTAssertEqual(check(7 * 24 * 60 + 1, 1800), .bookingTooFar)
        XCTAssertNil(check(7 * 24 * 60, 1800))
        XCTAssertEqual(check(60, 900), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertEqual(check(60, 11700), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertEqual(check(60, 2000), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertNil(check(60, 10800))

        _ = try core.createBooking(start: now.addingTimeInterval(3600), durationSeconds: 3600)  // 11:00–12:00
        XCTAssertEqual(check(90, 1800), .bookingOverlap)
        XCTAssertEqual(check(30, 3600), .bookingOverlap)
        XCTAssertNil(check(120, 1800))
        XCTAssertNil(check(30, 1800))

        _ = try core.createBooking(start: now.addingTimeInterval(3 * 3600), durationSeconds: 10800)  // 13:00–16:00
        XCTAssertEqual(core.allowanceRemaining(weekOf: now), 3600)
        XCTAssertEqual(check(7 * 60, 4500), .allowanceExceeded)
        XCTAssertNil(check(7 * 60, 3600))
    }

    func testCanceledAndEndedSessionsDoNotBlockNewBookings() throws {
        var (core, sim) = makeEngine(at: monday10)
        let canceled = try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800)  // 11:00
        try core.cancelBooking(id: canceled.id)
        XCTAssertNil(core.validateBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800))
        let ended = try core.createBooking(start: core.now.addingTimeInterval(900), durationSeconds: 7200)  // 10:15–12:15
        sim.advance(1800)  // 10:30
        _ = core.update(sim.input)
        core.endBooking(id: ended.id)
        XCTAssertNil(core.validateBooking(start: core.now.addingTimeInterval(900), durationSeconds: 1800))  // 10:45
    }

    func testCreateBookingRecordsHistoryAndRejectsInvalidRequests() throws {
        var (core, _) = makeEngine(at: monday10)
        let booking = try core.createBooking(start: core.now.addingTimeInterval(1800), durationSeconds: 3600)
        XCTAssertEqual(core.state.bookings, [booking])
        XCTAssertEqual(booking.createdAt, core.now)
        XCTAssertEqual(booking.extensionSeconds, 0)
        XCTAssertFalse(booking.appOpened)
        XCTAssertEqual(core.state.history.last?.kind, .bookingCreated)
        XCTAssertEqual(core.state.history.last?.text, "Booked a session · 1h")
        XCTAssertThrowsError(try core.createBooking(start: core.now.addingTimeInterval(60), durationSeconds: 3600)) {
            XCTAssertEqual($0 as? EngineError, .bookingTooSoon(leadSeconds: 600))
        }
        XCTAssertEqual(core.state.bookings.count, 1)
    }

    func testChargedSecondsFollowWhatHappened() throws {
        var (core, sim) = makeEngine(at: monday10)
        let discord = core.state.settings.apps[0].id
        let canceled = try core.createBooking(start: core.now.addingTimeInterval(1800), durationSeconds: 1800)  // 10:30
        _ = try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800)  // 11:00, never opened
        let early = try core.createBooking(start: core.now.addingTimeInterval(5400), durationSeconds: 3600)  // 11:30
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 7200)
        try core.cancelBooking(id: canceled.id)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 5400)

        sim.advance(5400 + 1)  // 11:30:01: the 11:00 session finished unopened; the 11:30 one is live
        _ = core.update(sim.input)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 3600)
        sim.running = [discord]
        sim.advance(619)  // 11:40:20
        _ = core.update(sim.input)
        core.endBooking(id: early.id)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[0]), 0)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[1]), 0)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[2]), 660)  // 10 min 20 s, rounded up
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 660)
    }

    func testAllowanceIsCountedByTheWeekASessionStartsIn() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 18, 10))  // Friday
        _ = try core.createBooking(start: date(2026, 9, 20, 23), durationSeconds: 3600)  // Sunday night
        _ = try core.createBooking(start: date(2026, 9, 21, 3), durationSeconds: 1800)  // Monday 3 AM: same week
        _ = try core.createBooking(start: date(2026, 9, 21, 4), durationSeconds: 2700)  // Monday 4 AM: next week
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 5400)
        XCTAssertEqual(core.allowanceRemaining(weekOf: date(2026, 9, 21, 12)), 18000 - 2700)
        core.state.weekly["2026-W38"] = WeeklyStats(allowanceForfeited: true)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 0)
        XCTAssertEqual(core.allowanceRemaining(weekOf: date(2026, 9, 21, 12)), 18000 - 2700)
    }

    func testOnlyUpcomingSessionsCanBeCanceled() throws {
        var (core, sim) = makeEngine(at: monday10)
        let soon = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)
        let later = try core.createBooking(start: core.now.addingTimeInterval(7200), durationSeconds: 2700)
        try core.cancelBooking(id: later.id)
        XCTAssertEqual(core.state.bookings[1].canceledAt, core.now)
        XCTAssertEqual(core.state.history.last?.kind, .bookingCanceled)
        XCTAssertEqual(core.state.history.last?.text, "Canceled a session · 45 min")
        XCTAssertThrowsError(try core.cancelBooking(id: later.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertThrowsError(try core.cancelBooking(id: soon.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
        XCTAssertThrowsError(try core.cancelBooking(id: UUID())) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
    }

    func testExtensionRules() throws {
        var (core, sim) = makeEngine(at: monday10)
        let live = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10–10:40
        _ = try core.createBooking(start: core.now.addingTimeInterval(3300), durationSeconds: 1800)  // 10:55–11:25
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // not live yet
        sim.advance(900)  // 10:15
        _ = core.update(sim.input)
        XCTAssertEqual(core.activeBooking?.id, live.id)
        XCTAssertTrue(core.canExtendBooking(id: live.id))  // the new end, 10:55, touches the next session
        try core.extendBooking(id: live.id)
        XCTAssertEqual(core.activeBooking?.extensionSeconds, 900)
        XCTAssertEqual(core.activeBooking?.end, date(2026, 9, 14, 10, 55))
        XCTAssertEqual(core.state.history.last?.kind, .bookingExtended)
        XCTAssertEqual(core.state.history.last?.text, "Extended session · +15 min")
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 2700 - 1800)
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // only once
        XCTAssertThrowsError(try core.extendBooking(id: live.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotExtendBooking)
        }
    }

    func testExtensionIsRefusedWhenItWouldOverlapOrExceedTheAllowance() throws {
        var (core, sim) = makeEngine(at: monday10)
        let live = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10–10:40
        _ = try core.createBooking(start: core.now.addingTimeInterval(3000), durationSeconds: 1800)  // 10:50–11:20
        sim.advance(900)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // 10:55 would overlap 10:50

        core.state.bookings.removeLast()
        core.state.settings[.weeklyAllowanceSeconds] = 2700  // 1800 used, exactly 900 left
        XCTAssertTrue(core.canExtendBooking(id: live.id))
        core.state.settings[.weeklyAllowanceSeconds] = 2600
        XCTAssertFalse(core.canExtendBooking(id: live.id))
        core.state.settings[.weeklyAllowanceSeconds] = 18000
        core.state.settings[.bookingExtensionSeconds] = 0
        XCTAssertFalse(core.canExtendBooking(id: live.id))
        XCTAssertFalse(core.canExtendBooking(id: UUID()))
    }

    func testUpcomingBookingsAreSortedAndExcludeCanceledAndLiveSessions() throws {
        var (core, sim) = makeEngine(at: monday10)
        let c = try core.createBooking(start: core.now.addingTimeInterval(14400), durationSeconds: 1800)  // 14:00
        let b = try core.createBooking(start: core.now.addingTimeInterval(7200), durationSeconds: 1800)  // 12:00
        let a = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10
        let d = try core.createBooking(start: core.now.addingTimeInterval(10800), durationSeconds: 1800)  // 13:00
        try core.cancelBooking(id: d.id)
        XCTAssertEqual(core.upcomingBookings.map(\.id), [a.id, b.id, c.id])
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.upcomingBookings.map(\.id), [b.id, c.id])
    }

    func testBookingIsAllowedDuringFocus() {
        var (core, _) = makeEngine(at: monday10)
        core.startFocus()
        XCTAssertNoThrow(try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800))
    }

    func testPickerChoices() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10, 2, 30))
        XCTAssertEqual(core.bookingDurations, [1800, 2700, 3600, 4500, 5400, 6300, 7200, 8100, 9000, 9900, 10800])
        let today = core.bookingStartSlots(onDayOf: core.now)
        XCTAssertEqual(today.first, date(2026, 9, 14, 10, 15))
        XCTAssertEqual(today.last, date(2026, 9, 14, 23, 55))
        XCTAssertEqual(today.count, 165)
        let tomorrow = core.bookingStartSlots(onDayOf: date(2026, 9, 15, 12))
        XCTAssertEqual(tomorrow.first, date(2026, 9, 15, 0, 0))
        XCTAssertEqual(tomorrow.count, 288)
        XCTAssertEqual(core.bookingDays(), (14...20).map { date(2026, 9, $0, 0) })
        sim.advance(13 * 3600 + 53 * 60 + 30)  // 23:56: nothing bookable is left today
        _ = core.update(sim.input)
        XCTAssertTrue(core.bookingStartSlots(onDayOf: core.now).isEmpty)
        XCTAssertEqual(core.bookingDays(), (15...20).map { date(2026, 9, $0, 0) })
    }
}
