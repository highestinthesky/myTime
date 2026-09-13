import XCTest
@testable import MyTimeCore

final class EnforcementPolicyTests: XCTestCase {
    private func ctx(
        pending: Bool = false, allowed: Bool = false, focus: Bool = false,
        mine: Bool = false, busy: Bool = false
    ) -> EnforcementContext {
        EnforcementContext(
            terminationPending: pending, isAllowed: allowed, focusActive: focus,
            overlayShowingForThisProcess: mine, overlayBusyWithOtherProcess: busy)
    }

    func testRulesInPriorityOrder() {
        XCTAssertEqual(
            EnforcementPolicy.decide(trigger: .launched, context: ctx(pending: true, allowed: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(allowed: true)), .allow)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx(mine: true, busy: true)), .keepHidden)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(focus: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true, busy: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true)), .focusCard)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx()), .gate)
    }

    /// Each rule must hold on its own, not only in combination with focus (reviewer addition after Run 1).
    func testRulesHoldIndependentlyOfFocus() {
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx()), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(busy: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx(mine: true)), .keepHidden)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(allowed: true, focus: true)), .allow)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(mine: true)), .keepHidden)
    }
}
