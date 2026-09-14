import AppKit
import MyTimeCore
import SwiftUI

struct OverlayActions {
    let neverMind: () -> Void
    let quickLook: (Int) -> Void
    let startFocus: () -> Void
    let backToWork: () -> Void
    let endFocus: () -> Void
}

/// The gate card shown when a blocked app is opened without access (spec §7.3, Run 1 subset).
/// Layout is fixed-height so the panel can be sized once: the status and error lines always reserve their space.
@MainActor
struct GateView: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    private var tokens: Int { model.core.state.tokens }

    var body: some View {
        VStack(spacing: 14) {
            iconWithPauseRing
            Text("Still want to open \(session.app.name)?")
                .font(.title3.weight(.semibold))
            Text(
                "\(tokenCount(tokens)) · 1 token = "
                    + "\(DurationFormat.short(Double(model.core.setting(.focusSecondsPerToken)))) of focus"
            )
            .foregroundStyle(.secondary)
            Text(session.isPausing ? "Options unlock in \(session.pauseRemaining)s" : " ")
                .foregroundStyle(.secondary)
                .frame(height: 20)

            if session.app.modes.contains(.quickLook) {
                if tokens == 0 {
                    VStack(spacing: 10) {
                        Text(
                            "No tokens yet. Your next one is "
                                + "\(DurationFormat.short(model.core.secondsToNextToken)) of focus away."
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        Button("Start Focus") {
                            actions.startFocus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isPausing)
                    }
                } else {
                    quickLookCard
                }
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
        }
        .padding(24)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
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

    private var quickLookCard: some View {
        let perToken = model.core.setting(.quickLookSecondsPerToken)
        let maxTokens = min(model.core.setting(.quickLookMaxTokens), tokens)
        let count = min(session.quickLookTokens, maxTokens)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick look").font(.headline)
                Spacer()
                Text("\(perToken) s per token").foregroundStyle(.secondary)
            }
            HStack {
                Stepper(value: $session.quickLookTokens, in: 1...maxTokens) {
                    Text(tokenCount(count)).monospacedDigit()
                }
                .onChange(of: session.quickLookTokens) { session.touch() }
                Spacer()
                Button("Open for \(DurationFormat.clock(Double(count * perToken))) · \(count) ◆") {
                    actions.quickLook(count)
                }
                .disabled(session.isPausing)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tokenCount(_ n: Int) -> String { "\(n) \(n == 1 ? "token" : "tokens")" }
}
