import SwiftUI

/// An arrow on a board as outlines: one outline for a solid arrow (shaft, head and round tail
/// together, so nothing overlaps itself and it fills in one even color), or a row of short bars
/// and the head for a dashed one. Lengths are in squares, scaled by `unit`; the last outline is
/// always the head. The flat boards and the 3D board draw their arrows from it.
enum ArrowOutline {
    struct Proportions: Equatable {
        var shaft: CGFloat
        var headLength: CGFloat
        var headWidth: CGFloat
        /// How far past the start square's middle the tail begins.
        var startInset: CGFloat
        /// How far short of the target's middle the tip stops.
        var tipInset: CGFloat

        /// The coach's arrows (lessons, drills, puzzles).
        static func coach(dashed: Bool) -> Proportions {
            Proportions(shaft: dashed ? 0.12 : 0.15, headLength: 0.4, headWidth: 0.46, startInset: 0.2, tipInset: 0.1)
        }

        /// The analysis arrows: the best move bold, the next best lighter.
        static func analysis(best: Bool) -> Proportions {
            Proportions(shaft: best ? 0.17 : 0.12, headLength: best ? 0.42 : 0.38, headWidth: best ? 0.5 : 0.44,
                        startInset: 0.18, tipInset: 0.08)
        }
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
        let tail = point(start, along: p.startInset, across: 0)
        let tip = point(end, along: -p.tipInset, across: 0)
        let base = point(tip, along: -p.headLength, across: 0)
        let shaftLength = max(0, length / unit - p.startInset - p.tipInset - p.headLength)
        let head = [point(base, along: 0, across: p.headWidth / 2), tip, point(base, along: 0, across: -p.headWidth / 2)]
        if dashed {
            var outlines: [[CGPoint]] = []
            let dash = shaft * 1.6
            let gap = shaft * 1.1
            var at: CGFloat = 0
            while at < shaftLength - 0.01 {
                let stop = min(at + dash, shaftLength)
                outlines.append([
                    point(tail, along: at, across: shaft / 2), point(tail, along: stop, across: shaft / 2),
                    point(tail, along: stop, across: -shaft / 2), point(tail, along: at, across: -shaft / 2),
                ])
                at = stop + gap
            }
            return outlines + [head]
        }
        // Down the left side, round the head, back up the right side and round the tail.
        var outline = [point(tail, along: 0, across: shaft / 2), point(base, along: 0, across: shaft / 2),
                       head[0], head[1], head[2],
                       point(base, along: 0, across: -shaft / 2), point(tail, along: 0, across: -shaft / 2)]
        let steps = 10
        for step in 1..<steps {
            let angle = CGFloat.pi * CGFloat(step) / CGFloat(steps)
            outline.append(point(tail, along: -sin(angle) * shaft / 2, across: -cos(angle) * shaft / 2))
        }
        return [outline]
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
}

/// The colors of the analysis arrows on every board: a clear sapphire that stands apart from
/// wood, stone, ivory, ebony and gold, the next best a paler one, both edged in white.
enum ArrowColors {
    static let best: UInt32 = 0x2F6FF5
    static let next: UInt32 = 0x6E9BFA
    /// The thin edge that keeps an arrow crisp on a light square, a dark one and over a piece.
    static let edge: UInt32 = 0xFFFFFF
}

/// An arrow drawn crisp: one even, solid color, a thin white edge, and a soft shadow under it.
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
        let outlines = ArrowOutline.outlines(from: from, to: to, unit: squareSize, dashed: dashed, proportions: proportions)
        let shape = Path { path in
            for outline in outlines {
                guard let first = outline.first else { continue }
                path.move(to: first)
                for point in outline.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
        }
        let edge = max(1, squareSize * 0.035)
        ZStack {
            if glow == nil {
                shape.stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: edge * 2, lineJoin: .round))
            }
            shape.fill(color)
        }
        .shadow(color: glow?.opacity(0.85) ?? .black.opacity(0.28), radius: glow == nil ? squareSize * 0.03 : squareSize * 0.1,
                y: glow == nil ? squareSize * 0.015 : 0)
    }
}
