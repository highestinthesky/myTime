import XCTest
@testable import MyTimeCore

final class StateCodecTests: XCTestCase {
    let now = date(2026, 9, 14, 10)

    func testRoundTrip() throws {
        var s = PersistedState.fresh(now: now, timeZone: testTZ)
        s.tokens = 7
        XCTAssertEqual(StateCodec.decode(try StateCodec.encode(s)), .ok(s))
    }

    func testEnvelopeShape() throws {
        let data = try StateCodec.encode(.fresh(now: now, timeZone: testTZ))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertNotNil(obj["payload"] as? String)
        XCTAssertEqual((obj["mac"] as? String)?.count, 64)
    }

    func testEditedPayloadIsTampered() throws {
        let data = try StateCodec.encode(.fresh(now: now, timeZone: testTZ))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(obj["payload"] as? String)))
        let original = String(decoding: payload, as: UTF8.self)
        let edited = original.replacingOccurrences(of: "\"tokens\":0", with: "\"tokens\":9")
        XCTAssertNotEqual(original, edited)
        obj["payload"] = Data(edited.utf8).base64EncodedString()
        XCTAssertEqual(StateCodec.decode(try JSONSerialization.data(withJSONObject: obj)), .tampered)
    }

    func testGarbageIsTampered() {
        XCTAssertEqual(StateCodec.decode(Data("not json".utf8)), .tampered)
        XCTAssertEqual(StateCodec.decode(Data("{\"v\":1,\"payload\":\"%%%\",\"mac\":\"zz\"}".utf8)), .tampered)
    }

    func testPenalizedState() {
        let p = PersistedState.penalized(now: now, timeZone: testTZ)
        let week = CalendarKeys.weekKey(now, dayStartHour: 4, timeZone: testTZ)
        let day = CalendarKeys.dayKey(now, dayStartHour: 4, timeZone: testTZ)
        XCTAssertEqual(p.tokens, 0)
        XCTAssertEqual(p.weekly[week]?.allowanceForfeited, true)
        XCTAssertEqual(p.weekly[week]?.emergencyUses, 99)
        XCTAssertEqual(p.daily[day]?.replies, 99)
        XCTAssertEqual(p.daily[day]?.claimedAwaySeconds, 1_000_000)
        XCTAssertEqual(p.tamperNoticeUntil, now.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(p.history.last?.kind, .tamperDetected)
        XCTAssertEqual(p.history.last?.text, "Saved data was edited outside myTime. Balances were reset.")
    }
}
