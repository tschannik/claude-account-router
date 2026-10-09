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
