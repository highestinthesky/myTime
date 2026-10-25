import Foundation
public enum HistoryKind: String, Codable {
    // Only in files from 0.1.0.
    case quickLook, reply, extended
    case focusStarted, focusEnded, tokenEarned, dayReset, awayClaimed, backedOff,
        bookingCreated, bookingCanceled, bookingEnded, bookingExtended, emergency, changeScheduled, changeApplied,
        changeCanceled, appAdded, appRemoved, tamperDetected, quit, unlockBought, unlockEnded
}
public struct HistoryEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: HistoryKind
    public var text: String
    public init(id: UUID = UUID(), date: Date, kind: HistoryKind, text: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
    }
}
