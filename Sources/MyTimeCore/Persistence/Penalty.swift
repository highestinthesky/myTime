import Foundation
public extension PersistedState {
    static func penalized(now: Date, timeZone: TimeZone) -> PersistedState {
        var state = fresh(now: now, timeZone: timeZone)
        let day = CalendarKeys.dayKey(now, dayStartHour: state.settings[.dayStartHour], timeZone: timeZone)
        let week = CalendarKeys.weekKey(now, dayStartHour: state.settings[.dayStartHour], timeZone: timeZone)
        state.daily[day] = DailyStats(replies: 99, claimedAwaySeconds: 1_000_000)
        state.weekly[week] = WeeklyStats(emergencyUses: 99, allowanceForfeited: true)
        state.tamperNoticeUntil = now.addingTimeInterval(7 * 86_400)
        state.history.append(
            HistoryEvent(
                date: now, kind: .tamperDetected, text: "Saved data was edited outside myTime. Balances were reset."))
        return state
    }
}
