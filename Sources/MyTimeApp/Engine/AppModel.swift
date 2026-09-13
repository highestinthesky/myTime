import AppKit
import Foundation
import Observation
import MyTimeCore
@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    private(set) var core: EngineCore
    private(set) var uiNow = Date()
    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let probe = SystemProbe()
    @ObservationIgnored private let monitor = AppMonitor()
    @ObservationIgnored private let scheduler = Scheduler()
    @ObservationIgnored private var events: SystemEvents?
    @ObservationIgnored private(set) var enforcer: Enforcer!
    @ObservationIgnored private(set) var overlays: OverlayController!
    @ObservationIgnored private let labelTimer = RepeatingUITimer()
    @ObservationIgnored private let panelTimer = RepeatingUITimer()
    @ObservationIgnored private var lastSaved: PersistedState?
    @ObservationIgnored private var activity: NSObjectProtocol?
    var displayNow: Date { Date().addingTimeInterval(core.state.clock.offsetSeconds) }
    private init() {
        let store = StateStore()
        let loaded = store.load()
        self.store = store
        self.core = EngineCore(state: loaded.state, timeZone: .current)
        self.lastSaved = loaded.outcome == .existing ? loaded.state : nil
        self.enforcer = Enforcer(model: self)
        self.overlays = OverlayController(model: self)
    }
    func launch() {
        Installer.selfHeal()
        scheduler.onFire = { [weak self] in self?.refresh(.wakeUp) }
        events = SystemEvents { [weak self] in self?.refresh($0) }
        events?.start()
        refresh(.launch)
    }
    func refresh(_ reason: RefreshReason) {
        var input = UpdateInput(
            wall: Date(), continuous: probe.continuousSeconds(), uptime: probe.uptimeSeconds(),
            bootSessionID: probe.bootSessionID, idleSeconds: probe.idleSeconds(), isLocked: probe.isScreenLocked(),
            runningAppIDs: monitor.runningBlockedAppIDs(in: core))
        if case .screenLocked = reason { input.isLocked = true }
        if case .screenUnlocked = reason { input.isLocked = false }
        let result: UpdateResult
        if case .launch = reason { result = core.start(input) } else { result = core.update(input) }
        uiNow = Date()
        for effect in result.effects {
            if case let .terminateIfNotAllowed(id) = effect { enforcer.terminateIfNotAllowed(appID: id) }
        }
        switch reason {
        case .launch: enforcer.sweep()
        case let .appLaunched(process): enforcer.handle(process, trigger: .launched)
        case let .appActivated(process): enforcer.handle(process, trigger: .activated)
        case let .appTerminated(pid): enforcer.processTerminated(pid: pid)
        case .didWake: Installer.selfHeal()
        case .willPowerOff:
            Installer.selfHeal()
            saveNow()
        case .willSleep: saveNow()
        default: break
        }
        overlays.updatePill()
        updateActivityAndTimers()
        saveIfChanged()
        scheduler.schedule(result.nextWakeUp, trustedNow: displayNow)
    }
    @discardableResult func perform<T>(_ intent: (inout EngineCore) throws -> T) rethrows -> T {
        refresh(.intent)
        let result = try intent(&core)
        refresh(.intent)
        return result
    }
    func panelDidOpen() { panelTimer.start(interval: 1) { [weak self] in self?.refresh(.panel) } }
    func panelDidClose() { panelTimer.stop() }
    func saveNow() {
        do {
            try store.save(core.state)
            lastSaved = core.state
        } catch { NSLog("myTime save failed: \(error)") }
    }
    /// Every update refreshes the trusted-clock bookkeeping, and updates run on every app switch. Saving on clock-only
    /// changes would write to disk constantly, so those are saved at most once a minute (enough for the downtime
    /// check in `EngineCore.start`, whose threshold is the 5-minute idle limit). Real changes save immediately.
    private func saveIfChanged() {
        guard let lastSaved else { return saveNow() }
        var comparable = core.state
        comparable.clock = lastSaved.clock
        let clockAge = core.state.clock.lastWall - lastSaved.clock.lastWall
        if comparable != lastSaved || clockAge >= 60 { saveNow() }
    }
    private func updateActivityAndTimers() {
        if overlays.isGateVisible || !core.state.grants.isEmpty || core.activeBooking != nil {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiatedAllowingIdleSystemSleep], reason: "Enforcing app limits")
            }
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if grantCountdown == nil {
            labelTimer.stop()
        } else {
            labelTimer.start(interval: 1) { [weak self] in self?.uiNow = Date() }
        }
    }
    var grantCountdown: GrantCountdown? {
        let candidates = monitor.runningBlocked(in: core).compactMap { app, process -> GrantCountdown? in
            guard let grant = core.activeGrant(appID: app.id) else { return nil }
            return GrantCountdown(
                app: app, process: process, grant: grant,
                remaining: max(0, grant.expiresAt.timeIntervalSince(max(displayNow, grant.startsAt))))
        }
        return candidates.min { $0.remaining < $1.remaining }
    }
    #if DEV_TIMESCALE
        func devReset() {
            core.state = .fresh(now: displayNow, timeZone: .current)
            refresh(.intent)
        }
    #endif
}
struct GrantCountdown {
    let app: BlockedApp
    let process: NSRunningApplication
    let grant: AccessGrant
    let remaining: Double
}
