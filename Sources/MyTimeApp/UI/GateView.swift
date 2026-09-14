import AppKit
import MyTimeCore
import SwiftUI

struct OverlayActions {
    let neverMind: () -> Void
    let quickLook: (Int) -> Void
    let reply: (String) -> Void
    let openEmergency: () -> Void
    let bookSession: () -> Void
    let startFocus: () -> Void
    let backToWork: () -> Void
    let endFocus: () -> Void
}

/// The gate card shown when a blocked app is opened without access (spec §7.3).
@MainActor
struct GateView: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    var body: some View {
        VStack(spacing: 14) {
            iconWithPauseRing
            Text("Still want to open \(session.app.name)?")
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
            Text(session.isPausing ? "Options unlock in \(session.pauseRemaining)s" : " ")
                .foregroundStyle(.secondary)
                .frame(height: 20)

            if session.step == .choose {
                GateCards(session: session, model: model, actions: actions)
            } else {
                EmergencyFlowView(session: session, model: model, actions: actions)
            }

            Text(session.errorMessage ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 20)

            Button {
                actions.neverMind()
            } label: {
                Text("Never mind").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            if session.step == .choose {
                emergencyFooter
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var subtitle: String {
        if session.app.modes == [.booked] {
            return "\(session.app.name) is available during booked sessions."
        }
        let tokens = model.core.state.tokens
        let tokenWord = tokens == 1 ? "token" : "tokens"
        let focus = DurationFormat.short(Double(model.core.setting(.focusSecondsPerToken)))
        return "\(tokens) \(tokenWord) · 1 token = \(focus) of focus"
    }

    private var emergencyFooter: some View {
        Group {
            if model.core.emergencyUsesLeftThisWeek > 0 {
                Button("Emergency access") {
                    session.step = .emergencyReason
                    session.touch()
                }
                .buttonStyle(.link)
                .disabled(session.isPausing)
            } else {
                Text("Emergency access used · resets Monday")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var iconWithPauseRing: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: session.pauseFraction)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: session.now)
            Image(nsImage: session.icon)
                .resizable()
                .frame(width: 64, height: 64)
        }
        .frame(width: 84, height: 84)
    }
}
