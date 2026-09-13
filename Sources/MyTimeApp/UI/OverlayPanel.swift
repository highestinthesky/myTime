import AppKit
import SwiftUI

/// Borderless floating panel used for the gate, pill, and heads-up.
/// Always non-activating: since macOS 14 a background app can't reliably activate itself while another app is in
/// front, so the gate becomes key *without* activating myTime (the Spotlight-style panel behavior). That keeps Esc
/// and text fields working.
final class OverlayPanel: NSPanel {
    private let allowsKey: Bool

    init(allowsKey: Bool) {
        self.allowsKey = allowsKey
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        // Borderless windows have no title bar to drag; let the user drag anywhere that isn't a control.
        isMovableByWindowBackground = true
        level = allowsKey ? .modalPanel : .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    func setRoot<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }
}
