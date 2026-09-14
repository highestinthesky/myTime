import MyTimeCore
import SwiftUI

@MainActor
struct EmergencyFlowView: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    private var wait: Int {
        model.core.setting(.emergencyWaitSeconds)
    }

    private var minutes: Int {
        model.core.setting(.emergencyAccessSeconds) / 60
    }

    var body: some View {
        VStack(spacing: 12) {
            switch session.step {
            case .choose:
                EmptyView()
            case .emergencyReason:
                reasonStep
            case let .emergencyWaiting(until):
                waitingStep(until: until)
            case .emergencyReady:
                Button("Open \(session.app.name) for \(minutes) min") {
                    actions.openEmergency()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emergency access")
                .font(.headline)
            Text(
                "Once a week. After a \(wait)-second wait you'll get "
                    + "\(minutes) \(minutes == 1 ? "minute" : "minutes")."
            )
            TextField("What's the emergency?", text: $session.emergencyReason)
                .textFieldStyle(.roundedBorder)
                .onChange(of: session.emergencyReason) {
                    session.touch()
                }
            HStack {
                Button("Back") {
                    session.step = .choose
                    session.touch()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Start wait") {
                    let until = Date().addingTimeInterval(Double(wait))
                    session.step = .emergencyWaiting(until: until)
                    session.touch()
                }
                .buttonStyle(.bordered)
                .disabled(trimmedReason.count < Constants.minEmergencyReason)
            }
        }
    }

    private func waitingStep(until: Date) -> some View {
        VStack(spacing: 12) {
            Text("Opening in \(max(0, Int(ceil(until.timeIntervalSince(session.now)))))s")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button("Cancel") {
                session.step = .emergencyReason
                session.touch()
            }
            .buttonStyle(.bordered)
            Text("Your pass won't be used.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedReason: String {
        session.emergencyReason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
