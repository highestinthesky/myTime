import MyTimeCore
import SwiftUI

@MainActor
struct GateCards: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    private var tokens: Int {
        model.core.state.tokens
    }

    private var hasTokenMode: Bool {
        session.app.modes.contains(.quickLook) || session.app.modes.contains(.reply)
    }

    var body: some View {
        VStack(spacing: 12) {
            if tokens == 0 && hasTokenMode {
                noTokens
            } else {
                if session.app.modes.contains(.quickLook) {
                    quickLookCard
                }
                if session.app.modes.contains(.reply) {
                    replyCard
                }
            }
            if session.app.modes.contains(.booked) {
                sessionsLine
            }
        }
    }

    private var noTokens: some View {
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
    }

    private var quickLookCard: some View {
        let perToken = model.core.setting(.quickLookSecondsPerToken)
        let maxTokens = min(model.core.setting(.quickLookMaxTokens), tokens)
        let count = min(session.quickLookTokens, maxTokens)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick look")
                    .font(.headline)
                Spacer()
                Text("\(perToken) s per token")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Stepper(value: $session.quickLookTokens, in: 1...maxTokens) {
                    Text(tokenCount(count))
                        .monospacedDigit()
                }
                .onChange(of: session.quickLookTokens) {
                    session.touch()
                }
                Spacer()
                Button("Open for \(DurationFormat.clock(Double(count * perToken))) · \(count) ◆") {
                    actions.quickLook(count)
                }
                .disabled(session.isPausing)
            }
        }
        .gateCardSurface()
    }

    private var replyCard: some View {
        let seconds = model.core.setting(.replySeconds)
        let cost = model.core.setting(.replyTokenCost)
        let perDay = model.core.setting(.replyPerDay)
        let left = max(0, perDay - model.core.today.replies)
        let reason = model.core.replyUnavailableReason(appID: session.app.id, note: session.replyNote)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reply mode")
                    .font(.headline)
                Spacer()
                Text(
                    "\(DurationFormat.short(Double(seconds))) · \(cost) ◆ · "
                        + "\(left) of \(perDay) left today"
                )
                .foregroundStyle(.secondary)
            }
            HStack {
                TextField("What are you here to do?", text: $session.replyNote)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: session.replyNote) {
                        session.touch()
                    }
                Button("Open") {
                    actions.reply(session.replyNote)
                }
                .disabled(session.isPausing || reason != nil)
            }
            if !session.isPausing, let message = replyReasonMessage(reason, cost: cost) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .gateCardSurface()
    }

    private var sessionsLine: some View {
        HStack {
            if let booking = model.core.upcomingBookings.first {
                Text(
                    "Next session: "
                        + DurationFormat.sessionStart(
                            booking.start,
                            now: model.displayNow,
                            timeZone: .current,
                            locale: .current
                        )
                )
                .foregroundStyle(.secondary)
            } else {
                Text("Sessions: none booked")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Book a session…") {
                    actions.bookSession()
                }
                .buttonStyle(.link)
                .disabled(session.isPausing)
            }
        }
    }

    private func replyReasonMessage(_ reason: EngineError?, cost: Int) -> String? {
        switch reason {
        case .noteTooShort:
            return "Write at least 8 characters"
        case .notEnoughTokens:
            return "Needs \(cost) \(cost == 1 ? "token" : "tokens")"
        case .replyLimitReached:
            return "No replies left today"
        default:
            return nil
        }
    }

    private func tokenCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "token" : "tokens")"
    }
}

extension View {
    fileprivate func gateCardSurface() -> some View {
        padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
