import MyTimeCore
import SwiftUI

/// The quiet gate variant shown when a blocked app is opened during focus (spec §7.4).
@MainActor
struct FocusCardView: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: session.icon)
                .resizable()
                .frame(width: 48, height: 48)
            Text("You're focusing")
                .font(.title3.weight(.semibold))
            Text("\(DurationFormat.short(model.core.secondsToNextToken)) to your next token.")
                .foregroundStyle(.secondary)
            HStack {
                Button("End focus…") {
                    actions.endFocus()
                }
                .buttonStyle(.bordered)
                Button("Back to work") {
                    actions.backToWork()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
