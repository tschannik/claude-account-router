import AppKit

/// Badge colour, derived from the account name so it is stable across launches and machines.
func badgeColorHex(_ name: String) -> UInt32 {
    let palette: [UInt32] = [0x4f46e5, 0x0d9488, 0xd97706, 0xdb2777, 0x0891b2, 0x65a30d, 0xc026d3, 0xdc2626]
    return palette[Int(name.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value } % UInt32(palette.count))]
}

func nsColor(_ rgb: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1)
}

/// Draws one coloured letter circle into rect `r` (used in the window and on launcher icons).
func drawBadge(letter: String, rgb: UInt32, in r: NSRect, ring: Bool) {
    let d = r.width
    var inner = r
    if ring {
        NSColor.white.setFill(); NSBezierPath(ovalIn: r).fill()
        inner = r.insetBy(dx: d * 0.07, dy: d * 0.07)
    }
    nsColor(rgb).setFill(); NSBezierPath(ovalIn: inner).fill()
    let str = NSAttributedString(string: letter.prefix(1).uppercased(), attributes: [
        .font: NSFont.systemFont(ofSize: d * 0.55, weight: .bold), .foregroundColor: NSColor.white])
    let sz = str.size()
    str.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
}

/// Renders `draw(size)` at all icon sizes and assembles an .icns with iconutil.
func writeIcns(to out: String, draw: (CGFloat) -> Void) -> Bool {
    let set = NSTemporaryDirectory() + "ca-icon-\(getpid()).iconset"
    try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: set) }
    let sizes: [(Int, String)] = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
        (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]
    for (px, name) in sizes {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        draw(CGFloat(px))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))) != nil else { return false }
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", "-o", out, set]
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// Claude's own icon with a coloured letter badge in the corner, for per-account launchers.
func writeBadgedIcon(base: String, to out: String, letter: String, rgb: UInt32) -> Bool {
    guard let img = NSImage(contentsOfFile: base) else { return false }
    return writeIcns(to: out) { s in
        img.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        let d = s * 0.48, pad = s * 0.02
        drawBadge(letter: letter, rgb: rgb, in: NSRect(x: s - d - pad, y: pad, width: d, height: d), ring: true)
    }
}

/// The app's own icon: two overlapping account circles on an indigo tile.
func writeAppIcon(to out: String) -> Bool {
    writeIcns(to: out) { s in
        let tile = NSRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84)
        let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.19, yRadius: s * 0.19)
        NSGradient(starting: nsColor(0x6366f1), ending: nsColor(0x3730a3))?.draw(in: path, angle: -60)
        let d = s * 0.34
        let y = s / 2 - d / 2
        nsColor(0x0d9488).setFill(); NSBezierPath(ovalIn: NSRect(x: s * 0.5 - d * 0.88, y: y, width: d, height: d)).fill()
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: s * 0.5 - d * 0.12, y: y, width: d, height: d)).fill()
    }
}
