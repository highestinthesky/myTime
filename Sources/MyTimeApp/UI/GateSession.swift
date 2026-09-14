import AppKit
import MyTimeCore
import Observation

enum GateMode {
    case gate
    case focusCard
}

enum GateStep: Equatable {
    case choose
    case emergencyReason
    case emergencyWaiting(until: Date)
    case emergencyReady
}

/// State for one gate. The gated app has already been quit; the gate belongs to the app, not a process.
@MainActor @Observable final class GateSession {
    let app: BlockedApp
    @ObservationIgnored let bundleURL: URL?
    let mode: GateMode
    @ObservationIgnored let icon: NSImage
    let pauseEndsAt: Date
    let pauseSeconds: Double
    var now: Date
    var lastInteraction: Date
    var quickLookTokens = 1
    var errorMessage: String?
    var step: GateStep = .choose
    var replyNote = ""
    var emergencyReason = ""

    init(app: BlockedApp, bundleURL: URL?, mode: GateMode, pauseEndsAt: Date) {
        self.app = app
        self.bundleURL = bundleURL
        self.mode = mode
        self.icon = NSWorkspace.shared.icon(forFile: bundleURL?.path ?? "")
        self.pauseEndsAt = pauseEndsAt
        self.pauseSeconds = max(0, pauseEndsAt.timeIntervalSinceNow)
        self.now = Date()
        self.lastInteraction = Date()
    }

    var isPausing: Bool {
        now < pauseEndsAt
    }

    var pauseRemaining: Int {
        max(0, Int(ceil(pauseEndsAt.timeIntervalSince(now))))
    }

    /// 1 at the start of the pause, 0 when options unlock.
    var pauseFraction: Double {
        pauseSeconds > 0 ? min(1, max(0, pauseEndsAt.timeIntervalSince(now) / pauseSeconds)) : 0
    }

    func touch() {
        lastInteraction = Date()
    }
}
