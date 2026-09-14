import AppKit
import SwiftUI

@MainActor final class WindowRouter {
    unowned let model: AppModel
    private var bookingWindow: NSWindow?
    private var bookingCloseObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    func showBooking() {
        model.refresh(.intent)
        if let bookingWindow {
            bringForward(bookingWindow)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Book a Session"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: BookingView(model: model) { [weak self] in
                self?.closeBooking()
            }
        )
        window.center()
        bookingWindow = window
        bookingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearBookingWindow()
            }
        }
        bringForward(window)
    }

    func closeBooking() {
        bookingWindow?.close()
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func clearBookingWindow() {
        if let bookingCloseObserver {
            NotificationCenter.default.removeObserver(bookingCloseObserver)
        }
        bookingCloseObserver = nil
        bookingWindow = nil
    }
}
