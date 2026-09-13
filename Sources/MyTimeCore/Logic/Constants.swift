import Foundation

public enum Constants {
    public static let schemaVersion: Int = 1
    #if DEV_TIMESCALE
        public static let isDev = true
        public static let launchGrace: TimeInterval = 15
        public static let extendWindow: TimeInterval = 10
        public static let focusCheckInterval: TimeInterval = 5
        public static let bookingHeadsUp: TimeInterval = 30
        public static let bookingMinSeconds = 60
        public static let bookingStartStepSeconds = 60
        public static let bookingDurationStepSeconds = 60
        public static let bookingHorizonSeconds = 604_800
        public static let gateTimeout: TimeInterval = 60
        public static let forceQuitAfter: TimeInterval = 5
        public static let holdToConfirm: TimeInterval = 2
        public static let headsUpVisible: TimeInterval = 8
        public static let minAwayGap: TimeInterval = 10
        public static let minClaimable: TimeInterval = 5
    #else
        public static let isDev = false
        public static let launchGrace: TimeInterval = 15
        public static let extendWindow: TimeInterval = 10
        public static let focusCheckInterval: TimeInterval = 30
        public static let bookingHeadsUp: TimeInterval = 300
        public static let bookingMinSeconds = 1800
        public static let bookingStartStepSeconds = 300
        public static let bookingDurationStepSeconds = 900
        public static let bookingHorizonSeconds = 604_800
        public static let gateTimeout: TimeInterval = 60
        public static let forceQuitAfter: TimeInterval = 5
        public static let holdToConfirm: TimeInterval = 2
        public static let headsUpVisible: TimeInterval = 8
        public static let minAwayGap: TimeInterval = 120
        public static let minClaimable: TimeInterval = 60
    #endif
    public static let clockJumpTolerance: TimeInterval = 120
    public static let criticalWakeTolerance: TimeInterval = 1
    public static let normalWakeTolerance: TimeInterval = 5
    public static let minReplyNote = 8
    public static let minEmergencyReason = 15
    public static let historyCap = 500
    public static let dailyRetentionDays = 60
    public static let bookingRetentionDays = 14
}
