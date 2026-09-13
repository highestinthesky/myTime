import XCTest
@testable import MyTimeCore

final class GrantTests: XCTestCase {
    private var discord: UUID!

    private func engine(tokens: Int) -> (EngineCore, Sim) {
        let pair = makeEngine(at: date(2026, 9, 14, 10), tokens: tokens)
        discord = pair.0.state.settings.apps[0].id
        return pair
    }

    func testQuickLookSpendsTokensAndCreatesGrant() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 2, appLaunchDate: nil)
        XCTAssertEqual(core.state.tokens, 3)
        XCTAssertEqual(g.kind, .quickLook)
        XCTAssertEqual(g.tokensSpent, 2)
        XCTAssertEqual(g.startsAt, core.now)
        XCTAssertEqual(g.expiresAt, core.now.addingTimeInterval(60))
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.today.quickLooks, 1)
        XCTAssertEqual(core.state.history.last?.text, "Quick look in Discord · 1:00 · 2 ◆")
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.activeGrant(appID: discord)?.id, g.id)
    }

    func testLaunchGraceDelaysStart() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: core.now.addingTimeInterval(-5))
        XCTAssertEqual(g.startsAt, core.now.addingTimeInterval(10))
        XCTAssertEqual(g.expiresAt, core.now.addingTimeInterval(40))
        XCTAssertEqual(core.remaining(of: g), 30, accuracy: 0.001)
    }

    func testAppLaunchedLongAgoStartsNow() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: core.now.addingTimeInterval(-60))
        XCTAssertEqual(g.startsAt, core.now)
    }

    func testQuickLookErrorsInOrder() {
        var (core, _) = engine(tokens: 1)
        func expect(_ error: EngineError, tokens: Int, app: UUID? = nil) {
            XCTAssertThrowsError(try core.buyQuickLook(appID: app ?? discord, tokens: tokens, appLaunchDate: nil)) {
                XCTAssertEqual($0 as? EngineError, error)
            }
        }
        expect(.unknownApp, tokens: 1, app: UUID())
        expect(.invalidAmount(max: 3), tokens: 0)
        expect(.invalidAmount(max: 3), tokens: 4)
        expect(.notEnoughTokens, tokens: 2)
        core.state.settings.apps[0].modes = [.reply]
        expect(.modeNotAllowed, tokens: 1)
        core.state.settings.apps[0].modes = [.quickLook]
        core.state.focus = FocusSession(startedAt: core.now)
        expect(.focusActive, tokens: 1)
        XCTAssertEqual(core.state.tokens, 1)
    }

    func testExtendOnlyInLastTenSeconds() throws {
        var (core, sim) = engine(tokens: 3)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        XCTAssertFalse(core.canExtend(grantID: g.id))
        XCTAssertThrowsError(try core.extendGrant(grantID: g.id)) { XCTAssertEqual($0 as? EngineError, .cannotExtend) }
        sim.advance(21)
        _ = core.update(sim.input)
        XCTAssertTrue(core.canExtend(grantID: g.id))
        try core.extendGrant(grantID: g.id)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.activeGrant(appID: discord)?.expiresAt, g.expiresAt.addingTimeInterval(30))
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.state.history.last?.text, "Extended Discord · +30 s")
        XCTAssertThrowsError(try core.extendGrant(grantID: UUID())) {
            XCTAssertEqual($0 as? EngineError, .unknownGrant)
        }
    }

    func testCannotExtendWithoutTokensOrForEmergency() throws {
        var (core, sim) = engine(tokens: 1)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        sim.advance(25)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: g.id))
        core.state.tokens = 5
        XCTAssertTrue(core.canExtend(grantID: g.id))
        core.state.grants[0].kind = .emergency
        XCTAssertFalse(core.canExtend(grantID: g.id))
    }

    func testExpiryRemovesGrantAndAsksToTerminate() throws {
        var (core, sim) = engine(tokens: 1)
        _ = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
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
        _ = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
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
        core.state.settings.apps[0].modes = [.quickLook]
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
        XCTAssertEqual(core.setting(.quickLookSecondsPerToken), 30)
        XCTAssertEqual(core.nextDayStart, date(2026, 9, 15, 4))
    }
}
