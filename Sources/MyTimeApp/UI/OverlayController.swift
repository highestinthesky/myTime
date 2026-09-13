import AppKit
import Observation
import SwiftUI
import MyTimeCore
@MainActor @Observable final class GateSession {
    let app: BlockedApp
    @ObservationIgnored let process: NSRunningApplication
    @ObservationIgnored let icon: NSImage
    let pauseEndsAt: Date
    let pauseSeconds: Double
    var now: Date
    var lastInteraction: Date
    var quickLookTokens = 1
    var errorMessage: String?

    init(app: BlockedApp, process: NSRunningApplication, pauseEndsAt: Date) {
        self.app = app
        self.process = process
        self.icon = NSWorkspace.shared.icon(forFile: process.bundleURL?.path ?? "")
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
@MainActor final class OverlayController {
    unowned let model: AppModel
    private var gatePanel: OverlayPanel?
    private var pillPanel: OverlayPanel?
    private var session: GateSession?
    private let gateClock = RepeatingUITimer()
    private let rehideTimer = RepeatingUITimer()
    private let pillTimer = RepeatingUITimer()
    var gateOwnerPID: pid_t? { session?.process.processIdentifier }
    var isGateVisible: Bool { gatePanel != nil }
    init(model: AppModel) { self.model = model }
    func showGate(app: BlockedApp, process: NSRunningApplication) {
        guard gateOwnerPID != process.processIdentifier else { return }
        closeGate()
        let session = GateSession(
            app: app, process: process,
            pauseEndsAt: Date().addingTimeInterval(Double(model.core.setting(.gatePauseSeconds))))
        self.session = session
        let panel = OverlayPanel(allowsKey: true)
        panel.setRoot(
            GateView(
                session: session, model: model, onNeverMind: { [weak self] in self?.neverMind() },
                onQuickLook: { [weak self] count in self?.quickLook(count) }))
        let frame = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)!.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        gatePanel = panel
        // Non-activating panel: becomes key for Esc/typing without needing myTime to take activation.
        panel.orderFrontRegardless()
        panel.makeKey()
        gateClock.start(interval: 1) { [weak self] in
            guard let self, let session = self.session else { return }
            session.now = Date()
            if Date().timeIntervalSince(session.lastInteraction) >= Constants.gateTimeout { self.neverMind() }
        }
        rehideTimer.start(interval: 0.5) { [weak self] in
            guard let session = self?.session, !session.process.isHidden else { return }
            session.process.hide()
        }
    }
    private func neverMind() {
        guard let session else { return }
        model.perform { $0.recordBackedOff(appID: session.app.id) }
        let process = session.process
        closeGate()
        model.enforcer.terminate(process)
    }
    private func quickLook(_ tokens: Int) {
        guard let session else { return }
        session.touch()
        do {
            _ = try model.perform {
                try $0.buyQuickLook(appID: session.app.id, tokens: tokens, appLaunchDate: session.process.launchDate)
            }
            let process = session.process
            closeGate()
            process.unhide()
            NSApp.yieldActivation(to: process)
            process.activate()
            updatePill()
        } catch let error as EngineError { session.errorMessage = error.userMessage } catch {
            session.errorMessage = ""
        }
    }
    func closeGate() {
        gateClock.stop()
        rehideTimer.stop()
        gatePanel?.orderOut(nil)
        gatePanel = nil
        session = nil
    }
    func updatePill() {
        guard model.grantCountdown != nil else {
            pillPanel?.orderOut(nil)
            pillPanel = nil
            pillTimer.stop()
            return
        }
        if pillPanel == nil {
            let panel = OverlayPanel(allowsKey: false)
            panel.setContentSize(NSSize(width: 320, height: 72))
            panel.contentView = NSHostingView(rootView: PillView(model: model))
            let frame = NSScreen.main!.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 332, y: frame.maxY - 84))
            panel.orderFrontRegardless()
            pillPanel = panel
            pillTimer.start(interval: 1) { [weak self] in self?.updatePill() }
        }
    }
}
