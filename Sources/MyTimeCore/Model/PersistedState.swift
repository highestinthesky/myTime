import Foundation
public struct FocusSession: Codable, Equatable {
    public var startedAt: Date
    public var creditedSeconds: Double
    public init(startedAt: Date, creditedSeconds: Double = 0) {
        self.startedAt = startedAt
        self.creditedSeconds = creditedSeconds
    }
}
public struct PersistedState: Codable, Equatable {
    public var schemaVersion: Int
    public var settings: Settings
    public var pending: [PendingChange]
    public var tokens: Int
    public var progressSeconds: Double
    public var tokensDayKey: String
    public var focus: FocusSession?
    public var grants: [AccessGrant]
    public var bookings: [Booking]
    public var daily: [String: DailyStats]
    public var weekly: [String: WeeklyStats]
    public var history: [HistoryEvent]
    public var clock: TrustedClockState
    public var tamperNoticeUntil: Date?
    public init(
        schemaVersion: Int = Constants.schemaVersion, settings: Settings, pending: [PendingChange] = [],
        tokens: Int = 0, progressSeconds: Double = 0, tokensDayKey: String, focus: FocusSession? = nil,
        grants: [AccessGrant] = [], bookings: [Booking] = [], daily: [String: DailyStats] = [:],
        weekly: [String: WeeklyStats] = [:], history: [HistoryEvent] = [],
        clock: TrustedClockState = TrustedClockState(), tamperNoticeUntil: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.pending = pending
        self.tokens = tokens
        self.progressSeconds = progressSeconds
        self.tokensDayKey = tokensDayKey
        self.focus = focus
        self.grants = grants
        self.bookings = bookings
        self.daily = daily
        self.weekly = weekly
        self.history = history
        self.clock = clock
        self.tamperNoticeUntil = tamperNoticeUntil
    }
    public static func fresh(now: Date, timeZone: TimeZone) -> PersistedState {
        let settings = Settings(apps: [.discord()])
        return PersistedState(
            settings: settings,
            tokensDayKey: CalendarKeys.dayKey(
                now, dayStartHour: SettingKey.dayStartHour.defaultValue, timeZone: timeZone))
    }
}
