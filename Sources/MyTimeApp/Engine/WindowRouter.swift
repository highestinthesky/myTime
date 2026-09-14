import AppKit
import SwiftUI

/// Opens myTime's regular windows (Book a Session, Quit) in front, one of each at a time.
@MainActor final class WindowRouter {
    unowned let model: AppModel
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func showBooking() {
        model.refresh(.intent)
        show(title: "Book a Session") {
            BookingView(model: model) { [weak self] in
                self?.close("Book a Session")
            }
        }
    }

    func showQuit() {
        show(title: "Quit myTime") {
            QuitView(model: model) { [weak self] in
                self?.close("Quit myTime")
            }
        }
    }

    private func show<Content: View>(title: String, content: () -> Content) {
        if let window = windows[title] {
            bringForward(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[title] = window
        closeObservers[title] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forget(title)
            }
        }
        bringForward(window)
    }

    private func close(_ title: String) {
        windows[title]?.close()
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func forget(_ title: String) {
        if let observer = closeObservers[title] {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObservers[title] = nil
        windows[title] = nil
    }
}
