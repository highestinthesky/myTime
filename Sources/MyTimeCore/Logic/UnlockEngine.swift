import Foundation

extension EngineCore {
    public var activeUnlock: ActiveUnlock? {
        guard let unlock = state.unlock, unlock.isActive(at: now) else { return nil }
        return unlock
    }

    public func remaining(of unlock: ActiveUnlock) -> Double {
        max(0, unlock.endsAt.timeIntervalSince(now))
    }

    public func unlockQuote(at date: Date) -> UnlockQuote {
        let previous =
            state.unlock.map {
                UnlockStreak(lastMultiplier: $0.multiplier, lastEnd: $0.endedAt ?? $0.endsAt, dayKey: $0.dayKey)
            } ?? state.unlockStreak
        return UnlockPricing.quote(
            after: previous, at: date,
            dayKey: CalendarKeys.dayKey(date, dayStartHour: dayStartHour, timeZone: timeZone),
            nextDayStart: CalendarKeys.nextDayStart(after: date, dayStartHour: dayStartHour, timeZone: timeZone))
    }

    public func gatePauseSeconds(appID: UUID, at date: Date) -> Int {
        let pause = setting(.gatePauseSeconds)
        guard app(id: appID)?.modes.contains(.unlock) == true else { return pause }
        return max(pause, min(Constants.gatePauseCap, pause * unlockQuote(at: date).multiplier))
    }

    public mutating func buyUnlock(appID: UUID, lengthSeconds: Int, expectedCost: Int) throws -> ActiveUnlock {
        guard let app = app(id: appID) else { throw EngineError.unknownApp }
        guard app.modes.contains(.unlock) else { throw EngineError.modeNotAllowed }
        guard state.focus == nil else { throw EngineError.focusActive }
        guard state.unlock == nil else { throw EngineError.unlockActive }
        let quote = unlockQuote(at: now)
        guard let option = quote.options.first(where: { $0.lengthSeconds == lengthSeconds }) else {
            throw EngineError.invalidLength
        }
        guard option.cost == expectedCost else { throw EngineError.priceChanged }
        guard state.tokens >= option.cost else { throw EngineError.notEnoughTokens }

        state.tokens -= option.cost
        updateToday {
            $0.tokensSpent += option.cost
            $0.unlocks += 1
            $0.unlockTokens += option.cost
            $0.highestMultiplier = max($0.highestMultiplier, quote.multiplier)
        }
        let weekKey = CalendarKeys.weekKey(now, dayStartHour: dayStartHour, timeZone: timeZone)
        var weekly = state.weekly[weekKey] ?? WeeklyStats()
        weekly.unlocks += 1
        weekly.unlockTokens += option.cost
        weekly.highestMultiplier = max(weekly.highestMultiplier, quote.multiplier)
        state.weekly[weekKey] = weekly

        let unlock = ActiveUnlock(
            appID: appID, startedAt: now, endsAt: now.addingTimeInterval(Double(lengthSeconds)),
            lengthSeconds: lengthSeconds, multiplier: quote.multiplier, cost: option.cost,
            dayKey: CalendarKeys.dayKey(now, dayStartHour: dayStartHour, timeZone: timeZone))
        state.unlock = unlock
        var text =
            "Unlock in \(app.name) · \(DurationFormat.short(Double(lengthSeconds))) · \(quote.multiplier)× · \(option.cost) ◆"
        if let previous = state.unlockStreak, previous.dayKey == unlock.dayKey {
            text += " · \(DurationFormat.short(now.timeIntervalSince(previous.lastEnd))) after the last"
        }
        record(.unlockBought, text)
        return unlock
    }

    public mutating func endUnlock() {
        guard activeUnlock != nil else { return }
        let end = now
        state.unlock?.endedAt = end
    }

    mutating func finishUnlockIfDue() -> [EngineEffect] {
        guard let unlock = state.unlock, unlock.endedAt != nil || now >= unlock.endsAt else { return [] }
        let end = min(unlock.endedAt ?? unlock.endsAt, unlock.endsAt)
        state.unlockStreak = UnlockStreak(
            lastMultiplier: unlock.multiplier, lastEnd: end, dayKey: unlock.dayKey)
        let used = end.timeIntervalSince(unlock.startedAt)
        var daily = state.daily[unlock.dayKey] ?? DailyStats()
        daily.unlockSeconds += used
        state.daily[unlock.dayKey] = daily
        let weekKey = CalendarKeys.weekKey(unlock.startedAt, dayStartHour: dayStartHour, timeZone: timeZone)
        var weekly = state.weekly[weekKey] ?? WeeklyStats()
        weekly.unlockSeconds += used
        state.weekly[weekKey] = weekly
        let early = unlock.endedAt.map { $0 < unlock.endsAt } ?? false
        record(.unlockEnded, "Unlock ended\(early ? " early" : "") · \(DurationFormat.short(used)) used")
        state.unlock = nil
        return state.settings.apps.filter { $0.modes.contains(.unlock) }.map {
            .terminateIfNotAllowed(appID: $0.id)
        } + [.unlockEnded]
    }

    mutating func unlockWarningIfDue(_ input: UpdateInput) -> [EngineEffect] {
        guard let unlock = activeUnlock, !unlock.warned, now >= unlock.warningAt else { return [] }
        if remaining(of: unlock) < Constants.unlockWarningMinimum {
            state.unlock?.warned = true
            return []
        }
        let hasClosingApp = state.settings.apps.contains { app in
            guard input.runningAppIDs.contains(app.id), app.modes.contains(.unlock) else { return false }
            let keptOpen =
                app.modes.contains(.booked)
                && state.bookings.contains {
                    $0.canceledAt == nil && $0.endedAt == nil && $0.start <= unlock.endsAt && unlock.endsAt < $0.end
                }
            return !keptOpen
        }
        guard hasClosingApp else { return [] }
        state.unlock?.warned = true
        return [.unlockWarning]
    }
}
