import AppKit
import MyTimeCore

@MainActor final class UnlockWarningController {
    unowned let model: AppModel
    private var panel: OverlayPanel?
    private let countdownTimer = RepeatingUITimer()

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard model.core.activeUnlock != nil else { return }
        close()
        let panel = OverlayPanel(allowsKey: false)
        panel.setRoot(UnlockWarningView(model: model))
        panel.setFrameOrigin(origin(for: panel.frame.size))
        panel.orderFrontRegardless()
        self.panel = panel
        countdownTimer.start(interval: 1) { [weak self] in
            self?.model.refresh(.uiTick)
        }
    }

    func close() {
        countdownTimer.stop()
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
