import AppKit
import MyTimeCore

/// Applies `EnforcementPolicy` to real processes (spec §6). Quit-first: a blocked app without access is quit the
/// moment it's seen, and the gate is shown for the app (not tied to a running process).
@MainActor final class Enforcer {
    unowned let model: AppModel
    private var pendingTermination = Set<pid_t>()

    init(model: AppModel) { self.model = model }

    func handle(_ process: NSRunningApplication, trigger: EnforcementTrigger) {
        guard let app = model.monitor.blockedApp(for: process, in: model.core) else { return }
        reconcile(app: app, process: process, trigger: trigger)
    }

    func sweep() {
        for pair in model.monitor.runningBlocked(in: model.core) {
            reconcile(app: pair.app, process: pair.process, trigger: .startupSweep)
        }
    }

    private func reconcile(app: BlockedApp, process: NSRunningApplication, trigger: EnforcementTrigger) {
        let gateApp = model.overlays.gateAppID
        let context = EnforcementContext(
            terminationPending: pendingTermination.contains(process.processIdentifier),
            isAllowed: model.core.isAllowed(appID: app.id),
            focusActive: model.core.state.focus != nil,
            gateShowingForThisApp: gateApp == app.id,
            gateShowingForOtherApp: gateApp != nil && gateApp != app.id)

        switch EnforcementPolicy.decide(trigger: trigger, context: context) {
        case .allow:
            break
        case .terminate:
            terminate(process)
        case .terminateAndShowGate, .terminateAndShowFocusCard:
            // Run 1 has no focus sessions, so the focus card case can't occur yet; Run 2 gives it its own view.
            let bundleURL = process.bundleURL
            terminate(process)
            model.overlays.showGate(app: app, bundleURL: bundleURL)
        }
    }

    func terminateIfNotAllowed(appID: UUID) {
        guard !model.core.isAllowed(appID: appID) else { return }
        for pair in model.monitor.runningBlocked(in: model.core) where pair.app.id == appID {
            terminate(pair.process)
        }
    }

    func processTerminated(pid: pid_t) {
        pendingTermination.remove(pid)
    }

    /// Polite quit, then force quit after `Constants.forceQuitAfter` if the process is still alive.
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
