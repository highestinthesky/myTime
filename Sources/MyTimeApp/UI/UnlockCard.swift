import MyTimeCore
import SwiftUI

@MainActor
struct UnlockCard: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    var body: some View {
        let quote = model.core.unlockQuote(at: model.displayNow)
        let tokens = model.core.state.tokens
        let selected = quote.options.first { $0.lengthSeconds == session.selectedLength }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Unlock")
                    .font(.headline)
                Spacer()
                if quote.multiplier > 1, let resetsAt = quote.resetsAt {
                    Text(
                        UnlockCopy.streakLine(
                            multiplier: quote.multiplier, resetsAt: resetsAt,
                            timeZone: model.core.timeZone, locale: .current)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let shortest = quote.options.first, shortest.cost > tokens {
                Text(
                    UnlockCopy.shortOfTokens(
                        needed: shortest.cost - tokens, lengthSeconds: shortest.lengthSeconds)
                )
                .foregroundStyle(.secondary)
                Text("Your next token is \(DurationFormat.short(model.core.secondsToNextToken)) of focus away.")
                    .foregroundStyle(.secondary)
                Button("Start Focus", action: actions.startFocus)
                    .buttonStyle(.bordered)
                    .disabled(session.isPausing)
            } else {
                HStack(spacing: 6) {
                    ForEach(quote.options, id: \.lengthSeconds) { option in
                        lengthButton(option, tokens: tokens)
                    }
                }
                Button {
                    guard let selected else { return }
                    actions.unlock(selected.lengthSeconds, selected.cost)
                } label: {
                    Text(
                        selected.map {
                            UnlockCopy.unlockButton(lengthSeconds: $0.lengthSeconds, cost: $0.cost)
                        } ?? "Choose a length"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(session.isPausing || selected == nil || (selected?.cost ?? 0) > tokens)
            }
        }
        .gateCardSurface()
        .onChange(of: quote) {
            clearUnaffordableSelection(quote: quote, tokens: tokens)
        }
        .onChange(of: tokens) {
            clearUnaffordableSelection(quote: quote, tokens: tokens)
        }
    }

    private func lengthButton(_ option: UnlockOption, tokens: Int) -> some View {
        let chosen = session.selectedLength == option.lengthSeconds
        return Button {
            session.selectedLength = option.lengthSeconds
            session.touch()
        } label: {
            VStack(spacing: 4) {
                Text(DurationFormat.short(Double(option.lengthSeconds)))
                Text(option.cost <= tokens ? "\(option.cost) ◆" : UnlockCopy.needsMore(option.cost - tokens))
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(chosen ? Theme.accent : Color.primary)
        .background(chosen ? Theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .disabled(session.isPausing || option.cost > tokens)
    }

    private func clearUnaffordableSelection(quote: UnlockQuote, tokens: Int) {
        guard let length = session.selectedLength else { return }
        if !quote.options.contains(where: { $0.lengthSeconds == length && $0.cost <= tokens }) {
            session.selectedLength = nil
        }
    }
}
