import XCTest
@testable import MyTimeCore

final class TrustedClockTests: XCTestCase {
    func testFirstReadingSetsBaseline() {
        var s = TrustedClockState()
        XCTAssertEqual(TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A"), 1000)
        XCTAssertEqual(s.offsetSeconds, 0)
        XCTAssertEqual(s.bootSessionID, "A")
    }

    func testForwardJumpIsCancelled() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 1000 + 10_800 + 1, continuous: 51, bootSessionID: "A")
        XCTAssertEqual(t, 1001, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, -10_800, accuracy: 0.001)
    }

    func testBackwardJumpIsCancelled() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 10_000, continuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 10_000 - 7200 + 1, continuous: 51, bootSessionID: "A")
        XCTAssertEqual(t, 10_001, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 7200, accuracy: 0.001)
    }

    func testSmallDriftIsAccepted() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        XCTAssertEqual(TrustedClock.update(&s, wall: 1631, continuous: 650, bootSessionID: "A"), 1631, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 0)
    }

    func testLongGapWithoutJumpIsAccepted() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        XCTAssertEqual(TrustedClock.update(&s, wall: 1600, continuous: 650, bootSessionID: "A"), 1600, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 0)
    }

    func testNewBootKeepsOffsetWithoutAdjusting() {
        var s = TrustedClockState(offsetSeconds: -500, lastWall: 1000, lastContinuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 90_000, continuous: 10, bootSessionID: "B")
        XCTAssertEqual(t, 89_500, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, -500)
        XCTAssertEqual(s.bootSessionID, "B")
    }
}
