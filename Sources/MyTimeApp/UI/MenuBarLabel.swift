import SwiftUI
import MyTimeCore
struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        let _ = model.uiNow
        let countdown = model.grantCountdown
        let prefix = Constants.isDev ? "DEV " : ""
        HStack(spacing: 4) {
            Image(systemName: countdown == nil ? "diamond.fill" : "hourglass")
            Text(prefix + (countdown.map { DurationFormat.clock($0.remaining) } ?? "\(model.core.state.tokens)"))
                .monospacedDigit()
        }
    }
}
