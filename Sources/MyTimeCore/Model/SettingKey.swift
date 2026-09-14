import Foundation

public enum SettingUnit: String, Codable { case seconds, count, hourOfDay }
public enum LooserWhen: String, Codable { case higher, lower, anyChange }
public enum SettingGroup: String, Codable, CaseIterable {
    case earning = "Earning", spending = "Spending", sessions = "Sessions", emergency = "Emergency", safety = "Safety"
}

public enum SettingKey: String, Codable, CaseIterable {
    case focusSecondsPerToken, dayStartHour, idleThresholdSeconds, awayClaimSecondsPerDay, autoEndAwaySeconds
    case quickLookSecondsPerToken, quickLookMaxTokens, replyTokenCost, replySeconds, replyPerDay, gatePauseSeconds
    case weeklyAllowanceSeconds, bookingLeadSeconds, bookingMaxSeconds, bookingExtensionSeconds
    case emergencyPerWeek, emergencyWaitSeconds, emergencyAccessSeconds, looseningDelaySeconds

    private struct Row {
        let title: String
        let group: SettingGroup
        let unit: SettingUnit
        let release: Int
        let dev: Int
        let range: ClosedRange<Int>
        let looser: LooserWhen
    }

    private var row: Row {
        switch self {
        case .focusSecondsPerToken:
            return Row(
                title: "Focus per token", group: .earning, unit: .seconds, release: 900, dev: 15, range: 300...3600,
                looser: .lower)
        case .dayStartHour:
            return Row(
                title: "Day starts at", group: .earning, unit: .hourOfDay, release: 4, dev: 4, range: 0...23,
                looser: .anyChange)
        case .idleThresholdSeconds:
            return Row(
                title: "Pause after no activity", group: .earning, unit: .seconds, release: 300, dev: 20,
                range: 60...1800, looser: .higher)
        case .awayClaimSecondsPerDay:
            return Row(
                title: "Away time you can count per day", group: .earning, unit: .seconds, release: 1800, dev: 60,
                range: 0...7200, looser: .higher)
        case .autoEndAwaySeconds:
            return Row(
                title: "End focus after away for", group: .earning, unit: .seconds, release: 1800, dev: 60,
                range: 600...7200, looser: .higher)
        case .quickLookSecondsPerToken:
            return Row(
                title: "Quick look per token", group: .spending, unit: .seconds, release: 30, dev: 30, range: 10...300,
                looser: .higher)
        case .quickLookMaxTokens:
            return Row(
                title: "Max tokens per quick look", group: .spending, unit: .count, release: 3, dev: 3, range: 1...10,
                looser: .higher)
        case .replyTokenCost:
            return Row(
                title: "Reply mode cost", group: .spending, unit: .count, release: 2, dev: 2, range: 1...10,
                looser: .lower)
        case .replySeconds:
            return Row(
                title: "Reply mode length", group: .spending, unit: .seconds, release: 180, dev: 60, range: 60...900,
                looser: .higher)
        case .replyPerDay:
            return Row(
                title: "Reply mode uses per day", group: .spending, unit: .count, release: 3, dev: 3, range: 0...10,
                looser: .higher)
        case .gatePauseSeconds:
            return Row(
                title: "Gate pause", group: .spending, unit: .seconds, release: 5, dev: 5, range: 0...30,
                looser: .lower)
        case .weeklyAllowanceSeconds:
            return Row(
                title: "Session time per week", group: .sessions, unit: .seconds, release: 18000, dev: 1200,
                range: 0...72000, looser: .higher)
        case .bookingLeadSeconds:
            return Row(
                title: "Book at least this far ahead", group: .sessions, unit: .seconds, release: 600, dev: 60,
                range: 0...86400, looser: .lower)
        case .bookingMaxSeconds:
            return Row(
                title: "Longest session", group: .sessions, unit: .seconds, release: 10800, dev: 600,
                range: 1800...28800, looser: .higher)
        case .bookingExtensionSeconds:
            return Row(
                title: "Session extension", group: .sessions, unit: .seconds, release: 900, dev: 60, range: 0...3600,
                looser: .higher)
        case .emergencyPerWeek:
            return Row(
                title: "Emergency passes per week", group: .emergency, unit: .count, release: 1, dev: 1, range: 0...3,
                looser: .higher)
        case .emergencyWaitSeconds:
            return Row(
                title: "Emergency wait", group: .emergency, unit: .seconds, release: 60, dev: 10, range: 10...600,
                looser: .lower)
        case .emergencyAccessSeconds:
            return Row(
                title: "Emergency access length", group: .emergency, unit: .seconds, release: 600, dev: 60,
                range: 60...3600, looser: .higher)
        case .looseningDelaySeconds:
            return Row(
                title: "Delay for loosening changes", group: .safety, unit: .seconds, release: 86400, dev: 60,
                range: 3600...604800, looser: .lower)
        }
    }

    public var title: String { row.title }
    public var group: SettingGroup { row.group }
    public var unit: SettingUnit { row.unit }
    public var defaultValue: Int { Constants.isDev ? row.dev : row.release }
    public var range: ClosedRange<Int> {
        #if DEV_TIMESCALE
            return self == .dayStartHour ? row.range : min(row.range.lowerBound, 1)...row.range.upperBound
        #else
            return row.range
        #endif
    }
    public var looserWhen: LooserWhen { row.looser }
    public func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }
}
