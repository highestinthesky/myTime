import AppKit
import MyTimeCore
import SwiftUI

/// Countdown pill for grants (spec §7.5). Lives in a fixed-size transparent panel; the capsule hugs the top-right.
@MainActor
struct PillView: View {
    let model: AppModel

    var body: some View {
        let _ = model.uiNow
        ZStack(alignment: .topTrailing) {
            Color.clear
            if let countdown = model.grantCountdown {
                pill(countdown)
            }
        }
    }

    private func pill(_ countdown: GrantCountdown) -> some View {
        let warm = countdown.remaining <= 10
        let tint: Color = warm ? Theme.warm : .primary
        let label = countdown.grant.kind == .emergency ? "Emergency" : countdown.app.name
        let icon = Image(nsImage: NSWorkspace.shared.icon(forFile: countdown.process.bundleURL?.path ?? ""))
        return HStack(spacing: 8) {
            icon
                .resizable()
                .frame(width: 18, height: 18)
                .overlay {
                    icon
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(Theme.warm)
                        .opacity(warm ? 1 : 0)
                }
            Text("\(label) · \(DurationFormat.clock(countdown.remaining))")
                .font(.system(.body, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thickMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: warm)
    }
}
