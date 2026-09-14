import SwiftUI

/// Focus progress ring with caller-supplied center content (spec §7.2).
@MainActor
struct FocusRing<Content: View>: View {
    let fraction: Double
    let content: Content

    init(fraction: Double, @ViewBuilder content: () -> Content) {
        self.fraction = fraction
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)
            content
        }
        .frame(width: 160, height: 160)
    }
}
