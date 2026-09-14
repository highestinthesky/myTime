import SwiftUI
import MyTimeCore
@MainActor
struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        let _ = model.uiNow
        let prefix = Constants.isDev ? "DEV " : ""
        HStack(spacing: 4) {
            if let countdown = model.grantCountdown {
                Image(systemName: "hourglass")
                Text(prefix + DurationFormat.clock(countdown.remaining))
            } else if let remaining = model.bookingCountdown {
                Image(systemName: "hourglass")
                Text(prefix + DurationFormat.short(remaining))
            } else if model.core.state.focus != nil && model.core.isAway {
                Image(nsImage: MenuBarIcon.image(.pause, dot: model.showsClaimDot))
                Text(prefix + "\(model.core.state.tokens)")
            } else if model.core.state.focus != nil {
                Image(nsImage: MenuBarIcon.image(.ring(step: model.ringStep), dot: model.showsClaimDot))
                Text(prefix + "\(model.core.state.tokens)")
            } else {
                Image(nsImage: MenuBarIcon.image(.diamond, dot: model.showsClaimDot))
                Text(prefix + "\(model.core.state.tokens)")
            }
        }
        .monospacedDigit()
    }
}
