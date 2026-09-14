import AppKit
import MyTimeCore
import SwiftUI

@MainActor
struct HeadsUpView: View {
    let model: AppModel
    let bookingID: UUID
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let booking {
                Text(
                    "Session ends in "
                        + DurationFormat.short(booking.end.timeIntervalSince(model.displayNow))
                )
                if model.core.canExtendBooking(id: bookingID) {
                    Button(
                        "Extend "
                            + DurationFormat.short(
                                Double(model.core.setting(.bookingExtensionSeconds))
                            )
                    ) {
                        model.extendBooking(id: bookingID)
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var booking: Booking? {
        model.core.state.bookings.first { $0.id == bookingID }
    }
}
