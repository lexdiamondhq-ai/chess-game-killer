import SwiftUI
import UIKit

/// An arrow on a board as outlines. A coach's arrow runs straight; an analysis arrow is a flight
/// path, bowing to one side as it goes and, on the 3D board, rising off the stone and landing on
/// the target. Solid, it is three outlines: the rounded tail, the shaft as one strip (its left side
/// from tail to head, then its right side back), and the head, always last. Dashed, the shaft is a
/// row of short bars. The shaft reaches a hair into the head, so no seam shows where they meet;
/// `seamless`, the parts only touch (a half-round tail, the shaft stopping at the head's base),
/// so a see-through arrow drawn part by part (the 3D board) shows no darker overlaps.
/// Lengths are in squares, scaled by `unit`. The flat boards and the 3D board draw from it.
enum ArrowOutline {
    struct Proportions: Hashable {
        var shaft: CGFloat
        var headLength: CGFloat
        var headWidth: CGFloat
        /// How far past the start square's middle the tail begins.
        var startInset: CGFloat
        /// How far short of the target's middle the tip stops.
        var tipInset: CGFloat
        /// How far the path bows out to the side at its middle, as a share of its length.
        var bow: CGFloat = 0
        /// How high it rises over the board at its middle on the 3D board, as a share of its length.
        var rise: CGFloat = 0
        /// Drawn dashed, the shaft is a row of round dots in place of bars.
        var dotted = false

        /// The coach's arrows (lessons, drills, puzzles): straight.
        static func coach(dashed: Bool) -> Proportions {
            Proportions(shaft: dashed ? 0.12 : 0.15, headLength: 0.4, headWidth: 0.46, startInset: 0.2, tipInset: 0.1)
        }

        /// The analysis arrows, flight paths: the best move fuller and higher, the next best slimmer.
        /// They bow only gently (Alex: "not the curved so much").
        static func analysis(best: Bool) -> Proportions {
            Proportions(shaft: best ? 0.14 : 0.1, headLength: best ? 0.32 : 0.27, headWidth: best ? 0.46 : 0.34,
                        startInset: 0.24, tipInset: 0.08, bow: best ? 0.08 : 0.06, rise: best ? 0.22 : 0.16,
                        dotted: !best)
        }
    }

    /// The path's three points: where the tail starts, the curve's pull to the side, and the tip.
    /// The path bows to the left of its travel as `unit`'s coordinates see it; `side` -1 bows it the
    /// other way (the 3D board's y runs up, the screen's down).
    static func path(from start: CGPoint, to end: CGPoint, unit: CGFloat, proportions p: Proportions,
                     side: CGFloat = 1) -> (tail: CGPoint, pull: CGPoint, tip: CGPoint) {
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001 * unit)
        let u = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let tail = CGPoint(x: start.x + u.x * p.startInset * unit, y: start.y + u.y * p.startInset * unit)
        let tip = CGPoint(x: end.x - u.x * p.tipInset * unit, y: end.y - u.y * p.tipInset * unit)
        let span = hypot(tip.x - tail.x, tip.y - tail.y)
        // A quadratic curve's middle sits halfway to its pull.
        let reach = 2 * p.bow * span * side
        let pull = CGPoint(x: (tail.x + tip.x) / 2 - u.y * reach, y: (tail.y + tip.y) / 2 + u.x * reach)
        return (tail, pull, tip)
    }

    /// Where the arrow's tail starts and where its tip is.
    static func ends(from start: CGPoint, to end: CGPoint, unit: CGFloat, proportions p: Proportions)
        -> (tail: CGPoint, tip: CGPoint) {
        let path = path(from: start, to: end, unit: unit, proportions: p)
        return (path.tail, path.tip)
    }

    private static func point(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: CGFloat) -> CGPoint {
        let s = 1 - t
        return CGPoint(x: s * s * a.x + 2 * s * t * b.x + t * t * c.x, y: s * s * a.y + 2 * s * t * b.y + t * t * c.y)
    }

    static func outlines(from start: CGPoint, to end: CGPoint, unit: CGFloat, dashed: Bool,
                         proportions p: Proportions, side: CGFloat = 1, seamless: Bool = false) -> [[CGPoint]] {
        let (tail, pull, tip) = path(from: start, to: end, unit: unit, proportions: p, side: side)
        // The head points along the curve as it lands.
        let lean = CGPoint(x: tip.x - pull.x, y: tip.y - pull.y)
        let leanLength = max(hypot(lean.x, lean.y), 0.000001)
        let u = CGPoint(x: lean.x / leanLength, y: lean.y / leanLength), n = CGPoint(x: -u.y, y: u.x)
        let base = CGPoint(x: tip.x - u.x * p.headLength * unit, y: tip.y - u.y * p.headLength * unit)
        let half = p.headWidth / 2 * unit
        let head = [CGPoint(x: base.x + n.x * half, y: base.y + n.y * half), tip,
                    CGPoint(x: base.x - n.x * half, y: base.y - n.y * half)]
        // The shaft follows the curve to a hair inside the head's base.
        let reach = seamless && !dashed ? 0 : 0.03 * unit
        let into = CGPoint(x: base.x + u.x * reach, y: base.y + u.y * reach)
        let curved = p.bow > 0
        let steps = curved ? 28 : 1
        // The curve from the tail to the head, solved for where it meets the head's base.
        let stop = curved ? closest(to: into, tail, pull, tip) : 1
        let spine: [CGPoint] = curved
            ? (0...steps).map { point(tail, pull, tip, stop * CGFloat($0) / CGFloat(steps)) }
            : [tail, into]
        let width = p.shaft * unit
        func normal(at i: Int) -> CGPoint {
            let a = spine[max(i - 1, 0)], b = spine[min(i + 1, spine.count - 1)]
            let d = max(hypot(b.x - a.x, b.y - a.y), 0.000001)
            return CGPoint(x: -(b.y - a.y) / d, y: (b.x - a.x) / d)
        }
        func edgePoint(_ i: Int, _ sign: CGFloat) -> CGPoint {
            let m = normal(at: i)
            return CGPoint(x: spine[i].x + m.x * width / 2 * sign, y: spine[i].y + m.y * width / 2 * sign)
        }
        if dashed {
            // Bars along the spine, by distance.
            var lengths: [CGFloat] = [0]
            for i in 1..<spine.count {
                lengths.append(lengths[i - 1] + hypot(spine[i].x - spine[i - 1].x, spine[i].y - spine[i - 1].y))
            }
            let total = lengths.last ?? 0
            func at(_ d: CGFloat) -> (CGPoint, CGPoint) {
                let i = max(1, lengths.firstIndex { $0 >= d } ?? spine.count - 1)
                let t = (d - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], 0.000001)
                let a = spine[i - 1], b = spine[i]
                let d2 = max(hypot(b.x - a.x, b.y - a.y), 0.000001)
                return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                        CGPoint(x: -(b.y - a.y) / d2 * width / 2, y: (b.x - a.x) / d2 * width / 2))
            }
            if p.dotted {
                // Round dots, a little wider than the shaft, a dot's width apart, the last clear of the head.
                let radius = width * 0.62, spacing = radius * 3.2
                var dots: [[CGPoint]] = []
                var d = radius
                while d + radius <= total - 0.05 * unit {
                    dots.append(circle(at(d).0, radius: radius, sides: 16))
                    d += spacing
                }
                return dots + [head]
            }
            var bars: [[CGPoint]] = []
            let dash = p.shaft * 1.6 * unit, gap = p.shaft * 1.1 * unit
            var d: CGFloat = 0
            while d < total - 0.04 * unit {
                let e = min(d + dash, total - 0.03 * unit)
                let (a, m1) = at(d), (b, m2) = at(e)
                bars.append([CGPoint(x: a.x + m1.x, y: a.y + m1.y), CGPoint(x: b.x + m2.x, y: b.y + m2.y),
                             CGPoint(x: b.x - m2.x, y: b.y - m2.y), CGPoint(x: a.x - m1.x, y: a.y - m1.y)])
                d = e + gap
            }
            return bars + [head]
        }
        let strip = spine.indices.map { edgePoint($0, 1) } + spine.indices.reversed().map { edgePoint($0, -1) }
        guard seamless else { return [circle(tail, radius: width / 2), strip, head] }
        // The tail's back half only, from the shaft's one side round to the other.
        let m = normal(at: 0)
        let back = CGPoint(x: -m.y, y: m.x)
        let cap = (0...14).map { i -> CGPoint in
            let angle = CGFloat.pi * CGFloat(i) / 14
            return CGPoint(x: tail.x + (m.x * cos(angle) + back.x * sin(angle)) * width / 2,
                           y: tail.y + (m.y * cos(angle) + back.y * sin(angle)) * width / 2)
        }
        return [cap, strip, head]
    }

    /// Where along the curve (0 to 1) it comes closest to `target`.
    private static func closest(to target: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        var best: CGFloat = 1, nearest = CGFloat.infinity
        for i in 0...200 {
            let t = CGFloat(i) / 200
            let q = point(a, b, c, t)
            let d = hypot(q.x - target.x, q.y - target.y)
            if d < nearest { nearest = d; best = t }
        }
        return best
    }

    /// How high a point of the arrow rises over the board, in `unit`s: nothing at its ends, the
    /// most at its middle.
    static func height(of point: CGPoint, tail: CGPoint, tip: CGPoint, proportions p: Proportions) -> CGFloat {
        let t = along(point, tail: tail, tip: tip)
        return 4 * t * (1 - t) * p.rise * hypot(tip.x - tail.x, tip.y - tail.y)
    }

    /// An outline grown outward by `distance` all round: the white edge under an arrow, where a
    /// stroke can't be drawn (the 3D board). Corners are mitred, short of a long spike at the tip.
    static func grown(_ outline: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        let count = outline.count
        guard count >= 3 else { return outline }
        // Shoelace: positive for counterclockwise in a y-up plane.
        var area: CGFloat = 0
        for i in 0..<count {
            let a = outline[i], b = outline[(i + 1) % count]
            area += a.x * b.y - b.x * a.y
        }
        let outward: CGFloat = area >= 0 ? 1 : -1
        func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.000001)
            return CGPoint(x: dy / length * outward, y: -dx / length * outward)
        }
        return (0..<count).map { i in
            let previous = outline[(i - 1 + count) % count], here = outline[i], next = outline[(i + 1) % count]
            let n1 = normal(previous, here), n2 = normal(here, next)
            var mx = n1.x + n2.x, my = n1.y + n2.y
            let length = hypot(mx, my)
            guard length > 0.000001 else { return CGPoint(x: here.x + n1.x * distance, y: here.y + n1.y * distance) }
            mx /= length
            my /= length
            let reach = distance / max(mx * n1.x + my * n1.y, 0.35)
            return CGPoint(x: here.x + mx * reach, y: here.y + my * reach)
        }
    }

    /// A circle as a polygon: the rounded tail, the landing ring.
    static func circle(_ center: CGPoint, radius: CGFloat, sides: Int = 28) -> [CGPoint] {
        (0..<sides).map { i in
            let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(sides)
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    /// How far along the arrow, 0 at the tail and 1 at the tip, a point lies: where it is in
    /// the arrow's color fade.
    static func along(_ point: CGPoint, tail: CGPoint, tip: CGPoint) -> CGFloat {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let length2 = max(dx * dx + dy * dy, 0.000001)
        return min(max(((point.x - tail.x) * dx + (point.y - tail.y) * dy) / length2, 0), 1)
    }
}

/// The colors of the analysis arrows on every board, Dusk Blue (Alex's pick, 2026-11-07): a soft
/// dusty blue for the best move, like a winter sky, and pearl for the next best, slimmer and
/// quieter. Each brightens toward its tail and is see-through, as tinted glass with a soft white
/// rim (`seeThrough`, `rim`), so the squares and pieces show through it.
enum ArrowColors {
    static let best: UInt32 = 0x7F9CC1
    static let bestTail: UInt32 = 0xD6E2F0
    static let next: UInt32 = 0xC7C1B7
    static let nextTail: UInt32 = 0xEFECE6
    /// How solid the analysis arrows are: the best move's, then the next best's.
    static let seeThrough: (best: Double, next: Double) = (0.66, 0.5)
    /// How strong their white rim is, against the arrow's own strength.
    static let rim: Double = 0.55
    /// The coach's arrows' thin white edge, which keeps them crisp on a light square, a dark one
    /// and over a piece.
    static let edge: UInt32 = 0xFFFFFF

    /// The color an arrow brightens to at its tail: the analysis pairs' own, or for any other
    /// color, that color lifted toward white.
    static func tail(of hex: UInt32) -> UInt32 {
        switch hex {
        case best: return bestTail
        case next: return nextTail
        default:
            func lift(_ shift: UInt32) -> UInt32 {
                let channel = Double((hex >> shift) & 0xFF)
                return UInt32((channel + (255 - channel) * 0.38).rounded()) << shift
            }
            return lift(16) | lift(8) | lift(0)
        }
    }

    static func hex(of color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}

/// An arrow drawn crisp: an even color that brightens toward its tail, a fine edge, and a soft
/// shadow under it. An analysis arrow flies: it bows to the side, its shadow lies straight on the
/// board beneath it, and the best move's lands on a ring.
struct CrispArrow: View {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat
    let dashed: Bool
    let color: Color
    let proportions: ArrowOutline.Proportions
    /// Neon looks: a glow of the arrow's color in place of the edge and shadow.
    var glow: Color? = nil
    /// The fine line round it.
    var edge: Color = .white
    /// Lands on a ring on its target square.
    var landing = false
    /// How solid the arrow is; under 1 it is see-through, as tinted glass.
    var opacity: Double = 1
    /// How strong its edge is, against the arrow's own strength.
    var rim: Double = 1

    var body: some View {
        let p = proportions
        let outlines = ArrowOutline.outlines(from: from, to: to, unit: squareSize, dashed: dashed, proportions: p)
        let (tail, tip) = ArrowOutline.ends(from: from, to: to, unit: squareSize, proportions: p)
        // Each part on its own, so the tail's round cap can't cut a hole in the shaft.
        let parts = outlines.map { outline in
            Path { path in
                guard let first = outline.first else { return }
                path.move(to: first)
                for point in outline.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
        }
        let tailColor = Color(hex: ArrowColors.tail(of: ArrowColors.hex(of: color)))
        let fade = Gradient(colors: [tailColor, color])
        let line = max(0.75, squareSize * 0.022)
        Canvas { context, _ in
            let clear = opacity < 1
            if p.bow > 0 && glow == nil {
                // The shadow on the board below the flight.
                var ground = context
                ground.addFilter(.blur(radius: squareSize * 0.07))
                ground.stroke(Path { $0.move(to: tail); $0.addLine(to: tip) },
                              with: .color(.black.opacity(clear ? 0.14 * opacity : 0.22)),
                              style: StrokeStyle(lineWidth: p.shaft * squareSize * 0.8, lineCap: .round))
            }
            if landing {
                let ring = CGRect(x: to.x - squareSize * 0.33, y: to.y - squareSize * 0.14,
                                  width: squareSize * 0.66, height: squareSize * 0.36)
                context.fill(Path(ellipseIn: ring), with: .color(color.opacity(0.18)))
                context.stroke(Path(ellipseIn: ring), with: .color(tailColor.opacity(min(1, opacity + 0.2))),
                               lineWidth: squareSize * 0.03)
            }
            if let glow {
                context.addFilter(.shadow(color: glow.opacity(0.85), radius: squareSize * 0.1))
            } else if !clear {
                // A see-through arrow has no shadow: it would show through it.
                context.addFilter(.shadow(color: .black.opacity(0.35), radius: squareSize * 0.03, y: squareSize * 0.015))
            }
            if glow == nil {
                // The edge only round the outside, so it doesn't show through a see-through arrow.
                var rimmed = context
                rimmed.opacity = rim * opacity
                rimmed.drawLayer { layer in
                    for part in parts {
                        layer.stroke(part, with: .color(edge), style: StrokeStyle(lineWidth: line * 2, lineJoin: .round))
                    }
                    layer.blendMode = .destinationOut
                    for part in parts { layer.fill(part, with: .color(.black)) }
                }
            }
            // The parts together in one layer, so where they overlap is no darker.
            var body = context
            body.opacity = opacity
            body.drawLayer { layer in
                for part in parts {
                    layer.fill(part, with: .linearGradient(fade, startPoint: tail, endPoint: tip))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
