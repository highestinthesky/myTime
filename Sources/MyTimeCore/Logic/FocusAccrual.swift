import Foundation

extension EngineCore {
    public var isAway: Bool {
        runtime.awayStartUptime != nil
    }

    public var claimableSeconds: Double {
        let remainingBudget = Double(setting(.awayClaimSecondsPerDay)) - today.claimedAwaySeconds
        return max(0, min(today.unclaimedAwaySeconds, remainingBudget))
    }

    public mutating func startFocus() {
        guard state.focus == nil else {
            return
        }

        state.focus = FocusSession(startedAt: now)
        runtime.unvestedSeconds = 0
        runtime.awayStartUptime = nil
        record(.focusStarted, "Started focus")
    }

    public mutating func endFocus() {
        guard state.focus != nil else {
            return
        }

        vest(runtime.unvestedSeconds)
        runtime.unvestedSeconds = 0
        runtime.awayStartUptime = nil
        let creditedSeconds = state.focus?.creditedSeconds ?? 0
        record(.focusEnded, "Focus ended · \(DurationFormat.short(creditedSeconds))")
        state.focus = nil
    }

    public mutating func confirmClaim() {
        let seconds = claimableSeconds
        if seconds > 0 {
            updateToday { stats in
                stats.claimedAwaySeconds += seconds
            }
            vest(seconds)
            record(
                .awayClaimed,
                "Counted \(DurationFormat.short(seconds)) away as focus"
            )
        }
        updateToday { stats in
            stats.unclaimedAwaySeconds = 0
        }
    }

    public mutating func dismissClaim() {
        updateToday { stats in
            stats.unclaimedAwaySeconds = 0
        }
    }

    public mutating func handleWillSleep(_ input: UpdateInput) -> UpdateResult {
        let result = update(input)
        runtime.sleepStartContinuous = input.continuous
        if state.focus != nil && !isAway {
            runtime.awayStartUptime = input.uptime - input.idleSeconds
            runtime.unvestedSeconds = 0
        }
        return result
    }

    public mutating func handleDidWake(_ input: UpdateInput) -> UpdateResult {
        if state.focus != nil,
            let sleepStartContinuous = runtime.sleepStartContinuous,
            input.continuous - sleepStartContinuous >= Double(setting(.autoEndAwaySeconds))
        {
            endFocusWithoutVesting("Focus ended · Mac was asleep")
        }

        if isAway {
            runtime.awayStartUptime = input.uptime
        }
        runtime.lastUptime = input.uptime
        runtime.sleepStartContinuous = nil
        return update(input)
    }

    mutating func accrueFocus(_ input: UpdateInput) {
        let elapsed = runtime.lastUptime.map { max(0, input.uptime - $0) } ?? 0
        let lastInputUptime = input.uptime - input.idleSeconds

        defer {
            runtime.lastUptime = input.uptime
            runtime.blockedRunningAtLastUpdate = !input.runningAppIDs.isEmpty
        }

        if let awayStart = runtime.awayStartUptime {
            if !input.isLocked && lastInputUptime > awayStart + 1 {
                runtime.awayStartUptime = nil
                let gap = lastInputUptime - awayStart
                if gap >= Constants.minAwayGap {
                    updateToday { stats in
                        stats.unclaimedAwaySeconds += gap
                    }
                }
                runtime.unvestedSeconds = 0
                return
            }

            if state.focus != nil
                && input.uptime - awayStart >= Double(setting(.autoEndAwaySeconds))
            {
                let duration = DurationFormat.short(input.uptime - awayStart)
                endFocusWithoutVesting("Focus ended after \(duration) away")
            }
            return
        }

        guard state.focus != nil else {
            return
        }

        if !runtime.blockedRunningAtLastUpdate {
            runtime.unvestedSeconds += elapsed
        }

        if input.isLocked || input.idleSeconds >= Double(setting(.idleThresholdSeconds)) {
            runtime.awayStartUptime = lastInputUptime
            runtime.unvestedSeconds = 0
            return
        }

        let trailing = min(runtime.unvestedSeconds, input.idleSeconds)
        vest(runtime.unvestedSeconds - trailing)
        runtime.unvestedSeconds = trailing
    }

    mutating func endFocusWithoutVesting(_ historyText: String) {
        state.focus = nil
        record(.focusEnded, historyText)
    }
}
