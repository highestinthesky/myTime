import Foundation
public enum AccessMode: String, Codable, CaseIterable {
    case quickLook, reply, booked
    public var title: String {
        switch self {
        case .quickLook: return "Quick look"
        case .reply: return "Reply mode"
        case .booked: return "Sessions"
        }
    }
}
public struct BlockedApp: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    public var modes: Set<AccessMode>
    public init(id: UUID = UUID(), name: String, bundleIDs: [String], modes: Set<AccessMode>) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.modes = modes
    }
    public static func discord() -> BlockedApp {
        BlockedApp(
            name: "Discord", bundleIDs: ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"],
            modes: [.quickLook, .reply, .booked])
    }
}
