import AppKit
import MyTimeCore
import SwiftUI

/// Countdown pill for grants (spec §7.5). Lives in a fixed-size transparent panel; the capsule hugs the top-right.
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
        let warm = countdown.remaining <= Constants.extendWindow
        let tint: Color = warm ? Theme.warm : .primary
        let label = countdown.grant.kind == .emergency ? "Emergency" : countdown.app.name
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: countdown.process.bundleURL?.path ?? ""))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) · \(DurationFormat.clock(countdown.remaining))")
                    .font(.system(.body, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if countdown.grant.kind == .reply, let note = countdown.grant.note {
                    Text("“\(note)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if warm && model.core.canExtend(grantID: countdown.grant.id) {
                Button("+\(model.core.setting(.quickLookSecondsPerToken)) s · 1 ◆") {
                    model.perform { try? $0.extendGrant(grantID: countdown.grant.id) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thickMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: warm)
    }
}
