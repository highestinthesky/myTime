import XCTest

@testable import MyTimeCore

/// Quitting myTime needs a reason (spec §5.10). The 60-second wait happens in the Quit window before this is called.
final class QuitTests: XCTestCase {
    func testQuitNeedsAReason() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        XCTAssertThrowsError(try core.quit(reason: "   too short   ")) { error in
            XCTAssertEqual(error as? EngineError, .reasonTooShort)
        }
        XCTAssertTrue(core.state.history.filter { $0.kind == .quit }.isEmpty)
    }

    func testQuitEndsFocusAndRecordsTheReason() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        try core.quit(reason: "  Going on vacation for a week  ")
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.kind, .quit)
        XCTAssertEqual(core.state.history.last?.text, "Quit myTime — “Going on vacation for a week”")
    }
}
