import AppKit
import MyTimeCore
@MainActor final class Enforcer {
    unowned let model: AppModel
    private var pendingTermination = Set<pid_t>()
    init(model: AppModel) { self.model = model }
    func handle(_ process: NSRunningApplication, trigger: EnforcementTrigger) {
        guard let app = AppMonitor().blockedApp(for: process, in: model.core) else { return }
        reconcile(app: app, process: process, trigger: trigger)
    }
    func sweep() {
        for pair in AppMonitor().runningBlocked(in: model.core) {
            reconcile(app: pair.app, process: pair.process, trigger: .startupSweep)
        }
    }
    private func reconcile(app: BlockedApp, process: NSRunningApplication, trigger: EnforcementTrigger) {
        let pid = process.processIdentifier
        let owner = model.overlays.gateOwnerPID
        let action = EnforcementPolicy.decide(
            trigger: trigger,
            context: EnforcementContext(
                terminationPending: pendingTermination.contains(pid), isAllowed: model.core.isAllowed(appID: app.id),
                focusActive: model.core.state.focus != nil, overlayShowingForThisProcess: owner == pid,
                overlayBusyWithOtherProcess: owner != nil && owner != pid))
        switch action {
        case .allow: break
        case .keepHidden: if !process.isHidden { process.hide() }
        case .terminate, .focusCard: terminate(process)
        case .gate:
            process.hide()
            model.overlays.showGate(app: app, process: process)
        }
    }
    func terminateIfNotAllowed(appID: UUID) {
        guard !model.core.isAllowed(appID: appID) else { return }
        for pair in AppMonitor().runningBlocked(in: model.core) where pair.app.id == appID { terminate(pair.process) }
    }
    func processTerminated(pid: pid_t) {
        pendingTermination.remove(pid)
        if model.overlays.gateOwnerPID == pid { model.overlays.closeGate() }
    }
    func terminate(_ process: NSRunningApplication) {
        let pid = process.processIdentifier
        guard pendingTermination.insert(pid).inserted else { return }
        process.terminate()
        let timer = Timer(timeInterval: Constants.forceQuitAfter, repeats: false) { _ in
            MainActor.assumeIsolated {
                if let process = NSRunningApplication(processIdentifier: pid), !process.isTerminated {
                    process.forceTerminate()
                }
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
    }
}
