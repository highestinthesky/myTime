import Foundation

public struct DailyStats: Codable, Equatable {
    public var focusSeconds: Double
    public var tokensEarned: Int
    public var tokensSpent: Int
    public var backedOff: Int
    public var claimedAwaySeconds: Double
    public var unclaimedAwaySeconds: Double
    public var unlocks: Int
    public var unlockSeconds: Double
    public var unlockTokens: Int
    public var highestMultiplier: Int

    public init(
        focusSeconds: Double = 0, tokensEarned: Int = 0, tokensSpent: Int = 0, backedOff: Int = 0,
        claimedAwaySeconds: Double = 0, unclaimedAwaySeconds: Double = 0, unlocks: Int = 0,
        unlockSeconds: Double = 0, unlockTokens: Int = 0, highestMultiplier: Int = 0
    ) {
        self.focusSeconds = focusSeconds
        self.tokensEarned = tokensEarned
        self.tokensSpent = tokensSpent
        self.backedOff = backedOff
        self.claimedAwaySeconds = claimedAwaySeconds
        self.unclaimedAwaySeconds = unclaimedAwaySeconds
        self.unlocks = unlocks
        self.unlockSeconds = unlockSeconds
        self.unlockTokens = unlockTokens
        self.highestMultiplier = highestMultiplier
    }

    private enum CodingKeys: String, CodingKey {
        case focusSeconds
        case tokensEarned
        case tokensSpent
        case backedOff
        case claimedAwaySeconds
        case unclaimedAwaySeconds
        case unlocks
        case unlockSeconds
        case unlockTokens
        case highestMultiplier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusSeconds = try values.decodeIfPresent(Double.self, forKey: .focusSeconds) ?? 0
        tokensEarned = try values.decodeIfPresent(Int.self, forKey: .tokensEarned) ?? 0
        tokensSpent = try values.decodeIfPresent(Int.self, forKey: .tokensSpent) ?? 0
        backedOff = try values.decodeIfPresent(Int.self, forKey: .backedOff) ?? 0
        claimedAwaySeconds = try values.decodeIfPresent(Double.self, forKey: .claimedAwaySeconds) ?? 0
        unclaimedAwaySeconds = try values.decodeIfPresent(Double.self, forKey: .unclaimedAwaySeconds) ?? 0
        unlocks = try values.decodeIfPresent(Int.self, forKey: .unlocks) ?? 0
        unlockSeconds = try values.decodeIfPresent(Double.self, forKey: .unlockSeconds) ?? 0
        unlockTokens = try values.decodeIfPresent(Int.self, forKey: .unlockTokens) ?? 0
        highestMultiplier = try values.decodeIfPresent(Int.self, forKey: .highestMultiplier) ?? 0
    }
}

public struct WeeklyStats: Codable, Equatable {
    public var emergencyUses: Int
    public var allowanceForfeited: Bool
    public var unlocks: Int
    public var unlockSeconds: Double
    public var unlockTokens: Int
    public var highestMultiplier: Int

    public init(
        emergencyUses: Int = 0, allowanceForfeited: Bool = false, unlocks: Int = 0, unlockSeconds: Double = 0,
        unlockTokens: Int = 0, highestMultiplier: Int = 0
    ) {
        self.emergencyUses = emergencyUses
        self.allowanceForfeited = allowanceForfeited
        self.unlocks = unlocks
        self.unlockSeconds = unlockSeconds
        self.unlockTokens = unlockTokens
        self.highestMultiplier = highestMultiplier
    }

    private enum CodingKeys: String, CodingKey {
        case emergencyUses
        case allowanceForfeited
        case unlocks
        case unlockSeconds
        case unlockTokens
        case highestMultiplier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        emergencyUses = try values.decodeIfPresent(Int.self, forKey: .emergencyUses) ?? 0
        allowanceForfeited = try values.decodeIfPresent(Bool.self, forKey: .allowanceForfeited) ?? false
        unlocks = try values.decodeIfPresent(Int.self, forKey: .unlocks) ?? 0
        unlockSeconds = try values.decodeIfPresent(Double.self, forKey: .unlockSeconds) ?? 0
        unlockTokens = try values.decodeIfPresent(Int.self, forKey: .unlockTokens) ?? 0
        highestMultiplier = try values.decodeIfPresent(Int.self, forKey: .highestMultiplier) ?? 0
    }
}
