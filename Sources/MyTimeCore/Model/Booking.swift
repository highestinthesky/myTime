import Foundation
public struct Booking: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var durationSeconds: Int
    public var extensionSeconds: Int
    public var createdAt: Date
    public var canceledAt: Date?
    public var endedAt: Date?
    public var appOpened: Bool
    public var warned: Bool
    public init(
        id: UUID = UUID(), start: Date, durationSeconds: Int, extensionSeconds: Int = 0, createdAt: Date,
        canceledAt: Date? = nil, endedAt: Date? = nil, appOpened: Bool = false, warned: Bool = false
    ) {
        self.id = id
        self.start = start
        self.durationSeconds = durationSeconds
        self.extensionSeconds = extensionSeconds
        self.createdAt = createdAt
        self.canceledAt = canceledAt
        self.endedAt = endedAt
        self.appOpened = appOpened
        self.warned = warned
    }
    public var end: Date { start.addingTimeInterval(Double(durationSeconds + extensionSeconds)) }
    public func isUpcoming(at now: Date) -> Bool { canceledAt == nil && now < start }
    public func isActive(at now: Date) -> Bool { canceledAt == nil && endedAt == nil && start <= now && now < end }
    public func isFinished(at now: Date) -> Bool { canceledAt == nil && (endedAt != nil || now >= end) }
}
