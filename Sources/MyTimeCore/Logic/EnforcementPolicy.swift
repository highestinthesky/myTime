import Foundation

public enum EnforcementTrigger: Equatable { case launched, activated, startupSweep }

/// Quit-first enforcement (spec §5.8). A blocked app without access never keeps running: hiding an Electron app
/// while it starts up makes it flash black windows, so it is quit immediately and the gate is shown for the app.
public enum EnforcementAction: Equatable {
    case allow
    /// Quit quietly; nothing is shown.
    case terminate
    /// Quit, then show the gate for this app.
    case terminateAndShowGate
    /// Quit, then show the "You're focusing" card for this app.
    case terminateAndShowFocusCard
}

public struct EnforcementContext: Equatable {
    public var terminationPending: Bool
    public var isAllowed: Bool
    public var focusActive: Bool
    public var gateShowingForThisApp: Bool
    public var gateShowingForOtherApp: Bool

    public init(
        terminationPending: Bool, isAllowed: Bool, focusActive: Bool, gateShowingForThisApp: Bool,
        gateShowingForOtherApp: Bool
    ) {
        self.terminationPending = terminationPending
        self.isAllowed = isAllowed
        self.focusActive = focusActive
        self.gateShowingForThisApp = gateShowingForThisApp
        self.gateShowingForOtherApp = gateShowingForOtherApp
    }
}

public enum EnforcementPolicy {
    /// First match wins.
    public static func decide(trigger: EnforcementTrigger, context: EnforcementContext) -> EnforcementAction {
        if context.terminationPending { return .terminate }
        if context.isAllowed { return .allow }
        if context.gateShowingForThisApp { return .terminate }
        if trigger == .startupSweep { return .terminate }
        if context.gateShowingForOtherApp { return .terminate }
        if context.focusActive { return .terminateAndShowFocusCard }
        return .terminateAndShowGate
    }
}
