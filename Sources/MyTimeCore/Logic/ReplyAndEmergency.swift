import Foundation

extension EngineCore {
    public func replyUnavailableReason(appID: UUID, note: String) -> EngineError? {
        guard let app = app(id: appID) else {
            return .unknownApp
        }
        guard app.modes.contains(.reply) else {
            return .modeNotAllowed
        }
        guard state.focus == nil else {
            return .focusActive
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Constants.minReplyNote else {
            return .noteTooShort
        }
        guard state.tokens >= setting(.replyTokenCost) else {
            return .notEnoughTokens
        }
        guard today.replies < setting(.replyPerDay) else {
            return .replyLimitReached
        }
        return nil
    }

    public mutating func buyReply(appID: UUID, note: String) throws -> AccessGrant {
        if let error = replyUnavailableReason(appID: appID, note: note) {
            throw error
        }
        guard let app = app(id: appID) else {
            throw EngineError.unknownApp
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cost = setting(.replyTokenCost)
        state.tokens -= cost
        updateToday { stats in
            stats.tokensSpent += cost
            stats.replies += 1
        }
        let grant = AccessGrant(
            appID: appID,
            kind: .reply,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Double(setting(.replySeconds))),
            tokensSpent: cost,
            note: trimmed
        )
        state.grants.append(grant)
        record(.reply, "Reply mode in \(app.name) — “\(trimmed)”")
        return grant
    }

    public var emergencyUsesLeftThisWeek: Int {
        let key = CalendarKeys.weekKey(now, dayStartHour: dayStartHour, timeZone: timeZone)
        let uses = state.weekly[key]?.emergencyUses ?? 0
        return max(0, setting(.emergencyPerWeek) - uses)
    }

    public mutating func useEmergency(appID: UUID, reason: String) throws -> AccessGrant {
        guard let app = app(id: appID) else {
            throw EngineError.unknownApp
        }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Constants.minEmergencyReason else {
            throw EngineError.reasonTooShort
        }
        guard emergencyUsesLeftThisWeek > 0 else {
            throw EngineError.emergencyUnavailable
        }

        let key = CalendarKeys.weekKey(now, dayStartHour: dayStartHour, timeZone: timeZone)
        var stats = state.weekly[key] ?? WeeklyStats()
        stats.emergencyUses += 1
        state.weekly[key] = stats
        if state.focus != nil {
            endFocus()
        }

        let grant = AccessGrant(
            appID: appID,
            kind: .emergency,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Double(setting(.emergencyAccessSeconds))),
            tokensSpent: 0,
            note: trimmed
        )
        state.grants.append(grant)
        record(.emergency, "Emergency access to \(app.name) — “\(trimmed)”")
        return grant
    }
}
