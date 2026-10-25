import XCTest

@testable import MyTimeCore

final class MigrationTests: XCTestCase {
    private let appID = "8E1A1C2B-0000-4000-8000-000000000001"
    private let created = 1_793_000_000.0

    /// A schema-1 payload as 0.1.0 wrote it.
    private func v1File(
        modes: [String], pending: [[String: Any]] = [], numbers: [String: Int] = [:],
        grants: [[String: Any]] = []
    ) throws -> Data {
        let app: [String: Any] = ["id": appID, "name": "Discord", "bundleIDs": ["com.hnc.Discord"], "modes": modes]
        let day: [String: Any] = [
            "focusSeconds": 900.0, "tokensEarned": 1, "tokensSpent": 2, "backedOff": 0, "quickLooks": 1,
            "replies": 2, "claimedAwaySeconds": 0.0, "unclaimedAwaySeconds": 0.0,
        ]
        let state: [String: Any] = [
            "schemaVersion": 1,
            "settings": ["numbers": numbers, "apps": [app]],
            "pending": pending,
            "tokens": 7,
            "progressSeconds": 120.0,
            "tokensDayKey": "2026-10-24",
            "grants": grants,
            "bookings": [],
            "daily": ["2026-10-24": day],
            "weekly": ["2026-W43": ["emergencyUses": 0, "allowanceForfeited": false]],
            "history": [],
            "clock": ["offsetSeconds": 0.0, "lastWall": created, "lastContinuous": 1000.0, "bootSessionID": "BOOT-A"],
        ]
        return try StateCodec.seal(JSONSerialization.data(withJSONObject: state))
    }

    private func pendingMode(_ mode: String) -> [String: Any] {
        [
            "id": UUID().uuidString, "createdAt": created, "applyAt": created + 6 * 3600,
            "change": ["setMode": ["appID": appID, "mode": mode, "enabled": true]],
            "summary": "Turn on something for Discord",
        ]
    }

    private func migrated(_ data: Data) throws -> PersistedState {
        guard case let .migrated(state) = StateCodec.decode(data) else {
            XCTFail("expected .migrated")
            throw CocoaError(.coderReadCorrupt)
        }
        return state
    }

    func testQuickLookAndReplyBecomeUnlock() throws {
        let state = try migrated(v1File(modes: ["quickLook", "reply", "booked"]))
        XCTAssertEqual(state.schemaVersion, 2)
        XCTAssertEqual(state.settings.apps[0].modes, [.unlock, .booked])
        XCTAssertEqual(state.tokens, 7)
        XCTAssertEqual(state.daily["2026-10-24"]?.focusSeconds, 900)
        XCTAssertNil(state.unlock)
        XCTAssertNil(state.unlockStreak)
        XCTAssertEqual(
            state.migrationNotice,
            "Quick look and Reply mode are now Unlock. Choose 1, 2, 5, or 10 minutes at the gate, 1 token a minute. "
                + "An Unlock bought less than 15 minutes after the last one costs twice as much.")
    }

    func testReplyAloneLeavesUnlockOff() throws {
        let state = try migrated(v1File(modes: ["reply", "booked"]))
        XCTAssertEqual(state.settings.apps[0].modes, [.booked])
        XCTAssertTrue(
            state.migrationNotice?.hasSuffix(" Unlock is off for Discord because Quick look was off.") == true)
    }

    func testPendingQuickLookEnableBecomesUnlockWithTheSameTime() throws {
        let state = try migrated(v1File(modes: ["reply"], pending: [pendingMode("quickLook")]))
        XCTAssertEqual(state.pending.count, 1)
        let id = try XCTUnwrap(UUID(uuidString: appID))
        XCTAssertEqual(state.pending[0].change, .setMode(appID: id, mode: .unlock, enabled: true))
        XCTAssertEqual(state.pending[0].applyAt, Date(timeIntervalSince1970: created + 6 * 3600))
        XCTAssertEqual(state.pending[0].summary, "Turn on Unlock for Discord")
    }

    func testPendingReplyAndRemovedSettingChangesAreDropped() throws {
        let number: [String: Any] = [
            "id": UUID().uuidString, "createdAt": created, "applyAt": created + 3600,
            "change": ["setNumber": ["key": "replySeconds", "value": 300]],
            "summary": "Reply mode length: 3 min → 5 min",
        ]
        let state = try migrated(v1File(modes: ["quickLook"], pending: [pendingMode("reply"), number]))
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(
            state.migrationNotice?.hasSuffix(" 2 pending Quick look or Reply mode changes were canceled.") == true)
    }

    func testRemovedSettingNumbersAreDropped() throws {
        let state = try migrated(
            v1File(modes: ["quickLook"], numbers: ["quickLookMaxTokens": 5, "gatePauseSeconds": 10]))
        XCTAssertEqual(state.settings.numbers, ["gatePauseSeconds": 10])
    }

    func testActiveLegacyGrantKeepsRunning() throws {
        let grant: [String: Any] = [
            "id": UUID().uuidString, "appID": appID, "kind": "quickLook", "createdAt": created,
            "expiresAt": created + 60, "tokensSpent": 2,
        ]
        let state = try migrated(v1File(modes: ["quickLook"], grants: [grant]))
        XCTAssertEqual(state.grants.map(\.kind), [.quickLook])
    }

    func testCurrentVersionDecodesAsOk() throws {
        let fresh = PersistedState.fresh(now: date(2026, 10, 24, 10), timeZone: testTZ)
        XCTAssertEqual(StateCodec.decode(try StateCodec.encode(fresh)), .ok(fresh))
    }

    func testUnknownVersionIsTampered() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["schemaVersion": 3])
        XCTAssertEqual(StateCodec.decode(try StateCodec.seal(payload)), .tampered)
    }

    func testNoticeCanBeDismissed() throws {
        let state = try migrated(v1File(modes: ["quickLook"]))
        var core = EngineCore(state: state, timeZone: testTZ)
        core.dismissMigrationNotice()
        XCTAssertNil(core.state.migrationNotice)
    }
}

extension MigrationTests {
    func testPreReleaseUnlockAndReplyKeepUnlockWithoutOffNotice() throws {
        let state = try migrated(v1File(modes: ["unlock", "reply"]))
        XCTAssertEqual(state.settings.apps[0].modes, [.unlock])
        XCTAssertFalse(try XCTUnwrap(state.migrationNotice).contains("Unlock is off"))
    }
}
