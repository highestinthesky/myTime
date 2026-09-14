import XCTest
@testable import MyTimeCore

final class WakeUpPlannerTests: XCTestCase {
    let now = date(2026, 9, 14, 10)
    let dayStart = date(2026, 9, 15, 4)
    var fresh: PersistedState { PersistedState.fresh(now: now, timeZone: testTZ) }

    private func plan(_ s: PersistedState, _ rt: EngineRuntime = EngineRuntime()) -> WakeUp? {
        WakeUpPlanner.next(state: s, runtime: rt, now: now, nextDayStart: dayStart)
    }

    func testIdleReturnsNextDayStart() {
        XCTAssertEqual(plan(fresh), WakeUp(date: dayStart, critical: false))
    }

    func testGrantExpiryIsCriticalAndEarliest() {
        var s = fresh
        s.grants = [
            AccessGrant(
                appID: s.settings.apps[0].id, kind: .quickLook, createdAt: now,
                expiresAt: now.addingTimeInterval(30))
        ]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(30), critical: true))
    }

    func testFocusAddsCheckInterval() {
        var s = fresh
        s.focus = FocusSession(startedAt: now)
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(Constants.focusCheckInterval), critical: false))
    }

    func testAwayWithoutFocusStillChecks() {
        var rt = EngineRuntime()
        rt.awayStartUptime = 5
        XCTAssertEqual(plan(fresh, rt)?.date, now.addingTimeInterval(Constants.focusCheckInterval))
    }

    func testActiveBookingHeadsUpThenEnd() {
        var s = fresh
        s.bookings = [
            Booking(
                start: now.addingTimeInterval(-1800), durationSeconds: 3600,
                createdAt: now.addingTimeInterval(-7200))
        ]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(1800 - Constants.bookingHeadsUp), critical: false))
        s.bookings[0].warned = true
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(1800), critical: true))
    }

    func testUpcomingBookingStartIsNotACandidate() {
        var s = fresh
        s.bookings = [Booking(start: now.addingTimeInterval(600), durationSeconds: 1800, createdAt: now)]
        XCTAssertEqual(plan(s), WakeUp(date: dayStart, critical: false))
    }

    func testPendingChangeAndPastCandidatesIgnored() {
        var s = fresh
        s.pending = [
            PendingChange(
                createdAt: now, applyAt: now.addingTimeInterval(-10), change: .uninstall, summary: "Uninstall myTime"),
            PendingChange(
                createdAt: now, applyAt: now.addingTimeInterval(600), change: .uninstall, summary: "Uninstall myTime"),
        ]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(600), critical: false))
    }

    func testTieBreakPrefersCritical() {
        var s = fresh
        s.pending = [
            PendingChange(
                createdAt: now, applyAt: now.addingTimeInterval(30), change: .uninstall, summary: "Uninstall myTime")
        ]
        s.grants = [
            AccessGrant(
                appID: s.settings.apps[0].id, kind: .quickLook, createdAt: now,
                expiresAt: now.addingTimeInterval(30))
        ]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(30), critical: true))
    }
}
