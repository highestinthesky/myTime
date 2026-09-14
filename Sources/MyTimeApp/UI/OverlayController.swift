import AppKit
import MyTimeCore
import SwiftUI

/// Presents the gate and the countdown pill (spec §6.4–§6.5, §7.3, §7.5).
@MainActor final class OverlayController {
    unowned let model: AppModel
    private var gatePanel: OverlayPanel?
    private var pillPanel: OverlayPanel?
    private var session: GateSession?
    private let gateClock = RepeatingUITimer()
    private var pillMoveObserver: NSObjectProtocol?

    private static let pillOriginKey = "mytime.pillOrigin"
    private static let pillSize = NSSize(width: 320, height: 72)

    var gateAppID: UUID? { session?.app.id }
    var isGateVisible: Bool { gatePanel != nil }
    var pillFrame: NSRect? { pillPanel?.frame }

    init(model: AppModel) { self.model = model }

    // MARK: Gate

    func showGate(app: BlockedApp, bundleURL: URL?) {
        show(app: app, bundleURL: bundleURL, mode: .gate)
    }

    func showFocusCard(app: BlockedApp, bundleURL: URL?) {
        show(app: app, bundleURL: bundleURL, mode: .focusCard)
    }

    private func show(app: BlockedApp, bundleURL: URL?, mode: GateMode) {
        guard !(gateAppID == app.id && session?.mode == mode) else {
            return
        }
        closeGate()
        let session = GateSession(
            app: app,
            bundleURL: bundleURL,
            mode: mode,
            pauseEndsAt: Date().addingTimeInterval(Double(model.core.setting(.gatePauseSeconds))))
        self.session = session

        let panel = OverlayPanel(allowsKey: true)
        let actions = OverlayActions(
            neverMind: { [weak self] in
                self?.neverMind()
            },
            quickLook: { [weak self] count in
                self?.quickLook(count)
            },
            reply: { [weak self] note in
                self?.reply(note)
            },
            openEmergency: { [weak self] in
                self?.openEmergency()
            },
            bookSession: { [weak self] in
                self?.bookSession()
            },
            startFocus: { [weak self] in
                self?.startFocus()
            },
            backToWork: { [weak self] in
                self?.backToWork()
            },
            endFocus: { [weak self] in
                self?.endFocus()
            }
        )
        switch mode {
        case .gate:
            panel.setRoot(GateView(session: session, model: model, actions: actions))
        case .focusCard:
            panel.setRoot(FocusCardView(session: session, model: model, actions: actions))
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        gatePanel = panel
        // Non-activating panel: becomes key for Esc/typing without myTime taking activation.
        panel.orderFrontRegardless()
        panel.makeKey()

        gateClock.start(interval: 1) { [weak self] in
            guard let self, let session = self.session else {
                return
            }
            session.now = Date()
            if case let .emergencyWaiting(until) = session.step {
                session.touch()
                if session.now >= until {
                    session.step = .emergencyReady
                }
            }
            if Date().timeIntervalSince(session.lastInteraction) >= Constants.gateTimeout {
                switch session.mode {
                case .gate:
                    self.neverMind()
                case .focusCard:
                    self.backToWork()
                }
            }
        }
    }

    func syncGateMode() {
        guard session?.mode == .gate, model.core.state.focus != nil, let session else {
            return
        }
        let app = session.app
        let bundleURL = session.bundleURL
        closeGate()
        showFocusCard(app: app, bundleURL: bundleURL)
    }

    func closeGate() {
        gateClock.stop()
        gatePanel?.orderOut(nil)
        gatePanel = nil
        session = nil
    }

    private func neverMind() {
        guard let session else {
            return
        }
        model.perform { $0.recordBackedOff(appID: session.app.id) }
        closeGate()
    }

    private func startFocus() {
        guard let session else {
            return
        }
        let appID = session.app.id
        closeGate()
        model.perform { core in
            core.recordBackedOff(appID: appID)
            core.startFocus()
        }
    }

    private func backToWork() {
        guard let session else {
            return
        }
        model.perform { core in
            core.recordBackedOff(appID: session.app.id)
        }
        closeGate()
    }

    private func endFocus() {
        guard let session else {
            return
        }
        let app = session.app
        let bundleURL = session.bundleURL
        closeGate()
        model.endFocus()
        showGate(app: app, bundleURL: bundleURL)
    }

    private func quickLook(_ tokens: Int) {
        guard let session else { return }
        session.touch()
        do {
            // The app was quit when the gate opened; it relaunches right after buying.
            _ = try model.perform {
                try $0.buyQuickLook(appID: session.app.id, tokens: tokens)
            }
            let bundleURL = session.bundleURL
            closeGate()
            relaunch(bundleURL)
        } catch let error as EngineError {
            session.errorMessage = error.userMessage
        } catch {
            session.errorMessage = nil
        }
    }

    private func reply(_ note: String) {
        guard let session else {
            return
        }
        session.touch()
        do {
            _ = try model.perform {
                try $0.buyReply(appID: session.app.id, note: note)
            }
            let bundleURL = session.bundleURL
            closeGate()
            relaunch(bundleURL)
        } catch let error as EngineError {
            session.errorMessage = error.userMessage
        } catch {
            session.errorMessage = nil
        }
    }

    private func openEmergency() {
        guard let session else {
            return
        }
        session.touch()
        do {
            _ = try model.perform {
                try $0.useEmergency(appID: session.app.id, reason: session.emergencyReason)
            }
            let bundleURL = session.bundleURL
            closeGate()
            relaunch(bundleURL)
        } catch let error as EngineError {
            session.errorMessage = error.userMessage
        } catch {
            session.errorMessage = nil
        }
    }

    private func bookSession() {
        guard let session else {
            return
        }
        let appID = session.app.id
        closeGate()
        model.perform { core in
            core.recordBackedOff(appID: appID)
        }
        model.router.showBooking()
    }

    private func relaunch(_ bundleURL: URL?) {
        guard let bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error { NSLog("myTime: relaunch failed: \(error)") }
        }
    }

    // MARK: Pill

    /// Shows or hides the pill. AppModel's countdown timer refreshes the engine every second while it's visible.
    func updatePill() {
        guard model.grantCountdown != nil else {
            if let pillPanel {
                pillPanel.orderOut(nil)
                self.pillPanel = nil
            }
            return
        }
        guard pillPanel == nil else { return }

        let panel = OverlayPanel(allowsKey: false)
        panel.setContentSize(Self.pillSize)
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        panel.setFrameOrigin(savedPillOrigin() ?? defaultPillOrigin())
        panel.orderFrontRegardless()
        pillPanel = panel

        if pillMoveObserver == nil {
            pillMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: nil, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let moved = note.object as? NSWindow, moved === self.pillPanel else { return }
                    UserDefaults.standard.set(NSStringFromPoint(moved.frame.origin), forKey: Self.pillOriginKey)
                }
            }
        }
    }

    private func defaultPillOrigin() -> NSPoint {
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: frame.maxX - Self.pillSize.width - 12, y: frame.maxY - Self.pillSize.height - 12)
    }

    /// The last position the user dragged the pill to, if it's still on a connected screen.
    private func savedPillOrigin() -> NSPoint? {
        guard let string = UserDefaults.standard.string(forKey: Self.pillOriginKey) else { return nil }
        let origin = NSPointFromString(string)
        let rect = NSRect(origin: origin, size: Self.pillSize)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect) } ? origin : nil
    }
}
