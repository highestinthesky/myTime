import AppKit
import Observation
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case apps
    case pending
    case history
}

@MainActor @Observable final class SettingsNavigation {
    var tab: SettingsTab = .general
}

/// Opens myTime's regular windows (Book a Session, Quit, Settings) in front, one of each at a time.
@MainActor final class WindowRouter {
    unowned let model: AppModel
    private let settingsNavigation = SettingsNavigation()
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func showBooking() {
        model.refresh(.intent)
        show(title: "Book a Session", size: NSSize(width: 380, height: 300)) {
            BookingView(model: model) { [weak self] in
                self?.close("Book a Session")
            }
        }
    }

    func showQuit() {
        show(title: "Quit myTime", size: NSSize(width: 380, height: 300)) {
            QuitView(model: model) { [weak self] in
                self?.close("Quit myTime")
            }
        }
    }

    func showSettings(tab: SettingsTab) {
        model.refresh(.intent)
        settingsNavigation.tab = tab
        show(title: "myTime Settings", size: NSSize(width: 560, height: 520)) {
            SettingsView(model: model, navigation: settingsNavigation)
        }
    }

    private func show<Content: View>(title: String, size: NSSize, content: () -> Content) {
        if let window = windows[title] {
            bringForward(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[title] = window
        if title == "myTime Settings" {
            model.settingsDidOpen()
        }
        closeObservers[title] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if title == "myTime Settings" {
                    self?.model.settingsDidClose()
                }
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
