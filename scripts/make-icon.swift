// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repository root)

import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    // macOS icons leave a margin around the rounded square.
    let inset = size * 0.1
    let square = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let background = NSBezierPath(roundedRect: square, xRadius: square.width * 0.225, yRadius: square.width * 0.225)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.56, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.33, blue: 0.86, alpha: 1),
    ])!.draw(in: background, angle: -90)

    func symbol(_ name: String, pointSize: CGFloat, colors: [NSColor]) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    if let envelope = symbol("envelope.fill", pointSize: size * 0.40, colors: [.white]) {
        let s = envelope.size
        envelope.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + size * 0.02,
                                 width: s.width, height: s.height))
    }
    if let badge = symbol("checkmark.circle.fill", pointSize: size * 0.20,
                          colors: [.white, NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)]) {
        let s = badge.size
        let origin = NSPoint(x: size * 0.60, y: size * 0.21)
        // White ring behind the badge so it reads against the envelope.
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(origin: origin, size: s).insetBy(dx: -size * 0.012, dy: -size * 0.012)).fill()
        badge.draw(in: NSRect(origin: origin, size: s))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("MailRem-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let data = drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? fileManager.removeItem(at: iconset)

if iconutil.terminationStatus == 0 {
    print("Wrote Resources/AppIcon.icns")
} else {
    print("iconutil failed")
    exit(1)
}
