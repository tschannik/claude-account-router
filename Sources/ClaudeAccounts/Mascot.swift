import AppKit
import SwiftUI

/// A small terracotta bot that bobs, blinks, follows the mouse pointer with its eyes and hops for joy
/// when an account starts (or when poked).
struct Mascot: View {
    var happyUntil: Date
    var scale: CGFloat = 1
    /// A frozen frame (idle clock, seconds of hop left, gaze) for README art; nil = live and animated.
    var still: Still? = nil

    struct Still { var t: Double; var left: Double; var gaze: CGSize }

    private let w: CGFloat = 64, h: CGFloat = 56
    private let fur = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757, Claude terracotta
    private let bodyDark = Color(red: 0.76, green: 0.38, blue: 0.27)
    private let ink = Color(red: 0.17, green: 0.11, blue: 0.09)

    var body: some View {
        Group {
            if let s = still {
                Canvas { ctx, _ in draw(&ctx, t: s.t, left: s.left, gaze: s.gaze) }
            } else {
                GeometryReader { g in
                    TimelineView(.animation) { tl in
                        let frame = g.frame(in: .global)
                        Canvas { ctx, _ in
                            draw(&ctx, t: tl.date.timeIntervalSinceReferenceDate,
                                 left: happyUntil.timeIntervalSince(tl.date), gaze: look(frame: frame))
                        }
                    }
                }
            }
        }
        .frame(width: w * scale, height: h * scale)
    }

    private func look(frame: CGRect) -> CGSize {
        guard let win = NSApp.windows.first(where: { $0.isVisible && $0.title == "Claude Accounts" }) ?? NSApp.keyWindow else { return .zero }
        let m = NSEvent.mouseLocation
        let cx = win.frame.minX + frame.midX, cy = win.frame.maxY - frame.midY
        let dx = m.x - cx, dy = -(m.y - cy)
        let len = max(hypot(dx, dy), 1), k = min(1, len / 160)
        return CGSize(width: dx / len * k * 3.4, height: dy / len * k * 2.4)
    }

    private func draw(_ ctx: inout GraphicsContext, t: Double, left: Double, gaze: CGSize) {
        ctx.scaleBy(x: scale, y: scale)
        let happy = left > 0
        var lift = sin(t * 2.2) * 1.2                           // idle bob
        if happy { lift -= abs(sin((1.6 - left) / 1.6 * .pi * 3)) * 9 } // hop

        // ground shadow
        let sh = 1 - min(0.35, max(0, -lift) / 30)
        ctx.fill(Path(ellipseIn: CGRect(x: 32 - 17 * sh, y: 49, width: 34 * sh, height: 5)), with: .color(.black.opacity(0.12)))

        ctx.translateBy(x: 0, y: lift)

        // legs
        for x in [18.0, 26.0, 35.0, 43.0] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: 40, width: 5, height: 9), cornerRadius: 2), with: .color(bodyDark))
        }
        // arms (raised while happy)
        let armY: CGFloat = happy ? 14 : 24
        ctx.fill(Path(roundedRect: CGRect(x: 2, y: armY, width: 10, height: 8), cornerRadius: 4), with: .color(bodyDark))
        ctx.fill(Path(roundedRect: CGRect(x: 52, y: armY, width: 10, height: 8), cornerRadius: 4), with: .color(bodyDark))
        // body
        let bodyRect = CGRect(x: 8, y: 10, width: 48, height: 34)
        ctx.fill(Path(roundedRect: bodyRect, cornerRadius: 13),
                 with: .linearGradient(Gradient(colors: [fur.opacity(0.95), fur]), startPoint: CGPoint(x: 0, y: 10), endPoint: CGPoint(x: 0, y: 44)))
        // cheeks
        for x in [15.0, 49.0] { ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: 31, width: 8, height: 5)), with: .color(.white.opacity(0.22))) }

        // eyes
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.3)
        let blink = blinkPhase < 0.13 ? max(0.1, abs(blinkPhase - 0.065) / 0.065) : 1
        for x in [24.0, 40.0] {
            if happy {
                var p = Path()
                p.move(to: CGPoint(x: x - 5, y: 28))
                p.addQuadCurve(to: CGPoint(x: x + 5, y: 28), control: CGPoint(x: x, y: 19))
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            } else {
                let ew: CGFloat = 6, eh: CGFloat = 10 * blink
                let c = CGPoint(x: x + gaze.width, y: 26 + gaze.height)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - ew / 2, y: c.y - eh / 2, width: ew, height: eh)), with: .color(ink))
                if blink > 0.6 { ctx.fill(Path(ellipseIn: CGRect(x: c.x - 0.5, y: c.y - 3.5, width: 2.2, height: 2.2)), with: .color(.white.opacity(0.9))) }
            }
        }
        // mouth: small smile
        var m = Path()
        m.move(to: CGPoint(x: 29, y: 34)); m.addQuadCurve(to: CGPoint(x: 35, y: 34), control: CGPoint(x: 32, y: happy ? 40 : 37))
        ctx.stroke(m, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }
}
