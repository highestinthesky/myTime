import AppKit
import MyTimeCore

@MainActor final class HeadsUpController {
    unowned let model: AppModel
    private var panel: OverlayPanel?
    private var hideTimer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func show(bookingID: UUID) {
        let bookedAppIsRunning = model.monitor.runningBlocked(in: model.core).contains { app, _ in
            app.modes.contains(.booked)
        }
        guard bookedAppIsRunning else {
            return
        }
        guard model.core.state.bookings.contains(where: { $0.id == bookingID }) else {
            return
        }
        close()

        let panel = OverlayPanel(allowsKey: false)
        panel.setRoot(
            HeadsUpView(model: model, bookingID: bookingID) { [weak self] in
                self?.close()
            }
        )
        panel.setFrameOrigin(origin(for: panel.frame.size))
        panel.orderFrontRegardless()
        self.panel = panel

        let timer = Timer(timeInterval: Constants.headsUpVisible, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
        timer.tolerance = 0.8
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func close() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func origin(for size: NSSize) -> NSPoint {
        if let pill = model.overlays.pillFrame {
            return NSPoint(x: pill.maxX - size.width, y: pill.minY - size.height - 8)
        }
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 12)
    }
}
