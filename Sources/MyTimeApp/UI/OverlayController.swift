import AppKit
import MyTimeCore
import Observation
import SwiftUI

/// State for one gate. The gated app has already been quit; the gate belongs to the app, not a process.
@MainActor @Observable final class GateSession {
    let app: BlockedApp
    @ObservationIgnored let bundleURL: URL?
    @ObservationIgnored let icon: NSImage
    let pauseEndsAt: Date
    let pauseSeconds: Double
    var now: Date
    var lastInteraction: Date
    var quickLookTokens = 1
    var errorMessage: String?

    init(app: BlockedApp, bundleURL: URL?, pauseEndsAt: Date) {
        self.app = app
        self.bundleURL = bundleURL
        self.icon = NSWorkspace.shared.icon(forFile: bundleURL?.path ?? "")
        self.pauseEndsAt = pauseEndsAt
        self.pauseSeconds = max(0, pauseEndsAt.timeIntervalSinceNow)
        self.now = Date()
        self.lastInteraction = Date()
    }

    var isPausing: Bool { now < pauseEndsAt }
    var pauseRemaining: Int { max(0, Int(ceil(pauseEndsAt.timeIntervalSince(now)))) }
    /// 1 at the start of the pause, 0 when options unlock.
    var pauseFraction: Double {
        pauseSeconds > 0 ? min(1, max(0, pauseEndsAt.timeIntervalSince(now) / pauseSeconds)) : 0
    }
    func touch() { lastInteraction = Date() }
}

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

    init(model: AppModel) { self.model = model }

    // MARK: Gate

    func showGate(app: BlockedApp, bundleURL: URL?) {
        guard gateAppID != app.id else { return }
        closeGate()
        let session = GateSession(
            app: app, bundleURL: bundleURL,
            pauseEndsAt: Date().addingTimeInterval(Double(model.core.setting(.gatePauseSeconds))))
        self.session = session

        let panel = OverlayPanel(allowsKey: true)
        panel.setRoot(
            GateView(
                session: session, model: model,
                onNeverMind: { [weak self] in self?.neverMind() },
                onQuickLook: { [weak self] count in self?.quickLook(count) }))
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
            guard let self, let session = self.session else { return }
            session.now = Date()
            if Date().timeIntervalSince(session.lastInteraction) >= Constants.gateTimeout { self.neverMind() }
        }
    }

    func closeGate() {
        gateClock.stop()
        gatePanel?.orderOut(nil)
        gatePanel = nil
        session = nil
    }

    private func neverMind() {
        guard let session else { return }
        model.perform { $0.recordBackedOff(appID: session.app.id) }
        closeGate()
    }

    private func quickLook(_ tokens: Int) {
        guard let session else { return }
        session.touch()
        do {
            // The app was quit when the gate opened; it relaunches now, so launch grace starts now.
            let relaunchAt = model.displayNow
            _ = try model.perform {
                try $0.buyQuickLook(appID: session.app.id, tokens: tokens, appLaunchDate: relaunchAt)
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
