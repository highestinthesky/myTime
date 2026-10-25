import Foundation
public enum EngineError: Error, Equatable {
    case unknownApp, unknownGrant, modeNotAllowed, focusActive, notEnoughTokens,
        reasonTooShort, emergencyUnavailable, bookingTooSoon(leadSeconds: Int),
        bookingTooFar, invalidDuration(minSeconds: Int, maxSeconds: Int), bookingOverlap, allowanceExceeded,
        cannotCancel, cannotExtendBooking, unlockActive, invalidLength, priceChanged
    public var userMessage: String {
        switch self {
        case .unknownApp: return "That app isn't blocked anymore."
        case .unknownGrant: return "That access has already ended."
        case .modeNotAllowed: return "That option is turned off for this app."
        case .focusActive: return "End your focus session first."
        case .unlockActive: return "An Unlock is already running."
        case .invalidLength: return "Choose one of the listed lengths."
        case .priceChanged: return "The price changed. Choose again."
        case .notEnoughTokens: return "Not enough tokens."
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
