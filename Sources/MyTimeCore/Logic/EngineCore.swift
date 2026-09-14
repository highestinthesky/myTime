import Foundation

public struct EngineCore {
    public var state: PersistedState
    public var runtime: EngineRuntime
    public private(set) var now: Date
    public let timeZone: TimeZone

    public init(state: PersistedState, timeZone: TimeZone) {
        self.state = state
        self.runtime = EngineRuntime()
        self.now = Date(timeIntervalSince1970: state.clock.lastWall)
        self.timeZone = timeZone
    }

    public mutating func start(_ input: UpdateInput) -> UpdateResult {
        let hadPrevious = state.clock.lastWall > 0
        let previousTrusted = state.clock.lastWall + state.clock.offsetSeconds
        now = Date(
            timeIntervalSince1970: TrustedClock.update(
                &state.clock, wall: input.wall.timeIntervalSince1970, continuous: input.continuous,
                bootSessionID: input.bootSessionID))
        if state.focus != nil && hadPrevious
            && now.timeIntervalSince1970 - previousTrusted > Double(setting(.idleThresholdSeconds))
        {
            endFocusWithoutVesting("Focus ended · myTime wasn't running")
        }
        runtime = EngineRuntime()
        return update(input)
    }

    public mutating func update(_ input: UpdateInput) -> UpdateResult {
        now = Date(
            timeIntervalSince1970: TrustedClock.update(
                &state.clock, wall: input.wall.timeIntervalSince1970, continuous: input.continuous,
                bootSessionID: input.bootSessionID))
        let key = CalendarKeys.dayKey(now, dayStartHour: dayStartHour, timeZone: timeZone)
        if state.tokensDayKey != key {
            let unused = state.tokens
            if unused > 0 { record(.dayReset, "New day · \(unused) unused token\(unused == 1 ? "" : "s") cleared") }
            state.tokens = 0
            state.progressSeconds = 0
            runtime.unvestedSeconds = 0
            state.tokensDayKey = key
        }

        // Step 4: focus accrual and away (spec §5.2)
        accrueFocus(input)

        let expired = state.grants.filter { $0.expiresAt <= now }.map(\.appID)
        state.grants.removeAll { $0.expiresAt <= now }
        var effects = Array(Set(expired)).map { EngineEffect.terminateIfNotAllowed(appID: $0) }

        // Step 6: booking transitions (spec §5.4). A grant expiring as a session ends closes the app once.
        for effect in applyBookingTransitions(input) where !effects.contains(effect) {
            effects.append(effect)
        }
        return UpdateResult(
            effects: effects,
            nextWakeUp: WakeUpPlanner.next(state: state, runtime: runtime, now: now, nextDayStart: nextDayStart))
    }

    public var dayStartHour: Int { setting(.dayStartHour) }
    public var today: DailyStats {
        state.daily[CalendarKeys.dayKey(now, dayStartHour: dayStartHour, timeZone: timeZone)] ?? DailyStats()
    }
    public var nextDayStart: Date {
        CalendarKeys.nextDayStart(after: now, dayStartHour: dayStartHour, timeZone: timeZone)
    }
    public var secondsToNextToken: Double {
        max(0, Double(setting(.focusSecondsPerToken)) - state.progressSeconds - runtime.unvestedSeconds)
    }
    public func setting(_ key: SettingKey) -> Int { state.settings[key] }
    public func app(id: UUID) -> BlockedApp? { state.settings.apps.first { $0.id == id } }
    public func app(bundleID: String) -> BlockedApp? { state.settings.apps.first { $0.bundleIDs.contains(bundleID) } }
    public var activeBooking: Booking? { state.bookings.first { $0.isActive(at: now) } }
    public func activeGrant(appID: UUID) -> AccessGrant? {
        state.grants.filter { $0.appID == appID && now < $0.expiresAt }.max { $0.expiresAt < $1.expiresAt }
    }
    public func remaining(of grant: AccessGrant) -> Double {
        max(0, grant.expiresAt.timeIntervalSince(now))
    }
    public func isAllowed(appID: UUID) -> Bool {
        if activeGrant(appID: appID) != nil { return true }
        return activeBooking != nil && app(id: appID)?.modes.contains(.booked) == true
    }

    public mutating func buyQuickLook(appID: UUID, tokens: Int) throws -> AccessGrant {
        guard let app = app(id: appID) else { throw EngineError.unknownApp }
        guard app.modes.contains(.quickLook) else { throw EngineError.modeNotAllowed }
        guard state.focus == nil else { throw EngineError.focusActive }
        guard (1...setting(.quickLookMaxTokens)).contains(tokens) else {
            throw EngineError.invalidAmount(max: setting(.quickLookMaxTokens))
        }
        guard state.tokens >= tokens else { throw EngineError.notEnoughTokens }
        state.tokens -= tokens
        updateToday {
            $0.tokensSpent += tokens
            $0.quickLooks += 1
        }
        // The countdown starts now: the gated app relaunches within about a second of buying.
        let duration = tokens * setting(.quickLookSecondsPerToken)
        let grant = AccessGrant(
            appID: appID, kind: .quickLook, createdAt: now,
            expiresAt: now.addingTimeInterval(Double(duration)), tokensSpent: tokens)
        state.grants.append(grant)
        record(.quickLook, "Quick look in \(app.name) · \(DurationFormat.clock(Double(duration))) · \(tokens) ◆")
        return grant
    }

    public func canExtend(grantID: UUID) -> Bool {
        guard let grant = state.grants.first(where: { $0.id == grantID }) else { return false }
        return (grant.kind == .quickLook || grant.kind == .reply) && now < grant.expiresAt
            && remaining(of: grant) <= Constants.extendWindow && state.tokens >= 1
    }
    public mutating func extendGrant(grantID: UUID) throws {
        guard let index = state.grants.firstIndex(where: { $0.id == grantID }) else { throw EngineError.unknownGrant }
        guard canExtend(grantID: grantID) else { throw EngineError.cannotExtend }
        state.grants[index].expiresAt = state.grants[index].expiresAt.addingTimeInterval(
            Double(setting(.quickLookSecondsPerToken)))
        state.tokens -= 1
        updateToday { $0.tokensSpent += 1 }
        record(
            .extended,
            "Extended \(app(id: state.grants[index].appID)?.name ?? "app") · +\(setting(.quickLookSecondsPerToken)) s")
    }
    public mutating func recordBackedOff(appID: UUID) {
        guard let app = app(id: appID) else { return }
        updateToday { $0.backedOff += 1 }
        record(.backedOff, "Backed off from \(app.name)")
    }

    mutating func vest(_ seconds: Double) {
        guard seconds > 0 else { return }
        updateToday { $0.focusSeconds += seconds }
        if state.focus != nil { state.focus!.creditedSeconds += seconds }
        state.progressSeconds += seconds
        while state.progressSeconds >= Double(setting(.focusSecondsPerToken)) {
            state.progressSeconds -= Double(setting(.focusSecondsPerToken))
            state.tokens += 1
            updateToday { $0.tokensEarned += 1 }
            record(.tokenEarned, "Earned a token")
        }
    }
    mutating func updateToday(_ body: (inout DailyStats) -> Void) {
        let key = CalendarKeys.dayKey(now, dayStartHour: dayStartHour, timeZone: timeZone)
        var stats = state.daily[key] ?? DailyStats()
        body(&stats)
        state.daily[key] = stats
    }
    mutating func record(_ kind: HistoryKind, _ text: String) {
        state.history.append(HistoryEvent(date: now, kind: kind, text: text))
        if state.history.count > Constants.historyCap {
            state.history.removeFirst(state.history.count - Constants.historyCap)
        }
    }
    #if DEV_TIMESCALE
        public mutating func devAddToken() { state.tokens += 1 }
        public mutating func devAddProgress(seconds: Double) { vest(seconds) }
        public mutating func devSimulateNewDay() { state.tokensDayKey = "" }
    #endif
}
