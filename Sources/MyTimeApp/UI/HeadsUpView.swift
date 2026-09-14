import AppKit
import MyTimeCore
import SwiftUI

enum HeadsUpKind {
    case started
    case endingSoon
}

/// The small session notice under the pill (spec §7.6): a reminder when a session starts, and one before it ends.
@MainActor
struct HeadsUpView: View {
    let model: AppModel
    let kind: HeadsUpKind
    let bookingID: UUID
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let booking {
                switch kind {
                case .started:
                    startedContent(booking)
                case .endingSoon:
                    endingSoonContent(booking)
                }
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func startedContent(_ booking: Booking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your session has started")
                .font(.headline)
            Text("Until \(DurationFormat.timeOfDay(booking.end, timeZone: .current, locale: .current))")
                .foregroundStyle(.secondary)
            if let (app, url) = appToOpen {
                Button("Open \(app.name)") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    onClose()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func endingSoonContent(_ booking: Booking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private var booking: Booking? {
        model.core.state.bookings.first { $0.id == bookingID }
    }

    /// The first app with Sessions on that isn't already open and can be found on disk.
    private var appToOpen: (BlockedApp, URL)? {
        let running = Set(model.monitor.runningBlocked(in: model.core).map { app, _ in app.id })
        for app in model.core.state.settings.apps where app.modes.contains(.booked) && !running.contains(app.id) {
            for bundleID in app.bundleIDs {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    return (app, url)
                }
            }
        }
        return nil
    }
}
