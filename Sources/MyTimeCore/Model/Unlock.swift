import Foundation

public struct ActiveUnlock: Codable, Equatable {
    public var appID: UUID
    public var startedAt: Date
    public var endsAt: Date
    public var lengthSeconds: Int
    public var multiplier: Int
    public var cost: Int
    public var dayKey: String
    public var warned: Bool
    public var endedAt: Date?

    public init(
        appID: UUID, startedAt: Date, endsAt: Date, lengthSeconds: Int, multiplier: Int,
        cost: Int, dayKey: String, warned: Bool = false, endedAt: Date? = nil
    ) {
        self.appID = appID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.lengthSeconds = lengthSeconds
        self.multiplier = multiplier
        self.cost = cost
        self.dayKey = dayKey
        self.warned = warned
        self.endedAt = endedAt
    }

    public func isActive(at now: Date) -> Bool {
        endedAt == nil && now < endsAt
    }

    public var warningAt: Date {
        endsAt.addingTimeInterval(-min(Constants.unlockWarningLead, Double(lengthSeconds) / 2))
    }
}

public struct UnlockStreak: Codable, Equatable {
    public var lastMultiplier: Int
    public var lastEnd: Date
    public var dayKey: String

    public init(lastMultiplier: Int, lastEnd: Date, dayKey: String) {
        self.lastMultiplier = lastMultiplier
        self.lastEnd = lastEnd
        self.dayKey = dayKey
    }
}

public struct UnlockOption: Equatable {
    public var units: Int
    public var lengthSeconds: Int
    public var cost: Int

    public init(units: Int, lengthSeconds: Int, cost: Int) {
        self.units = units
        self.lengthSeconds = lengthSeconds
        self.cost = cost
    }
}

public struct UnlockQuote: Equatable {
    public var multiplier: Int
    public var options: [UnlockOption]
    public var resetsAt: Date?

    public init(multiplier: Int, options: [UnlockOption], resetsAt: Date?) {
        self.multiplier = multiplier
        self.options = options
        self.resetsAt = resetsAt
    }
}
