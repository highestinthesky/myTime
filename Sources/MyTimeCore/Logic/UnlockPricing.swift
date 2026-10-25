import Foundation

public enum UnlockPricing {
    public static func multiplier(after previous: UnlockStreak?, at date: Date, dayKey: String) -> Int {
        guard let previous, previous.dayKey == dayKey,
            date.timeIntervalSince(previous.lastEnd) < Constants.unlockStreakGap
        else {
            return 1
        }
        return previous.lastMultiplier * 2
    }

    public static func quote(
        after previous: UnlockStreak?, at date: Date, dayKey: String, nextDayStart: Date
    ) -> UnlockQuote {
        let multiplier = multiplier(after: previous, at: date, dayKey: dayKey)
        let options = Constants.unlockLengthUnits.map {
            UnlockOption(units: $0, lengthSeconds: $0 * Constants.unlockSecondsPerUnit, cost: $0 * multiplier)
        }
        let resetsAt =
            multiplier > 1
            ? previous.map { min($0.lastEnd.addingTimeInterval(Constants.unlockStreakGap), nextDayStart) } : nil
        return UnlockQuote(multiplier: multiplier, options: options, resetsAt: resetsAt)
    }
}
