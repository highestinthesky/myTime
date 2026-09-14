import Foundation

public enum DurationFormat {
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total < 3600 { return "\(total / 60):\(String(format: "%02d", total % 60))" }
        return "\(total / 3600):\(String(format: "%02d", (total % 3600) / 60)):\(String(format: "%02d", total % 60))"
    }
    public static func short(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        let minutes = Int((Double(total) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }
    public static func hourOfDay(_ hour: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour))!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(
            of: "\u{00A0}", with: " ")
    }
    public static func timeOfDay(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
    public static func dayLabel(
        _ date: Date,
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: target).day
        if offset == 0 {
            return "Today"
        }
        if offset == 1 {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
    public static func sessionStart(
        _ date: Date,
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let day = dayLabel(date, now: now, timeZone: timeZone, locale: locale)
        return "\(day) \(timeOfDay(date, timeZone: timeZone, locale: locale))"
    }
    public static func historyDay(
        _ date: Date,
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: target).day
        if offset == 0 {
            return "Today"
        }
        if offset == -1 {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date)
    }
    public static func setting(_ key: SettingKey, _ value: Int, locale: Locale) -> String {
        switch key.unit {
        case .seconds: return short(Double(value))
        case .count: return "\(value)"
        case .hourOfDay: return hourOfDay(value, locale: locale)
        }
    }
}
