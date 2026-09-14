import SwiftUI
import MyTimeCore

@MainActor
struct SettingsView: View {
    let model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Changes that make myTime stricter apply right away. Changes that loosen it apply after "
                    + "\(DurationFormat.short(Double(model.core.setting(.looseningDelaySeconds))))."
            )
            .foregroundStyle(.secondary)

            if abs(model.core.state.clock.offsetSeconds) > Constants.clockJumpTolerance {
                Text(
                    "Your Mac's clock was changed. myTime is ignoring the change "
                        + "(\(DurationFormat.short(abs(model.core.state.clock.offsetSeconds))))."
                )
                .foregroundStyle(.secondary)
            }

            TabView(selection: $navigation.tab) {
                GeneralSettingsTab(model: model)
                    .tabItem {
                        Text("General")
                    }
                    .tag(SettingsTab.general)
                BlockedAppsTab(model: model)
                    .tabItem {
                        Text("Blocked Apps")
                    }
                    .tag(SettingsTab.apps)
                PendingTab(model: model)
                    .tabItem {
                        Text("Pending")
                    }
                    .tag(SettingsTab.pending)
                HistoryTab(model: model)
                    .tabItem {
                        Text("History")
                    }
                    .tag(SettingsTab.history)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}
