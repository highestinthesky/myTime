import SwiftUI
import MyTimeCore

@MainActor
struct PendingTab: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if pendingChanges.isEmpty {
                Text("No pending changes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(pendingChanges) { pending in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pending.summary)
                            Text(
                                "Applies in "
                                    + DurationFormat.short(
                                        pending.applyAt.timeIntervalSince(model.displayNow)
                                    )
                            )
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") {
                            model.cancelPending(id: pending.id)
                        }
                    }
                }
            }

            Button("Uninstall myTime…", role: .destructive) {
                scheduleUninstall()
            }
        }
    }

    private var pendingChanges: [PendingChange] {
        model.core.state.pending.sorted { first, second in
            first.applyAt < second.applyAt
        }
    }

    private func scheduleUninstall() {
        let delay = DurationFormat.short(
            Double(model.core.setting(.looseningDelaySeconds))
        )
        let confirmed = SettingsAlerts.confirm(
            title: "myTime will uninstall itself in \(delay). You can cancel it here until then.",
            message: "",
            confirmTitle: "Schedule"
        )
        if confirmed {
            model.submit(.uninstall)
        }
    }
}
