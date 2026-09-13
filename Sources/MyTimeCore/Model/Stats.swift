import Foundation
public struct DailyStats: Codable, Equatable {
    public var focusSeconds: Double
    public var tokensEarned: Int
    public var tokensSpent: Int
    public var backedOff: Int
    public var quickLooks: Int
    public var replies: Int
    public var claimedAwaySeconds: Double
    public var unclaimedAwaySeconds: Double
    public init(
        focusSeconds: Double = 0, tokensEarned: Int = 0, tokensSpent: Int = 0, backedOff: Int = 0, quickLooks: Int = 0,
        replies: Int = 0, claimedAwaySeconds: Double = 0, unclaimedAwaySeconds: Double = 0
    ) {
        self.focusSeconds = focusSeconds
        self.tokensEarned = tokensEarned
        self.tokensSpent = tokensSpent
        self.backedOff = backedOff
        self.quickLooks = quickLooks
        self.replies = replies
        self.claimedAwaySeconds = claimedAwaySeconds
        self.unclaimedAwaySeconds = unclaimedAwaySeconds
    }
}
public struct WeeklyStats: Codable, Equatable {
    public var emergencyUses: Int
    public var allowanceForfeited: Bool
    public init(emergencyUses: Int = 0, allowanceForfeited: Bool = false) {
        self.emergencyUses = emergencyUses
        self.allowanceForfeited = allowanceForfeited
    }
}
