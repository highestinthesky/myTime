import MyTimeCore
import SwiftUI

@MainActor
struct SessionsBlock: View {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Text(
                    "\(DurationFormat.short(Double(model.core.allowanceRemaining(weekOf: model.core.now)))) "
                        + "left this week"
                )
                .foregroundStyle(.secondary)
            }
            if let booking = model.core.activeBooking {
                liveRow(booking)
            }
            ForEach(Array(model.core.upcomingBookings.prefix(3))) { booking in
                upcomingRow(booking)
            }
            Button("Book a Session…") {
                model.router.showBooking()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func liveRow(_ booking: Booking) -> some View {
        HStack {
            Text("Live · \(DurationFormat.short(booking.end.timeIntervalSince(model.displayNow))) left")
            Spacer()
            if model.core.canExtendBooking(id: booking.id) {
                Button(
                    "Extend "
                        + DurationFormat.short(Double(model.core.setting(.bookingExtensionSeconds)))
                ) {
                    model.extendBooking(id: booking.id)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Button("End") {
                model.endBooking(id: booking.id)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func upcomingRow(_ booking: Booking) -> some View {
        HStack {
            Text(
                DurationFormat.sessionStart(
                    booking.start,
                    now: model.displayNow,
                    timeZone: .current,
                    locale: .current
                ) + " · \(DurationFormat.short(Double(booking.durationSeconds)))"
            )
            Spacer()
            Button("Cancel") {
                model.cancelBooking(id: booking.id)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
