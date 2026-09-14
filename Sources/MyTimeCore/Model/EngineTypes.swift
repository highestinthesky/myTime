import Foundation
public struct EngineRuntime: Equatable {
    public var unvestedSeconds: Double
    public var lastUptime: Double?
    public var blockedRunningAtLastUpdate: Bool
    public var awayStartUptime: Double?
    public var lastActiveBookingID: UUID?
    public var sleepStartContinuous: Double?
    public init(
        unvestedSeconds: Double = 0, lastUptime: Double? = nil, blockedRunningAtLastUpdate: Bool = false,
        awayStartUptime: Double? = nil, lastActiveBookingID: UUID? = nil,
        sleepStartContinuous: Double? = nil
    ) {
        self.unvestedSeconds = unvestedSeconds
        self.lastUptime = lastUptime
        self.blockedRunningAtLastUpdate = blockedRunningAtLastUpdate
        self.awayStartUptime = awayStartUptime
        self.lastActiveBookingID = lastActiveBookingID
        self.sleepStartContinuous = sleepStartContinuous
    }
}
public struct UpdateInput {
    public var wall: Date
    public var continuous: Double
    public var uptime: Double
    public var bootSessionID: String
    public var idleSeconds: Double
    public var isLocked: Bool
    public var runningAppIDs: Set<UUID>
    public init(
        wall: Date, continuous: Double, uptime: Double, bootSessionID: String, idleSeconds: Double, isLocked: Bool,
        runningAppIDs: Set<UUID>
    ) {
        self.wall = wall
        self.continuous = continuous
        self.uptime = uptime
        self.bootSessionID = bootSessionID
        self.idleSeconds = idleSeconds
        self.isLocked = isLocked
        self.runningAppIDs = runningAppIDs
    }
}
public struct WakeUp: Equatable {
    public var date: Date
    public var critical: Bool
    public init(date: Date, critical: Bool) {
        self.date = date
        self.critical = critical
    }
}
public struct UpdateResult: Equatable {
    public var effects: [EngineEffect]
    public var nextWakeUp: WakeUp?
    public init(effects: [EngineEffect] = [], nextWakeUp: WakeUp? = nil) {
        self.effects = effects
        self.nextWakeUp = nextWakeUp
    }
}
public enum EngineEffect: Equatable {
    case terminateIfNotAllowed(appID: UUID), bookingHeadsUp(bookingID: UUID), uninstall
}
