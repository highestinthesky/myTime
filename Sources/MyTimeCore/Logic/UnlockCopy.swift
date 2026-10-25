import Foundation

public enum UnlockCopy {
    public static func streakLine(multiplier: Int, resetsAt: Date, timeZone: TimeZone, locale: Locale) -> String {
        "\(multiplier)× — resets at \(DurationFormat.timeOfDay(resetsAt, timeZone: timeZone, locale: locale))"
    }

    public static func nextUnlockLine(multiplier: Int, resetsAt: Date, timeZone: TimeZone, locale: Locale) -> String {
        "Next Unlock: \(multiplier)× until \(DurationFormat.timeOfDay(resetsAt, timeZone: timeZone, locale: locale))"
    }

    public static func unlockButton(lengthSeconds: Int, cost: Int) -> String {
        "Unlock \(DurationFormat.short(Double(lengthSeconds))) · \(cost) token\(cost == 1 ? "" : "s")"
    }

    public static func needsMore(_ tokens: Int) -> String {
        "Needs \(tokens) more"
    }

    public static func shortOfTokens(needed: Int, lengthSeconds: Int) -> String {
        "Unlock needs \(needed) more token\(needed == 1 ? "" : "s") for \(DurationFormat.short(Double(lengthSeconds)))."
    }

    public static func closesIn(appNames: [String], remaining: Double) -> String {
        let subject = appNames.count == 1 ? "\(appNames[0]) closes" : "Unlocked apps close"
        return "\(subject) in \(DurationFormat.clock(remaining))"
    }

    public static func menuBarRemaining(_ seconds: Double) -> String {
        let unit = Double(Constants.unlockSecondsPerUnit)
        return DurationFormat.short(max(1, ceil(seconds / unit)) * unit)
    }
}
