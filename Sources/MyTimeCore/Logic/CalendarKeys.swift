import Foundation

public enum CalendarKeys {
    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
    private static func shifted(_ date: Date, hour: Int, timeZone: TimeZone) -> Date {
        calendar(timeZone).date(byAdding: .hour, value: -hour, to: date)!
    }
    public static func dayKey(_ date: Date, dayStartHour: Int, timeZone: TimeZone) -> String {
        let c = calendar(timeZone)
        let components = c.dateComponents(
            [.year, .month, .day], from: shifted(date, hour: dayStartHour, timeZone: timeZone))
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    public static func weekKey(_ date: Date, dayStartHour: Int, timeZone: TimeZone) -> String {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = timeZone
        let parts = c.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: shifted(date, hour: dayStartHour, timeZone: timeZone))
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear!, parts.weekOfYear!)
    }
    public static func nextDayStart(after date: Date, dayStartHour: Int, timeZone: TimeZone) -> Date {
        calendar(timeZone).nextDate(
            after: date, matching: DateComponents(hour: dayStartHour, minute: 0, second: 0), matchingPolicy: .nextTime)!
    }
    public static func nextWeekStart(after date: Date, dayStartHour: Int, timeZone: TimeZone) -> Date {
        calendar(timeZone).nextDate(
            after: date, matching: DateComponents(hour: dayStartHour, minute: 0, second: 0, weekday: 2),
            matchingPolicy: .nextTime)!
    }
}
