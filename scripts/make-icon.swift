import AppKit
import CoreGraphics

// Developer tool only. Each representation is drawn at its own pixel size.
enum IconError: Error {
    case usage
    case bitmap
    case png
    case iconutil(Int32)
}

func drawIcon(pixels: Int) throws -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        throw IconError.bitmap
    }
    context.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let bottom = NSColor(srgbRed: 47 / 255, green: 143 / 255, blue: 131 / 255, alpha: 1).cgColor
    let top = NSColor(srgbRed: 91 / 255, green: 192 / 255, blue: 178 / 255, alpha: 1).cgColor
    let tile = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale,
        color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(tile)
    context.setFillColor(bottom)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [bottom, top] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()

    let small = pixels <= 32
    let stroke: CGFloat = small ? 80 : 64
    let gap: CGFloat = small ? 0 : 36
    let radius: CGFloat = 260
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(stroke)
    context.strokeEllipse(in: CGRect(
        x: 512 - radius + stroke / 2, y: 512 - radius + stroke / 2,
        width: radius * 2 - stroke, height: radius * 2 - stroke))

    context.beginPath()
    context.move(to: CGPoint(x: 512, y: 512))
    context.addArc(
        center: CGPoint(x: 512, y: 512), radius: radius - stroke - gap,
        startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    context.closePath()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()

    guard let image = context.makeImage() else { throw IconError.bitmap }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.png
    }
    return png
}

func makeIcon(in directory: URL) throws {
    let iconset = directory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            let filename = "icon_\(points)x\(points)\(suffix).png"
            try drawIcon(pixels: points * scale).write(to: iconset.appendingPathComponent(filename))
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "-c", "icns", iconset.path, "-o", directory.appendingPathComponent("AppIcon.icns").path,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconError.iconutil(process.terminationStatus)
    }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/make-icon.swift <outDir>\n".utf8))
    throw IconError.usage
}
try makeIcon(in: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
