import Foundation
public enum EnforcementTrigger: Equatable { case launched, activated, startupSweep }
public enum EnforcementAction: Equatable { case allow, gate, focusCard, keepHidden, terminate }
public struct EnforcementContext: Equatable {
    public var terminationPending: Bool
    public var isAllowed: Bool
    public var focusActive: Bool
    public var overlayShowingForThisProcess: Bool
    public var overlayBusyWithOtherProcess: Bool
    public init(
        terminationPending: Bool, isAllowed: Bool, focusActive: Bool, overlayShowingForThisProcess: Bool,
        overlayBusyWithOtherProcess: Bool
    ) {
        self.terminationPending = terminationPending
        self.isAllowed = isAllowed
        self.focusActive = focusActive
        self.overlayShowingForThisProcess = overlayShowingForThisProcess
        self.overlayBusyWithOtherProcess = overlayBusyWithOtherProcess
    }
}
public enum EnforcementPolicy {
    public static func decide(trigger: EnforcementTrigger, context: EnforcementContext) -> EnforcementAction {
        // Spec §5.8 — first match wins.
        if context.terminationPending { return .terminate }
        if context.isAllowed { return .allow }
        if context.overlayShowingForThisProcess { return .keepHidden }
        if trigger == .startupSweep { return .terminate }
        if context.overlayBusyWithOtherProcess { return .terminate }
        if context.focusActive { return .focusCard }
        return .gate
    }
}
