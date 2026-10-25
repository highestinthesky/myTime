import MyTimeCore
import SwiftUI

@MainActor
struct UnlockBlock: View {
    let model: AppModel

    var body: some View {
        let _ = model.uiNow
        let quote = model.core.unlockQuote(at: model.displayNow)
        if model.unlockRemaining != nil || quote.multiplier > 1 {
            VStack(alignment: .leading, spacing: 6) {
                if let remaining = model.unlockRemaining {
                    HStack {
                        Text("Unlock · \(DurationFormat.clock(remaining)) left")
                            .monospacedDigit()
                        Spacer()
                        Button("End Unlock") {
                            model.endUnlock()
                        }
                        .buttonStyle(.bordered)
                    }
                    if quote.multiplier > 1, let resetsAt = quote.resetsAt {
                        Text(
                            UnlockCopy.nextUnlockLine(
                                multiplier: quote.multiplier, resetsAt: resetsAt,
                                timeZone: model.core.timeZone, locale: .current)
                        )
                        .foregroundStyle(.secondary)
                    }
                } else if quote.multiplier > 1, let resetsAt = quote.resetsAt {
                    Text(
                        UnlockCopy.streakLine(
                            multiplier: quote.multiplier, resetsAt: resetsAt,
                            timeZone: model.core.timeZone, locale: .current)
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
