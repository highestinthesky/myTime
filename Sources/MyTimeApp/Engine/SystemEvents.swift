import AppKit
enum RefreshReason {
    case launch, appLaunched(NSRunningApplication), appActivated(NSRunningApplication), appTerminated(pid_t),
        screenLocked, screenUnlocked, willSleep, didWake, willPowerOff, clockChanged, wakeUp, intent, panel, uiTick
}
extension RefreshReason {
    /// The once-a-second refreshes that run only while the panel or a grant countdown is on screen.
    var isUITick: Bool {
        switch self {
        case .panel, .uiTick: return true
        default: return false
        }
    }
}
@MainActor final class SystemEvents {
    private let handler: (RefreshReason) -> Void
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    init(handler: @escaping (RefreshReason) -> Void) { self.handler = handler }
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).map(RefreshReason.appLaunched)
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).map(RefreshReason.appActivated)
        }
        observe(workspace, NSWorkspace.didUnhideApplicationNotification) {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).map(RefreshReason.appActivated)
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).map {
                .appTerminated($0.processIdentifier)
            }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { _ in .willSleep }
        observe(workspace, NSWorkspace.didWakeNotification) { _ in .didWake }
        observe(workspace, NSWorkspace.willPowerOffNotification) { _ in .willPowerOff }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { _ in .screenLocked }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { _ in .screenUnlocked }
        let standard = NotificationCenter.default
        observe(standard, .NSSystemClockDidChange) { _ in .clockChanged }
        observe(standard, .NSSystemTimeZoneDidChange) { _ in .clockChanged }
    }
    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ map: @escaping (Notification) -> RefreshReason?
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { if let reason = map(note) { self?.handler(reason) } }
        }
        tokens.append((center, token))
    }
    deinit { for (center, token) in tokens { center.removeObserver(token) } }
}
