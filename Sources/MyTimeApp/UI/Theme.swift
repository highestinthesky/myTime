import AppKit
import SwiftUI
enum Theme {
    private static func color(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: values.0, green: values.1, blue: values.2, alpha: 1)
            })
    }
    static let accent = color(light: (47 / 255, 143 / 255, 131 / 255), dark: (91 / 255, 192 / 255, 178 / 255))
    static let warm = color(light: (217 / 255, 138 / 255, 31 / 255), dark: (242 / 255, 178 / 255, 76 / 255))
}
