import Foundation
public enum WakeUpPlanner {
    public static func next(state: PersistedState, runtime: EngineRuntime, now: Date, nextDayStart: Date) -> WakeUp? {
        var candidates: [(Date, Bool)] = [(nextDayStart, false)]
        candidates += state.grants.map { ($0.expiresAt, true) }
        for booking in state.bookings where booking.isActive(at: now) {
            candidates.append((booking.end, true))
            if !booking.warned { candidates.append((booking.end.addingTimeInterval(-Constants.bookingHeadsUp), false)) }
        }
        candidates += state.pending.map { ($0.applyAt, false) }
        if state.focus != nil || runtime.awayStartUptime != nil {
            candidates.append((now.addingTimeInterval(Constants.focusCheckInterval), false))
        }
        return candidates.filter { $0.0 > now }.map { WakeUp(date: $0.0, critical: $0.1) }.sorted {
            $0.date == $1.date ? ($0.critical && !$1.critical) : $0.date < $1.date
        }.first
    }
}
