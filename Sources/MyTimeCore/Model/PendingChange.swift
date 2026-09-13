import Foundation
public indirect enum SettingChange: Codable, Equatable {
    case setNumber(key: SettingKey, value: Int), addApp(BlockedApp), removeApp(id: UUID), setMode(
        appID: UUID, mode: AccessMode, enabled: Bool), uninstall
    public var fieldKey: String {
        switch self {
        case let .setNumber(key, _): return "number:\(key.rawValue)"
        case let .addApp(app): return "app:\(app.id.uuidString.lowercased())"
        case let .removeApp(id): return "app:\(id.uuidString.lowercased())"
        case let .setMode(id, mode, _): return "mode:\(id.uuidString.lowercased()):\(mode.rawValue)"
        case .uninstall: return "uninstall"
        }
    }
}
public struct PendingChange: Codable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var applyAt: Date
    public var change: SettingChange
    public var summary: String
    public init(id: UUID = UUID(), createdAt: Date, applyAt: Date, change: SettingChange, summary: String) {
        self.id = id
        self.createdAt = createdAt
        self.applyAt = applyAt
        self.change = change
        self.summary = summary
    }
}
public enum SubmitResult: Equatable { case applied, scheduled(applyAt: Date), noChange }
