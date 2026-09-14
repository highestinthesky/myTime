import XCTest

@testable import MyTimeCore

/// Reply mode (spec §5.3). Release values: 2 tokens, 3 minutes, 3 per day, note of at least 8 characters.
final class ReplyTests: XCTestCase {
    func testReplySpendsTokensAndKeepsTheTrimmedNote() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10), tokens: 5)
        let discord = core.state.settings.apps[0].id
        let grant = try core.buyReply(appID: discord, note: "  reply to Sam in #capstone \n")
        XCTAssertEqual(grant.kind, .reply)
        XCTAssertEqual(grant.note, "reply to Sam in #capstone")
        XCTAssertEqual(grant.tokensSpent, 2)
        XCTAssertEqual(grant.expiresAt, core.now.addingTimeInterval(180))
        XCTAssertEqual(core.state.tokens, 3)
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.today.replies, 1)
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.state.history.last?.kind, .reply)
        XCTAssertEqual(core.state.history.last?.text, "Reply mode in Discord — “reply to Sam in #capstone”")
    }

    /// `replyUnavailableReason` reports exactly what `buyReply` would throw, without changing anything.
    func testReplyErrorsInOrder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10), tokens: 1)
        let discord = core.state.settings.apps[0].id
        func expect(_ error: EngineError, note: String, app: UUID? = nil) {
            XCTAssertEqual(core.replyUnavailableReason(appID: app ?? discord, note: note), error)
            XCTAssertThrowsError(try core.buyReply(appID: app ?? discord, note: note)) {
                XCTAssertEqual($0 as? EngineError, error)
            }
        }
        expect(.unknownApp, note: "reply to Sam", app: UUID())
        core.state.settings.apps[0].modes = [.quickLook]
        expect(.modeNotAllowed, note: "reply to Sam")
        core.state.settings.apps[0].modes = [.reply]
        core.state.focus = FocusSession(startedAt: core.now)
        expect(.focusActive, note: "reply to Sam")
        core.state.focus = nil
        expect(.noteTooShort, note: "  1234567  ")
        core.updateToday { $0.replies = 3 }
        expect(.notEnoughTokens, note: "12345678")
        core.state.tokens = 2
        expect(.replyLimitReached, note: "12345678")
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertTrue(core.state.grants.isEmpty)
        core.updateToday { $0.replies = 2 }
        XCTAssertNil(core.replyUnavailableReason(appID: discord, note: "12345678"))
    }

    func testReplyLimitIsFreshOnTheNewDay() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 30), tokens: 4)
        let discord = core.state.settings.apps[0].id
        core.updateToday { $0.replies = 3 }
        XCTAssertEqual(core.replyUnavailableReason(appID: discord, note: "reply to Sam"), .replyLimitReached)
        sim.advance(3600)
        _ = core.update(sim.input)
        core.state.tokens = 2
        XCTAssertNil(core.replyUnavailableReason(appID: discord, note: "reply to Sam"))
        _ = try core.buyReply(appID: discord, note: "reply to Sam")
        XCTAssertEqual(core.today.replies, 1)
    }

    func testReplyAccessCanBeExtendedInItsLastSeconds() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: 3)
        let discord = core.state.settings.apps[0].id
        let grant = try core.buyReply(appID: discord, note: "reply to Sam")
        sim.advance(169)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: grant.id))
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertTrue(core.canExtend(grantID: grant.id))
        try core.extendGrant(grantID: grant.id)
        XCTAssertEqual(core.activeGrant(appID: discord)?.expiresAt, grant.expiresAt.addingTimeInterval(30))
        XCTAssertEqual(core.state.tokens, 0)
    }
}
