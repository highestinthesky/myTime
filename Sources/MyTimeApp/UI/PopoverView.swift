import SwiftUI
import MyTimeCore
@MainActor
struct PopoverView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Constants.isDev ? "myTime · DEV" : "myTime")
                .font(.headline)
            focusBlock
            if model.core.claimableSeconds >= Constants.minClaimable {
                claimRow
            }
            tokensRow
            SessionsBlock(model: model)
            todayStrip
            #if DEV_TIMESCALE
                HStack {
                    Button("+1 token") { model.perform { $0.devAddToken() } }
                    Button("+5 min progress") { model.perform { $0.devAddProgress(seconds: 300) } }
                    Button("New day") { model.perform { $0.devSimulateNewDay() } }
                    Button("Reset state") { model.devReset() }
                }
            #endif
            Button("Quit myTime…") {
                model.router.showQuit()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }

    private var focusBlock: some View {
        VStack(spacing: 12) {
            FocusRing(fraction: focusFraction) {
                VStack(spacing: 2) {
                    Text(DurationFormat.clock(model.core.secondsToNextToken))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("to next token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.core.state.focus == nil {
                Button("Start Focus") {
                    model.startFocus()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text(focusCaption)
                    .foregroundStyle(.secondary)
                Button("End Focus") {
                    model.endFocus()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var claimRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "You were away \(DurationFormat.short(model.core.today.unclaimedAwaySeconds)) during focus today."
            )
            HoldButton(title: claimLabel, duration: Constants.holdToConfirm) {
                model.confirmClaim()
            }
            Button("Dismiss") {
                model.dismissClaim()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var tokensRow: some View {
        HStack {
            Text("◆ \(model.core.state.tokens) \(model.core.state.tokens == 1 ? "token" : "tokens")")
            Spacer()
            Text(
                "Resets at \(DurationFormat.hourOfDay(model.core.setting(.dayStartHour), locale: .current))"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var todayStrip: some View {
        HStack {
            statColumn(label: "Focus", value: DurationFormat.short(model.core.today.focusSeconds))
            statColumn(label: "Earned", value: "\(model.core.today.tokensEarned)")
            statColumn(label: "Backed off", value: "\(model.core.today.backedOff)")
        }
    }

    private var focusFraction: Double {
        let progress = model.core.state.progressSeconds + model.core.runtime.unvestedSeconds
        return progress / Double(model.core.setting(.focusSecondsPerToken))
    }

    private var focusCaption: String {
        if model.core.isAway {
            return "Paused — no activity"
        }
        let sessionSeconds = (model.core.state.focus?.creditedSeconds ?? 0) + model.core.runtime.unvestedSeconds
        return "This session · \(DurationFormat.short(sessionSeconds))"
    }

    private var claimLabel: String {
        var label = "Hold to count \(DurationFormat.short(model.core.claimableSeconds))"
        if model.core.claimableSeconds < model.core.today.unclaimedAwaySeconds {
            label += " (daily limit)"
        }
        return label
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .frame(maxWidth: .infinity)
    }
}
