import XCTest

@testable import MyTimeCore

final class MigrationCompatibilityTests: XCTestCase {
    private let now = date(2026, 10, 24, 10)
    private let appID = UUID(uuidString: "8E1A1C2B-0000-4000-8000-000000000001")!
    private let removedKeys = [
        "quickLookSecondsPerToken", "quickLookMaxTokens", "replyTokenCost", "replySeconds", "replyPerDay",
    ]

    private func payload() throws -> [String: Any] {
        var state = PersistedState.fresh(now: now, timeZone: testTZ)
        state.schemaVersion = 1
        state.settings.apps[0].id = appID
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.myTime.encode(state)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        var apps = try XCTUnwrap(settings["apps"] as? [[String: Any]])
        apps[0]["modes"] = ["quickLook", "reply", "booked"]
        settings["apps"] = apps
        json["settings"] = settings
        return json
    }

    private func decode(_ json: [String: Any]) throws -> PersistedState {
        let file = try StateCodec.seal(JSONSerialization.data(withJSONObject: json))
        guard case let .migrated(state) = StateCodec.decode(file) else {
            XCTFail("expected migrated legacy state")
            throw CocoaError(.coderReadCorrupt)
        }
        return state
    }

    private func pending(_ change: [String: Any], summary: String = "original") -> [String: Any] {
        [
            "id": UUID().uuidString, "createdAt": now.timeIntervalSince1970,
            "applyAt": now.addingTimeInterval(3600).timeIntervalSince1970,
            "change": change, "summary": summary,
        ]
    }

    func testPendingMetadataAndUnaffectedChangesCarryOver() throws {
        var json = try payload()
        let legacy = pending([
            "setMode": ["appID": appID.uuidString.lowercased(), "mode": "quickLook", "enabled": true]
        ])
        let unlock = pending(["setMode": ["appID": appID.uuidString, "mode": "unlock", "enabled": true]])
        let booked = pending(["setMode": ["appID": appID.uuidString, "mode": "booked", "enabled": true]])
        let number = pending(["setNumber": ["key": "weeklyAllowanceSeconds", "value": 28800]])
        let remove = pending(["removeApp": ["id": appID.uuidString]])
        let uninstall = pending(["uninstall": [:]])
        json["pending"] = [legacy, unlock, booked, number, remove, uninstall]
        let state = try decode(json)
        XCTAssertEqual(state.pending.count, 6)
        let first = try XCTUnwrap(state.pending.first)
        XCTAssertEqual(first.id.uuidString, legacy["id"] as? String)
        XCTAssertEqual(first.createdAt, now)
        XCTAssertEqual(first.applyAt, now.addingTimeInterval(3600))
        XCTAssertEqual(first.summary, "Turn on Unlock for Discord")
        XCTAssertEqual(first.change, .setMode(appID: appID, mode: .unlock, enabled: true))
        for (actual, original) in zip(state.pending.dropFirst(), [unlock, booked, number, remove, uninstall]) {
            let expected = try JSONDecoder.myTime.decode(
                PendingChange.self, from: JSONSerialization.data(withJSONObject: original))
            XCTAssertEqual(actual, expected)
        }
    }

    func testAllRemovedNumbersAndPendingChangesAreDropped() throws {
        var json = try payload()
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        var numbers = Dictionary(uniqueKeysWithValues: removedKeys.map { ($0, 5) })
        numbers["gatePauseSeconds"] = 10
        settings["numbers"] = numbers
        json["settings"] = settings
        json["pending"] = removedKeys.map { pending(["setNumber": ["key": $0, "value": 5]]) }
        let day: [String: Any] = ["quickLooks": 3, "replies": 2, "tokensSpent": 9]
        json["daily"] = ["2026-10-23": day, "2026-10-24": day]
        var migratedJSON = json
        StateMigration.migrateV1(&migratedJSON)
        let daily = try XCTUnwrap(migratedJSON["daily"] as? [String: [String: Any]])
        for value in daily.values {
            XCTAssertNil(value["quickLooks"])
            XCTAssertNil(value["replies"])
            XCTAssertEqual(value["tokensSpent"] as? Int, 9)
        }
        let state = try decode(json)
        XCTAssertEqual(state.settings.numbers, ["gatePauseSeconds": 10])
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(
            try XCTUnwrap(state.migrationNotice).hasSuffix(" 5 pending Quick look or Reply mode changes were canceled.")
        )
    }

    func testSingleDroppedChangeUsesSingularNotice() throws {
        var json = try payload()
        json["pending"] = [pending(["setMode": ["appID": appID.uuidString, "mode": "reply", "enabled": false]])]
        let state = try decode(json)
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(
            try XCTUnwrap(state.migrationNotice).hasSuffix(" A pending Quick look or Reply mode change was canceled."))
    }

    func testReplyOnlyAppNoticesFollowAppOrder() throws {
        var json = try payload()
        json["settings"] = [
            "numbers": [:],
            "apps": [
                ["id": appID.uuidString, "name": "Discord", "bundleIDs": ["com.hnc.Discord"], "modes": ["reply"]],
                [
                    "id": UUID().uuidString, "name": "Notes", "bundleIDs": ["com.example.notes"],
                    "modes": ["reply", "booked"],
                ],
                ["id": UUID().uuidString, "name": "Mail", "bundleIDs": ["com.example.mail"], "modes": []],
            ],
        ]
        let state = try decode(json)
        XCTAssertEqual(state.settings.apps.map(\.modes), [[], [.booked], []])
        XCTAssertTrue(
            try XCTUnwrap(state.migrationNotice).hasSuffix(
                " Unlock is off for Discord because Quick look was off. Unlock is off for Notes because Quick look was off."
            ))
    }

    func testBalancesFocusGrantsBookingsStatsHistoryAndClockArePreserved() throws {
        var original = PersistedState.fresh(now: now, timeZone: testTZ)
        original.schemaVersion = 1
        original.tokens = 19
        original.progressSeconds = 123
        original.focus = FocusSession(startedAt: now, creditedSeconds: 456)
        original.grants = [GrantKind.quickLook, .reply, .emergency].map {
            AccessGrant(
                appID: original.settings.apps[0].id, kind: $0, createdAt: now,
                expiresAt: now.addingTimeInterval(60), tokensSpent: 2, note: "kept verbatim")
        }
        original.bookings = [Booking(start: now.addingTimeInterval(3600), durationSeconds: 1800, createdAt: now)]
        original.daily = [
            "2026-10-24": DailyStats(
                focusSeconds: 456, tokensEarned: 9, tokensSpent: 2, backedOff: 3,
                claimedAwaySeconds: 100, unclaimedAwaySeconds: 200)
        ]
        original.weekly = ["2026-W43": WeeklyStats(emergencyUses: 1, allowanceForfeited: true)]
        original.history = [HistoryKind.quickLook, .reply, .extended].map {
            HistoryEvent(date: now, kind: $0, text: "legacy text \($0.rawValue)")
        }
        original.clock = TrustedClockState(
            offsetSeconds: 3600, lastWall: now.timeIntervalSince1970,
            lastContinuous: 1000, bootSessionID: "BOOT-A")
        original.tamperNoticeUntil = now.addingTimeInterval(86400)
        original.unlock = ActiveUnlock(
            appID: appID, startedAt: now, endsAt: now.addingTimeInterval(60),
            lengthSeconds: 60, multiplier: 4, cost: 4, dayKey: "2026-10-24")
        original.unlockStreak = UnlockStreak(lastMultiplier: 2, lastEnd: now, dayKey: "2026-10-24")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.myTime.encode(original)) as? [String: Any])
        let state = try decode(json)
        XCTAssertEqual(state.tokens, original.tokens)
        XCTAssertEqual(state.progressSeconds, original.progressSeconds)
        XCTAssertEqual(state.tokensDayKey, original.tokensDayKey)
        XCTAssertEqual(state.focus, original.focus)
        XCTAssertEqual(state.grants, original.grants)
        XCTAssertEqual(state.bookings, original.bookings)
        XCTAssertEqual(state.daily, original.daily)
        XCTAssertEqual(state.weekly, original.weekly)
        XCTAssertEqual(state.history, original.history)
        XCTAssertEqual(state.clock, original.clock)
        XCTAssertEqual(state.tamperNoticeUntil, original.tamperNoticeUntil)
        XCTAssertNil(state.unlock)
        XCTAssertNil(state.unlockStreak)
        let core = EngineCore(state: state, timeZone: testTZ)
        XCTAssertEqual(core.unlockQuote(at: now).multiplier, 1)
    }

    func testLegacyReplyGrantRunsUntilItsOriginalExpiry() throws {
        var json = try payload()
        json["grants"] = [
            [
                "id": UUID().uuidString, "appID": appID.uuidString, "kind": "reply",
                "createdAt": now.timeIntervalSince1970, "expiresAt": now.addingTimeInterval(60).timeIntervalSince1970,
                "tokensSpent": 2, "note": "old reply note",
            ]
        ]
        var core = EngineCore(state: try decode(json), timeZone: testTZ)
        var sim = Sim(wall: now)
        _ = core.start(sim.input)
        XCTAssertTrue(core.isAllowed(appID: appID))
        XCTAssertEqual(core.activeGrant(appID: appID)?.note, "old reply note")
        sim.advance(59)
        XCTAssertEqual(core.update(sim.input).effects, [])
        XCTAssertTrue(core.isAllowed(appID: appID))
        sim.advance(1)
        XCTAssertEqual(core.update(sim.input).effects, [.terminateIfNotAllowed(appID: appID)])
        XCTAssertFalse(core.isAllowed(appID: appID))
    }

    func testDismissalSurvivesCurrentVersionReload() throws {
        let state = try decode(payload())
        XCTAssertEqual(StateCodec.decode(try StateCodec.encode(state)), .ok(state))
        var core = EngineCore(state: state, timeZone: testTZ)
        core.dismissMigrationNotice()
        let saved = try StateCodec.encode(core.state)
        guard case let .ok(reloaded) = StateCodec.decode(saved) else { return XCTFail("expected schema 2") }
        XCTAssertNil(reloaded.migrationNotice)
    }

    func testBadMACAndMalformedLegacyPayloadsAreTampered() throws {
        let json = try payload()
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: StateCodec.seal(JSONSerialization.data(withJSONObject: json)))
                as? [String: Any])
        envelope["mac"] = String(repeating: "0", count: 64)
        XCTAssertEqual(StateCodec.decode(try JSONSerialization.data(withJSONObject: envelope)), .tampered)
        var badVersion = json
        badVersion["schemaVersion"] = true
        var missingSettings = json
        missingSettings.removeValue(forKey: "settings")
        for invalid in [badVersion, missingSettings, ["schemaVersion": 1]] {
            XCTAssertEqual(
                StateCodec.decode(try StateCodec.seal(JSONSerialization.data(withJSONObject: invalid))), .tampered)
        }
    }
}
