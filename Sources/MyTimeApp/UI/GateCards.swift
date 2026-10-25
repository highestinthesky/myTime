import MyTimeCore
import SwiftUI

@MainActor
struct GateCards: View {
    @Bindable var session: GateSession
    let model: AppModel
    let actions: OverlayActions

    var body: some View {
        VStack(spacing: 12) {
            if session.app.modes.contains(.unlock) {
                UnlockCard(session: session, model: model, actions: actions)
            }
            if session.app.modes.contains(.booked) {
                sessionsLine
            }
        }
    }

    private var sessionsLine: some View {
        HStack {
            if let booking = model.core.upcomingBookings.first {
                Text(
                    "Next session: "
                        + DurationFormat.sessionStart(
                            booking.start,
                            now: model.displayNow,
                            timeZone: .current,
                            locale: .current
                        )
                )
                .foregroundStyle(.secondary)
            } else {
                Text("Sessions: none booked")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Book a session…") {
                    actions.bookSession()
                }
                .buttonStyle(.link)
                .disabled(session.isPausing)
            }
        }
    }
}

extension View {
    func gateCardSurface() -> some View {
        padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
