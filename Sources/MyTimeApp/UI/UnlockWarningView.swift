import MyTimeCore
import SwiftUI

@MainActor
struct UnlockWarningView: View {
    let model: AppModel

    var body: some View {
        let _ = model.uiNow
        let quote = model.core.unlockQuote(at: model.displayNow)
        VStack(alignment: .leading, spacing: 10) {
            Text(UnlockCopy.closesIn(appNames: appNames, remaining: model.unlockRemaining ?? 0))
                .font(.headline)
                .monospacedDigit()
            if quote.multiplier > 1, let resetsAt = quote.resetsAt {
                Text(
                    UnlockCopy.nextUnlockLine(
                        multiplier: quote.multiplier, resetsAt: resetsAt,
                        timeZone: model.core.timeZone, locale: .current)
                )
                .foregroundStyle(.secondary)
            }
            Button("End now") {
                model.endUnlock()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var appNames: [String] {
        let running = model.monitor.runningBlockedAppIDs(in: model.core)
        return model.core.state.settings.apps.filter {
            running.contains($0.id) && $0.modes.contains(.unlock)
        }.map(\.name)
    }
}
