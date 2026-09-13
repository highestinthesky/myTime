import Foundation
public enum HistoryKind: String, Codable {
    case focusStarted, focusEnded, tokenEarned, dayReset, awayClaimed, quickLook, reply, extended, backedOff,
        bookingCreated, bookingCanceled, bookingEnded, bookingExtended, emergency, changeScheduled, changeApplied,
        changeCanceled, appAdded, appRemoved, tamperDetected
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
