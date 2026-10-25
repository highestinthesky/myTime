import XCTest

@testable import MyTimeCore

final class UnlockCopyTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testStreakAndNextUnlockLines() {
        let resets = date(2026, 9, 14, 14, 28)
        XCTAssertEqual(
            UnlockCopy.streakLine(multiplier: 4, resetsAt: resets, timeZone: testTZ, locale: en),
            "4× — resets at 2:28 PM")
        XCTAssertEqual(
            UnlockCopy.nextUnlockLine(multiplier: 2, resetsAt: resets, timeZone: testTZ, locale: en),
            "Next Unlock: 2× until 2:28 PM")
    }

    func testGateStrings() {
        XCTAssertEqual(UnlockCopy.unlockButton(lengthSeconds: 300, cost: 10), "Unlock 5 min · 10 tokens")
        XCTAssertEqual(UnlockCopy.unlockButton(lengthSeconds: 60, cost: 1), "Unlock 1 min · 1 token")
        XCTAssertEqual(UnlockCopy.needsMore(3), "Needs 3 more")
        XCTAssertEqual(UnlockCopy.shortOfTokens(needed: 1, lengthSeconds: 60), "Unlock needs 1 more token for 1 min.")
        XCTAssertEqual(UnlockCopy.shortOfTokens(needed: 4, lengthSeconds: 60), "Unlock needs 4 more tokens for 1 min.")
    }

    func testWarningTitle() {
        XCTAssertEqual(UnlockCopy.closesIn(appNames: ["Discord"], remaining: 30), "Discord closes in 0:30")
        XCTAssertEqual(
            UnlockCopy.closesIn(appNames: ["Discord", "TextEdit"], remaining: 12), "Unlocked apps close in 0:12")
    }

    func testMenuBarRoundsUpToTheUnit() {
        XCTAssertEqual(UnlockCopy.menuBarRemaining(241), "5 min")
        XCTAssertEqual(UnlockCopy.menuBarRemaining(60), "1 min")
        XCTAssertEqual(UnlockCopy.menuBarRemaining(0.4), "1 min")
    }
}
