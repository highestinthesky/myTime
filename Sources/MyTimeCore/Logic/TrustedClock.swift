import Foundation

public struct TrustedClockState: Codable, Equatable {
    public var offsetSeconds: Double
    public var lastWall: Double
    public var lastContinuous: Double
    public var bootSessionID: String
    public init(offsetSeconds: Double = 0, lastWall: Double = 0, lastContinuous: Double = 0, bootSessionID: String = "")
    {
        self.offsetSeconds = offsetSeconds
        self.lastWall = lastWall
        self.lastContinuous = lastContinuous
        self.bootSessionID = bootSessionID
    }
}

public enum TrustedClock {
    public static func update(_ state: inout TrustedClockState, wall: Double, continuous: Double, bootSessionID: String)
        -> Double
    {
        if state.bootSessionID == bootSessionID && state.lastWall > 0 {
            let drift = (wall - state.lastWall) - (continuous - state.lastContinuous)
            if abs(drift) > Constants.clockJumpTolerance { state.offsetSeconds -= drift }
        }
        state.lastWall = wall
        state.lastContinuous = continuous
        state.bootSessionID = bootSessionID
        return wall + state.offsetSeconds
    }
}
