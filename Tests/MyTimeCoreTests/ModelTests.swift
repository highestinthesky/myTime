import XCTest
@testable import MyTimeCore

final class ModelTests: XCTestCase {
    func testFreshStateBlocksDiscordWithAllModes() {
        let s = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        XCTAssertEqual(s.schemaVersion, 1)
        XCTAssertEqual(s.tokens, 0)
        XCTAssertEqual(s.tokensDayKey, "2026-09-14")
        XCTAssertEqual(s.settings.apps.count, 1)
        XCTAssertEqual(s.settings.apps[0].name, "Discord")
        XCTAssertEqual(
            s.settings.apps[0].bundleIDs, ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"])
        XCTAssertEqual(s.settings.apps[0].modes, [.quickLook, .reply, .booked])
    }

    func testSettingsSubscriptFallsBackToDefaultAndClamps() {
        var settings = Settings()
        XCTAssertEqual(settings[.focusSecondsPerToken], 900)
        settings[.focusSecondsPerToken] = 600
        XCTAssertEqual(settings.numbers["focusSecondsPerToken"], 600)
        settings[.quickLookMaxTokens] = 50
        XCTAssertEqual(settings[.quickLookMaxTokens], 10)
    }

    func testPersistedStateRoundTripsAndUsesStringKeyedObjects() throws {
        var s = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        let discord = s.settings.apps[0].id
        s.tokens = 4
        s.daily["2026-09-14"] = DailyStats(backedOff: 1)
        s.grants = [
            AccessGrant(
                appID: discord, kind: .reply, createdAt: date(2026, 9, 14, 10),
                startsAt: date(2026, 9, 14, 10), expiresAt: date(2026, 9, 14, 10, 3),
                tokensSpent: 2, note: "reply to Sam")
        ]
        s.pending = [
            PendingChange(
                createdAt: date(2026, 9, 14, 10), applyAt: date(2026, 9, 15, 10),
                change: .setMode(appID: discord, mode: .reply, enabled: true),
                summary: "Turn on Reply mode for Discord")
        ]
        let data = try JSONEncoder.myTime.encode(s)
        XCTAssertEqual(try JSONDecoder.myTime.decode(PersistedState.self, from: data), s)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"daily\":{\"2026-09-14\":{"), json)
    }

    func testBookingStates() {
        var b = Booking(start: date(2026, 9, 14, 20), durationSeconds: 3600, createdAt: date(2026, 9, 14, 10))
        XCTAssertEqual(b.end, date(2026, 9, 14, 21))
        XCTAssertTrue(b.isUpcoming(at: date(2026, 9, 14, 19)))
        XCTAssertTrue(b.isActive(at: date(2026, 9, 14, 20, 30)))
        XCTAssertTrue(b.isFinished(at: date(2026, 9, 14, 21)))
        b.endedAt = date(2026, 9, 14, 20, 30)
        XCTAssertFalse(b.isActive(at: date(2026, 9, 14, 20, 45)))
        XCTAssertTrue(b.isFinished(at: date(2026, 9, 14, 20, 45)))
        b.canceledAt = date(2026, 9, 14, 12)
        XCTAssertFalse(b.isFinished(at: date(2026, 9, 14, 22)))
        XCTAssertFalse(b.isUpcoming(at: date(2026, 9, 14, 19)))
    }

    func testFieldKeys() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let app = BlockedApp(id: id, name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"], modes: [])
        XCTAssertEqual(SettingChange.setNumber(key: .replyPerDay, value: 1).fieldKey, "number:replyPerDay")
        XCTAssertEqual(SettingChange.addApp(app).fieldKey, "app:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(SettingChange.removeApp(id: id).fieldKey, "app:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(
            SettingChange.setMode(appID: id, mode: .reply, enabled: true).fieldKey,
            "mode:00000000-0000-0000-0000-000000000001:reply")
        XCTAssertEqual(SettingChange.uninstall.fieldKey, "uninstall")
    }

    func testEngineErrorMessages() {
        XCTAssertEqual(EngineError.invalidAmount(max: 3).userMessage, "Choose between 1 and 3 tokens.")
        XCTAssertEqual(EngineError.notEnoughTokens.userMessage, "Not enough tokens.")
        XCTAssertEqual(EngineError.bookingTooSoon(leadSeconds: 600).userMessage, "Book at least 10 min ahead.")
        XCTAssertEqual(
            EngineError.invalidDuration(minSeconds: 1800, maxSeconds: 10800).userMessage,
            "Choose a length between 30 min and 3h.")
        XCTAssertEqual(EngineError.unknownApp.userMessage, "That app isn't blocked anymore.")
        XCTAssertEqual(EngineError.unknownGrant.userMessage, "That access has already ended.")
    }
}
