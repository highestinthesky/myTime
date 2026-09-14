import SwiftUI

/// Press and hold to confirm (spec §7.7). Releasing early resets the fill.
@MainActor
struct HoldButton: View {
    let title: String
    let duration: TimeInterval
    let action: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.accent.opacity(0.35))
                        .frame(width: geo.size.width * progress)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 20) {
                action()
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Count away time") { action() }
    }
}
