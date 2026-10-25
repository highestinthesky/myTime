import Foundation

extension EngineCore {
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
