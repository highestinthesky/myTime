import Foundation

/// The unit a duration setting is typed in (spec §7.9). The value stored is always whole seconds.
public enum DurationUnit: String, CaseIterable, Identifiable {
    case seconds
    case minutes
    case hours

    public var id: String { rawValue }

    public var seconds: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        }
    }

    public var title: String { rawValue }

    /// The largest unit that shows the value as a whole number. Zero reads as minutes.
    public static func natural(for seconds: Int) -> DurationUnit {
        if seconds > 0 && seconds % 3600 == 0 {
            return .hours
        }
        if seconds % 60 == 0 {
            return .minutes
        }
        return .seconds
    }
}

extension SettingKey {
    /// Shown under a typed value outside the key's range, e.g. "Choose between 5 min and 1h."
    public func rangeMessage(locale: Locale) -> String {
        let lower = DurationFormat.setting(self, range.lowerBound, locale: locale)
        let upper = DurationFormat.setting(self, range.upperBound, locale: locale)
        return "Choose between \(lower) and \(upper)."
    }
}
