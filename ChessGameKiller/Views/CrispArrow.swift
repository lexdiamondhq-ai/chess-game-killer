import SwiftUI
import UIKit

/// An arrow on a board as outlines: the shaft (one bar, or a row of short bars when dashed) and
/// the head, each a simple convex shape, the head always last. They meet without overlapping, so
/// the arrow fills in one even color, lighter toward its tail. At the tail sits a white-ringed
/// dot, where the move starts. Lengths are in squares, scaled by `unit`. The flat boards and the
/// 3D board draw their arrows from it.
enum ArrowOutline {
    struct Proportions: Hashable {
        var shaft: CGFloat
        var headLength: CGFloat
        var headWidth: CGFloat
        /// How far past the start square's middle the tail begins, at the dot.
        var startInset: CGFloat
        /// How far short of the target's middle the tip stops.
        var tipInset: CGFloat
        /// The dot's radius, white ring and all.
        var dot: CGFloat

        /// The coach's arrows (lessons, drills, puzzles).
        static func coach(dashed: Bool) -> Proportions {
            Proportions(shaft: dashed ? 0.14 : 0.18, headLength: 0.44, headWidth: 0.54, startInset: 0.3, tipInset: 0.08,
                        dot: dashed ? 0.1 : 0.12)
        }

        /// The analysis arrows: the best move bold, the next best lighter.
        static func analysis(best: Bool) -> Proportions {
            Proportions(shaft: best ? 0.23 : 0.16, headLength: best ? 0.5 : 0.42, headWidth: best ? 0.66 : 0.52,
                        startInset: 0.3, tipInset: 0.06, dot: best ? 0.14 : 0.11)
        }
    }

    /// Where the arrow starts (the dot's middle) and where its tip is.
    static func ends(from start: CGPoint, to end: CGPoint, unit: CGFloat, proportions p: Proportions)
        -> (tail: CGPoint, tip: CGPoint) {
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001 * unit)
        let u = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        return (CGPoint(x: start.x + u.x * p.startInset * unit, y: start.y + u.y * p.startInset * unit),
                CGPoint(x: end.x - u.x * p.tipInset * unit, y: end.y - u.y * p.tipInset * unit))
    }

    static func outlines(from start: CGPoint, to end: CGPoint, unit: CGFloat, dashed: Bool,
                         proportions p: Proportions) -> [[CGPoint]] {
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001 * unit)
        let u = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        // Across the arrow, to its left.
        let n = CGPoint(x: -u.y, y: u.x)
        func point(_ origin: CGPoint, along: CGFloat, across: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (u.x * along + n.x * across) * unit, y: origin.y + (u.y * along + n.y * across) * unit)
        }
        let shaft = p.shaft
        let (tail, tip) = ends(from: start, to: end, unit: unit, proportions: p)
        let base = point(tip, along: -p.headLength, across: 0)
        let shaftLength = max(0, length / unit - p.startInset - p.tipInset - p.headLength)
        let head = [point(base, along: 0, across: p.headWidth / 2), tip, point(base, along: 0, across: -p.headWidth / 2)]
        func bar(_ from: CGFloat, _ to: CGFloat) -> [CGPoint] {
            [point(tail, along: from, across: shaft / 2), point(tail, along: to, across: shaft / 2),
             point(tail, along: to, across: -shaft / 2), point(tail, along: from, across: -shaft / 2)]
        }
        guard dashed else {
            return (shaftLength > 0 ? [bar(0, shaftLength)] : []) + [head]
        }
        var outlines: [[CGPoint]] = []
        // The first dash starts past the dot, so the dot stands clear.
        var at = p.dot + shaft * 0.5
        let dash = shaft * 1.6
        let gap = shaft * 1.1
        while at < shaftLength - 0.01 {
            let stop = min(at + dash, shaftLength)
            outlines.append(bar(at, stop))
            at = stop + gap
        }
        return outlines + [head]
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

    /// A circle as a polygon, for the dot on the 3D board.
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

/// The colors of the arrows on every board. The analysis arrows are a deep royal blue that
/// brightens to sky blue toward the tail, the next best a softer pair; both stand apart from
/// wood, stone, ivory, ebony and gold, and both are edged in white.
enum ArrowColors {
    static let best: UInt32 = 0x1F4FE0
    static let bestTail: UInt32 = 0x4AB2FF
    static let next: UInt32 = 0x5A86EE
    static let nextTail: UInt32 = 0x9FD0FF
    /// The thin edge that keeps an arrow crisp on a light square, a dark one and over a piece,
    /// and the dot's ring.
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

/// An arrow drawn crisp: an even color that brightens toward its tail, a thin white edge, a
/// white-ringed dot where the move starts, and a soft shadow under it all.
struct CrispArrow: View {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat
    let dashed: Bool
    let color: Color
    let proportions: ArrowOutline.Proportions
    /// Neon looks: a glow of the arrow's color in place of the edge and shadow.
    var glow: Color? = nil

    var body: some View {
        let p = proportions
        let outlines = ArrowOutline.outlines(from: from, to: to, unit: squareSize, dashed: dashed, proportions: p)
        let (tail, tip) = ArrowOutline.ends(from: from, to: to, unit: squareSize, proportions: p)
        let shape = Path { path in
            for outline in outlines {
                guard let first = outline.first else { continue }
                path.move(to: first)
                for point in outline.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
        }
        let tailColor = Color(hex: ArrowColors.tail(of: ArrowColors.hex(of: color)))
        let fade = Gradient(colors: [tailColor, color])
        let edge = max(1, squareSize * 0.03)
        let dot = p.dot * squareSize
        let ring = Path(ellipseIn: CGRect(x: tail.x - dot, y: tail.y - dot, width: dot * 2, height: dot * 2))
        let core = dot * 0.6
        let center = Path(ellipseIn: CGRect(x: tail.x - core, y: tail.y - core, width: core * 2, height: core * 2))
        Canvas { context, _ in
            // The shadow (or a neon look's glow) falls from the arrow as one shape.
            if let glow {
                context.addFilter(.shadow(color: glow.opacity(0.85), radius: squareSize * 0.1))
            } else {
                context.addFilter(.shadow(color: .black.opacity(0.32), radius: squareSize * 0.035, y: squareSize * 0.018))
            }
            context.drawLayer { layer in
                if glow == nil {
                    layer.stroke(shape, with: .color(.white.opacity(0.95)),
                                 style: StrokeStyle(lineWidth: edge * 2, lineJoin: .round))
                }
                layer.fill(shape, with: .linearGradient(fade, startPoint: tail, endPoint: tip))
                layer.fill(ring, with: .color(.white))
                layer.fill(center, with: .color(tailColor))
            }
        }
        .allowsHitTesting(false)
    }
}
