import Foundation

public enum SettingsPolicy {
    public static func isLoosening(_ change: SettingChange, settings: Settings) -> Bool {
        switch change {
        case let .setNumber(key, value):
            let value = key.clamp(value)
            switch key.looserWhen {
            case .higher:
                return value > settings[key]
            case .lower:
                return value < settings[key]
            case .anyChange:
                return value != settings[key]
            }
        case .addApp:
            return false
        case .removeApp:
            return true
        case let .setMode(appID, mode, enabled):
            guard let app = settings.apps.first(where: { $0.id == appID }) else {
                return false
            }
            return enabled && !app.modes.contains(mode)
        case .uninstall:
            return true
        }
    }

    public static func addAppProblem(
        bundleID: String?,
        path: String,
        ownBundleID: String?,
        apps: [BlockedApp]
    ) -> String? {
        guard let bundleID, !bundleID.isEmpty else {
            return "That app can't be blocked."
        }
        if bundleID == ownBundleID {
            return "myTime can't block itself."
        }
        if path.hasPrefix("/System/") {
            return "System apps can't be blocked."
        }
        if let app = apps.first(where: { $0.bundleIDs.contains(bundleID) }) {
            return "\(app.name) is already blocked."
        }
        return nil
    }
}

extension EngineCore {
    public func summary(of change: SettingChange, locale: Locale) -> String {
        switch change {
        case let .setNumber(key, value):
            let oldValue = DurationFormat.setting(key, setting(key), locale: locale)
            let newValue = DurationFormat.setting(key, key.clamp(value), locale: locale)
            return "\(key.title): \(oldValue) → \(newValue)"
        case let .addApp(app):
            return "Add \(app.name)"
        case let .removeApp(id):
            return "Remove \(app(id: id)?.name ?? "app")"
        case let .setMode(appID, mode, enabled):
            let action = enabled ? "Turn on" : "Turn off"
            return "\(action) \(mode.title) for \(app(id: appID)?.name ?? "app")"
        case .uninstall:
            return "Uninstall myTime"
        }
    }

    public mutating func submit(_ originalChange: SettingChange, locale: Locale) -> SubmitResult {
        let change = clamped(originalChange)
        state.pending.removeAll { $0.change.fieldKey == change.fieldKey }
        guard !isNoOp(change) else {
            return .noChange
        }

        let changeSummary = summary(of: change, locale: locale)
        if SettingsPolicy.isLoosening(change, settings: state.settings) {
            let applyAt = now.addingTimeInterval(Double(setting(.looseningDelaySeconds)))
            state.pending.append(
                PendingChange(
                    createdAt: now,
                    applyAt: applyAt,
                    change: change,
                    summary: changeSummary
                ))
            let applyAtText = DurationFormat.sessionStart(
                applyAt,
                now: now,
                timeZone: timeZone,
                locale: locale
            )
            record(.changeScheduled, "Scheduled: \(changeSummary) · applies \(applyAtText)")
            return .scheduled(applyAt: applyAt)
        }

        apply(change)
        let historyKind: HistoryKind
        if case .addApp = change {
            historyKind = .appAdded
        } else {
            historyKind = .changeApplied
        }
        record(historyKind, changeSummary)
        return .applied
    }

    public mutating func cancelPending(id: UUID) {
        guard let index = state.pending.firstIndex(where: { $0.id == id }) else {
            return
        }
        let pending = state.pending.remove(at: index)
        record(.changeCanceled, "Canceled: \(pending.summary)")
    }

    mutating func applyDuePending() -> [EngineEffect] {
        let currentNow = now
        let due = state.pending
            .filter { currentNow >= $0.applyAt }
            .sorted { $0.applyAt < $1.applyAt }
        state.pending.removeAll { currentNow >= $0.applyAt }

        var effects: [EngineEffect] = []
        for pending in due {
            guard targetAppExists(for: pending.change) else {
                continue
            }
            apply(pending.change)
            let historyKind: HistoryKind
            if case .removeApp = pending.change {
                historyKind = .appRemoved
            } else {
                historyKind = .changeApplied
            }
            record(historyKind, "Applied: \(pending.summary)")
            if case .uninstall = pending.change {
                effects.append(.uninstall)
            }
        }
        return effects
    }

    private func clamped(_ change: SettingChange) -> SettingChange {
        guard case let .setNumber(key, value) = change else {
            return change
        }
        return .setNumber(key: key, value: key.clamp(value))
    }

    private func isNoOp(_ change: SettingChange) -> Bool {
        switch change {
        case let .setNumber(key, value):
            return setting(key) == value
        case let .addApp(newApp):
            return state.settings.apps.contains { app in
                !Set(app.bundleIDs).isDisjoint(with: newApp.bundleIDs)
            }
        case let .removeApp(id):
            return app(id: id) == nil
        case let .setMode(appID, mode, enabled):
            guard let app = app(id: appID) else {
                return true
            }
            return app.modes.contains(mode) == enabled
        case .uninstall:
            return false
        }
    }

    private func targetAppExists(for change: SettingChange) -> Bool {
        switch change {
        case let .removeApp(id):
            return app(id: id) != nil
        case let .setMode(appID, _, _):
            return app(id: appID) != nil
        default:
            return true
        }
    }

    private mutating func apply(_ change: SettingChange) {
        switch change {
        case let .setNumber(key, value):
            state.settings[key] = value
            if key == .dayStartHour {
                state.tokensDayKey = CalendarKeys.dayKey(
                    now,
                    dayStartHour: state.settings[key],
                    timeZone: timeZone
                )
            }
        case let .addApp(app):
            state.settings.apps.append(app)
        case let .removeApp(id):
            state.settings.apps.removeAll { $0.id == id }
        case let .setMode(appID, mode, enabled):
            guard let index = state.settings.apps.firstIndex(where: { $0.id == appID }) else {
                return
            }
            if enabled {
                state.settings.apps[index].modes.insert(mode)
            } else {
                state.settings.apps[index].modes.remove(mode)
            }
        case .uninstall:
            break
        }
    }
}
