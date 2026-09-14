import Foundation
public enum GrantKind: String, Codable { case quickLook, reply, emergency }
public struct AccessGrant: Codable, Equatable, Identifiable {
    public var id: UUID
    public var appID: UUID
    public var kind: GrantKind
    public var createdAt: Date
    public var expiresAt: Date
    public var tokensSpent: Int
    public var note: String?
    public init(
        id: UUID = UUID(), appID: UUID, kind: GrantKind, createdAt: Date, expiresAt: Date,
        tokensSpent: Int = 0, note: String? = nil
    ) {
        self.id = id
        self.appID = appID
        self.kind = kind
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.tokensSpent = tokensSpent
        self.note = note
    }
}
