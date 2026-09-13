import XCTest

@testable import MyTimeCore

/// Enforcement is quit-first (spec §5.8, revised after Run 1 review): a blocked app without access is quit the moment
/// it appears, and the gate is shown for the *app*. Hiding caused Electron apps to flash black windows.
final class EnforcementPolicyTests: XCTestCase {
    private func ctx(
        pending: Bool = false, allowed: Bool = false, focus: Bool = false,
        mine: Bool = false, other: Bool = false
    ) -> EnforcementContext {
        EnforcementContext(
            terminationPending: pending, isAllowed: allowed, focusActive: focus,
            gateShowingForThisApp: mine, gateShowingForOtherApp: other)
    }

    func testRulesInPriorityOrder() {
        XCTAssertEqual(
            EnforcementPolicy.decide(trigger: .launched, context: ctx(pending: true, allowed: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(allowed: true)), .allow)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx(mine: true, other: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(focus: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true, other: true)), .terminate)
        XCTAssertEqual(
            EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true)), .terminateAndShowFocusCard)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx()), .terminateAndShowGate)
    }

    /// Each rule must hold on its own, not only in combination with focus.
    func testRulesHoldIndependentlyOfFocus() {
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx()), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(other: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(allowed: true, focus: true)), .allow)
    }

    /// Reopening an app while its own gate is up quits the new process quietly and leaves the gate in place.
    func testReopeningWhileGateIsUpQuitsSilently() {
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(mine: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx(mine: true)), .terminate)
    }
}
