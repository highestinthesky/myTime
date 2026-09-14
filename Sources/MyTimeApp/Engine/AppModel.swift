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
    @ObservationIgnored let monitor = AppMonitor()
    @ObservationIgnored private let scheduler = Scheduler()
    @ObservationIgnored private var events: SystemEvents?
    @ObservationIgnored private(set) var enforcer: Enforcer!
    @ObservationIgnored private(set) var overlays: OverlayController!
    @ObservationIgnored private(set) var router: WindowRouter!
    @ObservationIgnored private(set) var headsUp: HeadsUpController!
    @ObservationIgnored private let countdownTimer = RepeatingUITimer()
    @ObservationIgnored private let bookingLabelTimer = RepeatingUITimer()
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
        self.router = WindowRouter(model: self)
        self.headsUp = HeadsUpController(model: self)
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
        switch reason {
        case .launch:
            result = core.start(input)
        case .willSleep:
            result = core.handleWillSleep(input)
        case .didWake:
            result = core.handleDidWake(input)
        default:
            result = core.update(input)
        }
        uiNow = Date()
        for effect in result.effects {
            switch effect {
            case let .terminateIfNotAllowed(appID):
                enforcer.terminateIfNotAllowed(appID: appID)
            case let .bookingHeadsUp(bookingID):
                headsUp.show(bookingID: bookingID)
            case .uninstall:
                break
            }
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
        overlays.syncGateMode()
        overlays.updatePill()
        updateActivityAndTimers()
        saveIfChanged(throttled: reason.isUITick)
        scheduler.schedule(result.nextWakeUp, trustedNow: displayNow)
    }
    @discardableResult func perform<T>(_ intent: (inout EngineCore) throws -> T) rethrows -> T {
        refresh(.intent)
        let result = try intent(&core)
        refresh(.intent)
        return result
    }
    func startFocus() {
        perform { core in
            core.startFocus()
        }
    }
    func endFocus() {
        perform { core in
            core.endFocus()
        }
    }
    func confirmClaim() {
        perform { core in
            core.confirmClaim()
        }
    }
    func dismissClaim() {
        perform { core in
            core.dismissClaim()
        }
    }
    func createBooking(start: Date, durationSeconds: Int) throws {
        try perform { core in
            _ = try core.createBooking(start: start, durationSeconds: durationSeconds)
        }
    }
    func cancelBooking(id: UUID) {
        perform { core in
            try? core.cancelBooking(id: id)
        }
    }
    func endBooking(id: UUID) {
        perform { core in
            core.endBooking(id: id)
        }
    }
    func extendBooking(id: UUID) {
        perform { core in
            try? core.extendBooking(id: id)
        }
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
    /// check in `EngineCore.start`, whose threshold is the 5-minute idle limit). The once-a-second panel and countdown
    /// refreshes (`throttled`) are held to the same limit, because during focus each one credits another second.
    /// Everything else saves as soon as it changes.
    private func saveIfChanged(throttled: Bool) {
        guard let lastSaved else { return saveNow() }
        var comparable = core.state
        comparable.clock = lastSaved.clock
        let saveAge = core.state.clock.lastWall - lastSaved.clock.lastWall
        let changed = comparable != lastSaved
        if saveAge >= 60 || (changed && !throttled) { saveNow() }
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
        // While a grant countdown is on screen, refresh the engine every second so the pill, the menu bar label,
        // and `canExtend` (which reads `core.now`) stay current. Nothing ticks when no countdown is visible.
        if grantCountdown == nil {
            countdownTimer.stop()
        } else {
            countdownTimer.start(interval: 1) { [weak self] in self?.refresh(.uiTick) }
        }
        if grantCountdown == nil && bookingCountdown != nil {
            bookingLabelTimer.start(interval: 60) { [weak self] in
                self?.uiNow = Date()
            }
        } else {
            bookingLabelTimer.stop()
        }
    }
    var grantCountdown: GrantCountdown? {
        let candidates = monitor.runningBlocked(in: core).compactMap { app, process -> GrantCountdown? in
            guard let grant = core.activeGrant(appID: app.id) else { return nil }
            return GrantCountdown(
                app: app, process: process, grant: grant,
                remaining: max(0, grant.expiresAt.timeIntervalSince(displayNow)))
        }
        return candidates.min { $0.remaining < $1.remaining }
    }
    var ringStep: Int {
        let progress = core.state.progressSeconds + core.runtime.unvestedSeconds
        let fraction = progress / Double(core.setting(.focusSecondsPerToken))
        return max(0, min(12, Int((fraction * 12).rounded(.down))))
    }
    var bookingCountdown: Double? {
        guard let booking = core.activeBooking else {
            return nil
        }
        let bookedAppIsRunning = monitor.runningBlocked(in: core).contains { app, _ in
            app.modes.contains(.booked)
        }
        guard bookedAppIsRunning else {
            return nil
        }
        return max(0, booking.end.timeIntervalSince(displayNow))
    }
    var showsClaimDot: Bool {
        core.claimableSeconds >= Constants.minClaimable
            && grantCountdown == nil
            && bookingCountdown == nil
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
