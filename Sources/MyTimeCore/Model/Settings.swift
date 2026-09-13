import Foundation
public struct Settings: Codable, Equatable {
    public var numbers: [String: Int]
    public var apps: [BlockedApp]
    public init(numbers: [String: Int] = [:], apps: [BlockedApp] = []) {
        self.numbers = numbers
        self.apps = apps
    }
    public subscript(key: SettingKey) -> Int {
        get { numbers[key.rawValue] ?? key.defaultValue }
        set { numbers[key.rawValue] = key.clamp(newValue) }
    }
}
