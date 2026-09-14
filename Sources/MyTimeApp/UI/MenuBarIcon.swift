import AppKit

/// Menu bar glyphs drawn as template images so the system tints them for light/dark menu bars (spec §7.1).
@MainActor enum MenuBarIcon {
    enum Kind: Hashable {
        case diamond
        case pause
        case ring(step: Int)
    }

    nonisolated static let size = NSSize(width: 18, height: 16)
    private static var cache: [String: NSImage] = [:]

    static func image(_ kind: Kind, dot: Bool) -> NSImage {
        let key = "\(kind)-\(dot)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: size, flipped: false) { _ in
            switch kind {
            case .diamond: drawSymbol("diamond.fill")
            case .pause: drawSymbol("pause.circle")
            case .ring(let step): drawRing(step: max(0, min(12, step)))
            }
            if dot {
                // Clear a small halo first so the dot never touches the glyph underneath.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 12.2, y: 9.2, width: 6.8, height: 6.8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 13.4, y: 10.4, width: 4.4, height: 4.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    private static func drawSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: (16 - s.width) / 2, y: (16 - s.height) / 2, width: s.width, height: s.height))
    }

    private static func drawRing(step: Int) {
        let center = NSPoint(x: 8, y: 8)
        let outline = NSBezierPath(ovalIn: NSRect(x: 1.75, y: 1.75, width: 12.5, height: 12.5))
        outline.lineWidth = 1.5
        NSColor.black.setStroke()
        outline.stroke()
        guard step > 0 else { return }
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(
            withCenter: center, radius: 5, startAngle: 90, endAngle: 90 - CGFloat(step) * 30, clockwise: true)
        wedge.close()
        NSColor.black.setFill()
        wedge.fill()
    }
}
