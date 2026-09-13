import Foundation
public enum EngineError: Error, Equatable {
    case unknownApp, unknownGrant, modeNotAllowed, focusActive, invalidAmount(max: Int), notEnoughTokens, noteTooShort,
        replyLimitReached, cannotExtend, reasonTooShort, emergencyUnavailable, bookingTooSoon(leadSeconds: Int),
        bookingTooFar, invalidDuration(minSeconds: Int, maxSeconds: Int), bookingOverlap, allowanceExceeded,
        cannotCancel, cannotExtendBooking
    public var userMessage: String {
        switch self {
        case .unknownApp: return "That app isn't blocked anymore."
        case .unknownGrant: return "That access has already ended."
        case .modeNotAllowed: return "That option is turned off for this app."
        case .focusActive: return "End your focus session first."
        case let .invalidAmount(max): return "Choose between 1 and \(max) tokens."
        case .notEnoughTokens: return "Not enough tokens."
        case .noteTooShort: return "Write at least 8 characters."
        case .replyLimitReached: return "No replies left today."
        case .cannotExtend: return "Can't extend right now."
        case .reasonTooShort: return "Write at least 15 characters."
        case .emergencyUnavailable: return "Emergency access used · resets Monday."
        case let .bookingTooSoon(lead): return "Book at least \(DurationFormat.short(Double(lead))) ahead."
        case .bookingTooFar: return "Book up to 7 days ahead."
        case let .invalidDuration(minimum, maximum):
            return
                "Choose a length between \(DurationFormat.short(Double(minimum))) and \(DurationFormat.short(Double(maximum)))."
        case .bookingOverlap: return "That overlaps another session."
        case .allowanceExceeded: return "Not enough session time left that week."
        case .cannotCancel: return "That session has already started."
        case .cannotExtendBooking: return "Can't extend this session."
        }
    }
}
