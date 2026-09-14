import Foundation

extension EngineCore {
    mutating func prune() {
        let currentNow = now
        let dailyCutoff = CalendarKeys.dayKey(
            currentNow.addingTimeInterval(-Double(Constants.dailyRetentionDays) * 86_400),
            dayStartHour: dayStartHour,
            timeZone: timeZone
        )
        state.daily = state.daily.filter { key, _ in
            key >= dailyCutoff
        }

        let weeklyCutoff = CalendarKeys.weekKey(
            currentNow.addingTimeInterval(-Double(Constants.weeklyRetentionWeeks * 7) * 86_400),
            dayStartHour: dayStartHour,
            timeZone: timeZone
        )
        state.weekly = state.weekly.filter { key, _ in
            key >= weeklyCutoff
        }

        let bookingCutoff = currentNow.addingTimeInterval(-Double(Constants.bookingRetentionDays) * 86_400)
        state.bookings.removeAll { booking in
            if let canceledAt = booking.canceledAt {
                return canceledAt < bookingCutoff
            }
            if booking.isFinished(at: currentNow) {
                return (booking.endedAt ?? booking.end) < bookingCutoff
            }
            return false
        }

        if state.history.count > Constants.historyCap {
            state.history.removeFirst(state.history.count - Constants.historyCap)
        }
    }
}
