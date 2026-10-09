import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the mascot for the README: a looping GIF (hop, then a blink) and two still PNGs.
@MainActor
func renderReadmeAssets(to dir: String) -> Bool {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let cream = Color(red: 0.984, green: 0.953, blue: 0.925)

    func image(_ still: Mascot.Still, scale: CGFloat, background: Bool) -> CGImage? {
        let view = ZStack {
            if background { cream }
            Mascot(happyUntil: .distantPast, scale: scale, still: still)
        }.frame(width: 64 * scale + (background ? 48 : 0), height: 56 * scale + (background ? 40 : 0))
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.cgImage
    }
    func writePNG(_ img: CGImage?, _ name: String) -> Bool {
        guard let img, let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/" + name) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, img, nil)
        return CGImageDestinationFinalize(d)
    }

    // Loop length matches the bob period (2*pi/2.2 s) so the GIF loops seamlessly.
    let loop = 2 * Double.pi / 2.2, fps = 20.0, n = Int(loop * fps)
    guard let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/mascot.gif") as CFURL, UTType.gif.identifier as CFString, n, nil) else { return false }
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<n {
        let time = Double(i) / fps
        let hopStart = 0.35, hopLen = 1.6
        let left = (time >= hopStart && time < hopStart + hopLen) ? hopStart + hopLen - time : 0
        let gaze = CGSize(width: 3.4 * sin(time * 2.2), height: 0.6)
        let t = time + (4.3 - 2.4) // the blink (t mod 4.3 < 0.13) lands at 2.4 s
        guard let img = image(.init(t: t, left: left, gaze: gaze), scale: 3, background: true) else { return false }
        CGImageDestinationAddImage(gif, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(gif) else { return false }

    return writePNG(image(.init(t: 0.6, left: 0, gaze: CGSize(width: 2, height: 0.5)), scale: 4, background: false), "mascot.png")
        && writePNG(image(.init(t: 0.6, left: 1.0, gaze: .zero), scale: 4, background: false), "mascot-happy.png")
}

/// The .dmg window background (660x520 pt; Finder's title bar and status bars cover part of it, so everything
/// that matters stays in the top ~380 pt), written as 1x and 2x PNGs for `tiffutil` to merge.
/// The app and Applications icons sit at (170, 195) and (490, 195), see scripts/dmg-settings.py.
@MainActor
func renderDmgBackground(to dir: String) -> Bool {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let view = ZStack {
        LinearGradient(colors: [Color(red: 0.60, green: 0.62, blue: 0.95), Color(red: 0.55, green: 0.48, blue: 0.92)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 6) {
            Text("Claude Accounts").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("Drag the app onto Applications").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }.position(x: 330, y: 66)
        HStack(spacing: 0) {
            ForEach(0..<5) { _ in Circle().fill(.white.opacity(0.7)).frame(width: 6, height: 6).padding(.horizontal, 5) }
            Image(systemName: "chevron.right").font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.9)).padding(.leading, 4)
        }.position(x: 330, y: 195)
        Mascot(happyUntil: .distantPast, scale: 1.0, still: .init(t: 0.6, left: 0, gaze: CGSize(width: 0, height: -1.5)))
            .position(x: 330, y: 312)
    }.frame(width: 660, height: 520)

    for (scale, name, dpi) in [(1.0, "background.png", 72.0), (2.0, "background@2x.png", 144.0)] {
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let img = r.cgImage,
              let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/" + name) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, img, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { return false }
    }
    return true
}
