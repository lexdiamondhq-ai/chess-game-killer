import ChessKit
import SwiftUI

/// Where things are on a piece picture, read once from its outline: the top, the foot, the
/// solid span of each row, and (for a pawn) the narrow neck under its head. Unit coordinates.
struct PieceOutline {
    let top: CGFloat
    let bottom: CGFloat
    /// Left and right solid edge of each row, from the top; nil where the row is clear.
    let spans: [(CGFloat, CGFloat)?]

    var height: CGFloat { bottom - top }

    init?(mask: AlphaMask) {
        var spans: [(CGFloat, CGFloat)?] = []
        var first: Int?, last: Int?
        for y in 0..<mask.height {
            var left: Int?, right: Int?
            for x in 0..<mask.width where mask.alpha[y * mask.width + x] > 128 {
                if left == nil { left = x }
                right = x
            }
            if let left, let right {
                spans.append((CGFloat(left) / CGFloat(mask.width), CGFloat(right + 1) / CGFloat(mask.width)))
                if first == nil { first = y }
                last = y
            } else {
                spans.append(nil)
            }
        }
        guard let first, let last, last > first else { return nil }
        self.spans = spans
        top = CGFloat(first) / CGFloat(mask.height)
        bottom = CGFloat(last + 1) / CGFloat(mask.height)
    }

    /// The solid span at `y` (unit), or the nearest row's.
    func span(at y: CGFloat) -> (CGFloat, CGFloat) {
        let row = min(max(Int(y * CGFloat(spans.count)), 0), spans.count - 1)
        for distance in 0..<spans.count {
            for candidate in [row - distance, row + distance] where spans.indices.contains(candidate) {
                if let s = spans[candidate] { return s }
            }
        }
        return (0.4, 0.6)
    }

    /// The narrowest row between two fractions of the piece's height, measured from its top.
    func narrowest(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let count = CGFloat(spans.count)
        let from = Int((top + height * start) * count), to = Int((top + height * end) * count)
        var best: (row: Int, width: CGFloat)?
        for row in max(from, 0)...max(min(to, spans.count - 1), 0) {
            guard let s = spans[row] else { continue }
            let width = s.1 - s.0
            if best == nil || width < best!.width { best = (row, width) }
        }
        return (CGFloat(best?.row ?? from) + 0.5) / count
    }

    @MainActor private static var cache: [String: PieceOutline] = [:]

    @MainActor static func of(_ name: String) -> PieceOutline? {
        if let known = cache[name] { return known }
        guard let mask = SpriteMasks.shared.mask(named: name), let outline = PieceOutline(mask: mask) else { return nil }
        cache[name] = outline
        return outline
    }
}

/// The Heirloom marks drawn over a piece picture the same size as the picture, to be masked by it:
/// a warm patina, gold kintsugi seams down the body, a gold collar at a pawn's neck and small gold
/// notches along the front of the base.
struct HeirloomOverlay: View {
    let heirloom: Heirloom
    let imageName: String
    let piece: Piece

    static let gold = Color(red: 0.96, green: 0.78, blue: 0.38)
    private static let goldDeep = Color(red: 0.62, green: 0.42, blue: 0.12)

    var body: some View {
        let outline = PieceOutline.of(imageName)
        Canvas { context, size in
            guard let outline else { return }
            patina(&context, size: size)
            seams(&context, size: size, outline: outline)
            if heirloom.collar { collar(&context, size: size, outline: outline) }
            if heirloom.notches > 0 { notches(&context, size: size, outline: outline) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Ivory warms toward old bone; ebony takes a faint bronze sheen.
    private func patina(_ context: inout GraphicsContext, size: CGSize) {
        guard heirloom.patina > 0.02 else { return }
        var layer = context
        let rect = Path(CGRect(origin: .zero, size: size))
        if piece.color == .white {
            layer.blendMode = .multiply
            layer.fill(rect, with: .color(Color(red: 0.93, green: 0.8, blue: 0.6).opacity(0.55 * heirloom.patina)))
        } else {
            layer.blendMode = .screen
            layer.fill(rect, with: .color(Color(red: 0.42, green: 0.27, blue: 0.12).opacity(0.35 * heirloom.patina)))
        }
    }

    /// Each seam runs down the body from under the head toward the base, wandering a little,
    /// gold over a dark hairline so it reads on ivory and ebony alike.
    private func seams(_ context: inout GraphicsContext, size: CGSize, outline: PieceOutline) {
        guard heirloom.seams > 0 else { return }
        var random = SeededRandom(seed: UInt64(heirloom.seed * 7919 + 17))
        let lanes: [CGFloat] = heirloom.seams == 1 ? [0.42] : heirloom.seams == 2 ? [0.3, 0.64] : [0.24, 0.5, 0.74]
        let line = max(0.8, size.width * 0.011)
        for lane in lanes {
            let start = 0.3 + random.next() * 0.12, end = 0.78 + random.next() * 0.1
            var path = Path()
            let steps = 7
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let y = outline.top + outline.height * (start + (end - start) * t)
                let span = outline.span(at: y)
                let wander = (random.next() - 0.5) * 0.16
                let x = span.0 + (span.1 - span.0) * min(max(lane + wander, 0.08), 0.92)
                let point = CGPoint(x: x * size.width, y: y * size.height)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                // Now and then a short branch, as a real crack splits.
                if step == 3, random.next() < 0.6 {
                    var branch = Path()
                    branch.move(to: point)
                    let side: CGFloat = random.next() < 0.5 ? -1 : 1
                    branch.addLine(to: CGPoint(x: point.x + side * size.width * 0.05, y: point.y + size.height * 0.035))
                    context.stroke(branch, with: .color(Self.goldDeep.opacity(0.7)), style: StrokeStyle(lineWidth: line * 1.6, lineCap: .round))
                    context.stroke(branch, with: .color(Self.gold), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
                }
            }
            context.stroke(path, with: .color(Self.goldDeep.opacity(0.7)),
                           style: StrokeStyle(lineWidth: line * 2, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Self.gold),
                           style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
    }

    /// A gold band where the pawn's head meets its body.
    private func collar(_ context: inout GraphicsContext, size: CGSize, outline: PieceOutline) {
        let y = outline.narrowest(from: 0.2, to: 0.5)
        let band = outline.height * 0.045
        let rect = CGRect(x: 0, y: (y - band / 2) * size.height, width: size.width, height: band * size.height)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Self.goldDeep, Self.gold, Self.goldDeep]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
    }

    /// Small gold notches in a row across the front of the base.
    private func notches(_ context: inout GraphicsContext, size: CGSize, outline: PieceOutline) {
        let y = outline.top + outline.height * 0.93
        let span = outline.span(at: y)
        let center = (span.0 + span.1) / 2 * size.width
        let gap = (span.1 - span.0) * size.width * 0.1
        let dot = max(1.2, size.width * 0.018)
        for index in 0..<heirloom.notches {
            let x = center + (CGFloat(index) - CGFloat(heirloom.notches - 1) / 2) * gap
            let mark = CGRect(x: x - dot / 2, y: y * size.height - dot, width: dot, height: dot * 2)
            context.fill(Path(roundedRect: mark, cornerRadius: dot / 2), with: .color(Self.goldDeep))
            context.fill(Path(roundedRect: mark.insetBy(dx: dot * 0.18, dy: dot * 0.18), cornerRadius: dot / 2), with: .color(Self.gold))
        }
    }
}

/// A small repeatable random source, so a piece's seams run the same way every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// The next value, from 0 up to 1.
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}
