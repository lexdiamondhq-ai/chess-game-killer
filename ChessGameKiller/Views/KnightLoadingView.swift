import SwiftUI

// MARK: - The board knight, drawn in light

/// What shows while a photo is read: the knight from the board, drawn as fine white line art on
/// a floating glass card over a warm gradient, with a spark of light running around its outline
/// and "Processing" below (Alex, 2026-11-10, "Light Trace"). With Reduce Motion the spark rests
/// and the whole outline glows instead.
struct KnightLoadingView: View {
    var title = "Processing"

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? Color(hex: 0xF4EDDF) : Color(hex: 0x2A1F16) }

    var body: some View {
        ZStack {
            KnightGlassBackdrop(dark: dark, still: reduceMotion)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                KnightTrace(dark: dark, still: reduceMotion)
                    .frame(width: 230, height: 276)
                VStack(spacing: 18) {
                    Text(title.uppercased())
                        .font(.custom(HomeCarvingFont.plain, size: 20, relativeTo: .headline))
                        .tracking(8)
                        .padding(.leading, 8)
                        .foregroundStyle(ink)
                        .shadow(color: .white.opacity(dark ? 0.4 : 0.9), radius: 9)
                    GlidingLine(dark: dark, still: reduceMotion)
                        .frame(width: 120, height: 2)
                }
            }
            .padding(.vertical, 46)
            .frame(maxWidth: 330)
            .background { KnightGlassCard(dark: dark) }
            .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The frosted card the knight floats on: glass with a bright top edge and a soft drop.
private struct KnightGlassCard: View {
    let dark: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(Color.white.opacity(dark ? 0.05 : 0.30)) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(dark ? 0.26 : 0.95), .white.opacity(dark ? 0.08 : 0.5)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .shadow(color: dark ? .black.opacity(0.45) : Color(hex: 0x785028).opacity(0.18), radius: 36, y: 22)
    }
}

/// Warm light behind the glass: amber, rose, plum and copper pools, blurred into one another,
/// drifting slowly. Ivory and pastel on a light screen, espresso and deep jewel tones on a dark one.
private struct KnightGlassBackdrop: View {
    let dark: Bool
    let still: Bool

    private struct Pool {
        let color: UInt32
        let opacity: Double
        let x: CGFloat, y: CGFloat, size: CGFloat
    }

    private var base: Color { dark ? Color(hex: 0x100B08) : Color(hex: 0xEFE4D2) }
    private var pools: [Pool] {
        dark ? [
            Pool(color: 0xE2B577, opacity: 0.50, x: 0.15, y: 0.12, size: 1.0),
            Pool(color: 0x8E3E45, opacity: 0.55, x: 0.85, y: 0.45, size: 0.95),
            Pool(color: 0x3E2A55, opacity: 0.60, x: 0.10, y: 0.80, size: 1.0),
            Pool(color: 0xC97A4A, opacity: 0.32, x: 0.85, y: 0.92, size: 0.85),
        ] : [
            Pool(color: 0xF2C79A, opacity: 0.90, x: 0.15, y: 0.12, size: 1.0),
            Pool(color: 0xE9A9A0, opacity: 0.70, x: 0.85, y: 0.42, size: 0.95),
            Pool(color: 0xB9A8D6, opacity: 0.60, x: 0.10, y: 0.80, size: 1.0),
            Pool(color: 0xF6D7A8, opacity: 0.80, x: 0.85, y: 0.92, size: 0.85),
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let side = max(proxy.size.width, 1) * 0.95
                ZStack {
                    base
                    ForEach(Array(pools.enumerated()), id: \.offset) { index, pool in
                        let drift = t / 14 + Double(index) * 1.7
                        Circle()
                            .fill(Color(hex: pool.color).opacity(pool.opacity))
                            .frame(width: side * pool.size, height: side * pool.size)
                            .position(x: proxy.size.width * pool.x + CGFloat(sin(drift)) * 26,
                                      y: proxy.size.height * pool.y + CGFloat(cos(drift * 0.8)) * 30)
                    }
                }
                .blur(radius: 70)
                .overlay { Color.white.opacity(dark ? 0.035 : 0.2) }
            }
        }
    }
}

/// The knight: its whole line art lit softly, and a spark with a fading tail running around the
/// outline every few seconds. On a light screen a faint warm shadow under the lines keeps the
/// white legible.
private struct KnightTrace: View {
    let dark: Bool
    let still: Bool

    /// One lap of the outline, in seconds.
    private static let lap = 3.2

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let phase = still ? 0 : (context.date.timeIntervalSinceReferenceDate / Self.lap)
                .truncatingRemainder(dividingBy: 1)
            ZStack {
                if !dark {
                    art
                        .stroke(Color(hex: 0x7A5230).opacity(0.42),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)
                }
                art
                    .stroke(.white.opacity(still ? 1 : (dark ? 0.6 : 0.92)),
                            style: StrokeStyle(lineWidth: still ? 2.2 : 1.6, lineCap: .round, lineJoin: .round))
                    .shadow(color: .white.opacity(0.8), radius: 2)
                    .shadow(color: .white.opacity(0.55), radius: 7)
                if !still {
                    // The tail fades in three steps up to the spark's bright head.
                    spark(at: phase, length: 0.24, width: 2.6, opacity: 0.35)
                    spark(at: phase + 0.10, length: 0.14, width: 3.0, opacity: 0.65)
                    spark(at: phase + 0.20, length: 0.05, width: 3.6, opacity: 1)
                }
            }
            .background {
                Ellipse()
                    .fill(.white.opacity(dark ? 0.10 : 0.18))
                    .scaleEffect(1.1)
                    .blur(radius: 40)
            }
        }
    }

    private var art: some Shape { BoardKnightArt() }

    private func spark(at start: Double, length: Double, width: CGFloat, opacity: Double) -> some View {
        BoardKnightRimSegment(start: start.truncatingRemainder(dividingBy: 1), length: length)
            .stroke(.white.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .shadow(color: .white, radius: 3)
            .shadow(color: .white.opacity(0.8), radius: 10)
            .shadow(color: .white.opacity(0.5), radius: 22)
    }
}

/// A short bright line gliding to and fro in a faint track: something is happening, with no
/// promise of how long.
private struct GlidingLine: View {
    let dark: Bool
    let still: Bool

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let width = proxy.size.width * 0.4
                let travel = proxy.size.width - width
                let x = still ? travel / 2 : travel * (0.5 - 0.5 * cos(t * 2 * .pi / 2.4))
                ZStack(alignment: .leading) {
                    Capsule().fill(dark ? Color.white.opacity(0.14) : Color(hex: 0x5A3C1E).opacity(0.15))
                    Capsule()
                        .fill(.white)
                        .frame(width: width)
                        .shadow(color: .white, radius: 5)
                        .offset(x: x)
                }
            }
        }
    }
}

// MARK: - The knight's lines

/// The board knight's outline, traced from its 3D mesh (scripts/sculpted/knight_outline.py),
/// in an 80 x 96 box (x 0...80, y 6...102), muzzle to the left. The rim starts at the ear tip.
enum BoardKnightLines {
    static let rim: [CGPoint] = [
        CGPoint(x: 39.11, y: 8.93), CGPoint(x: 40.0, y: 9.37), CGPoint(x: 41.44, y: 10.95), CGPoint(x: 43.98, y: 16.06),
        CGPoint(x: 46.44, y: 20.07), CGPoint(x: 46.98, y: 22.09), CGPoint(x: 47.42, y: 23.02), CGPoint(x: 48.09, y: 23.79),
        CGPoint(x: 49.33, y: 24.68), CGPoint(x: 50.47, y: 26.39), CGPoint(x: 52.83, y: 29.3), CGPoint(x: 54.17, y: 31.54),
        CGPoint(x: 55.83, y: 35.32), CGPoint(x: 56.1, y: 36.32), CGPoint(x: 56.15, y: 38.26), CGPoint(x: 56.77, y: 40.72),
        CGPoint(x: 58.36, y: 43.42), CGPoint(x: 59.18, y: 45.87), CGPoint(x: 59.71, y: 49.0), CGPoint(x: 59.56, y: 50.02),
        CGPoint(x: 59.13, y: 50.94), CGPoint(x: 59.08, y: 51.87), CGPoint(x: 60.41, y: 55.21), CGPoint(x: 60.85, y: 57.26),
        CGPoint(x: 61.01, y: 60.51), CGPoint(x: 60.04, y: 62.85), CGPoint(x: 60.19, y: 63.82), CGPoint(x: 61.09, y: 66.24),
        CGPoint(x: 61.43, y: 68.89), CGPoint(x: 61.14, y: 72.65), CGPoint(x: 61.06, y: 78.63), CGPoint(x: 61.42, y: 80.15),
        CGPoint(x: 62.64, y: 83.0), CGPoint(x: 62.81, y: 84.0), CGPoint(x: 62.52, y: 84.95), CGPoint(x: 61.2, y: 86.1),
        CGPoint(x: 61.23, y: 86.29), CGPoint(x: 62.06, y: 87.13), CGPoint(x: 63.59, y: 87.75), CGPoint(x: 63.65, y: 88.49),
        CGPoint(x: 62.8, y: 89.31), CGPoint(x: 62.73, y: 89.68), CGPoint(x: 63.22, y: 91.08), CGPoint(x: 64.25, y: 92.27),
        CGPoint(x: 66.54, y: 93.49), CGPoint(x: 71.24, y: 94.3), CGPoint(x: 72.18, y: 94.67), CGPoint(x: 72.54, y: 95.01),
        CGPoint(x: 72.89, y: 95.91), CGPoint(x: 72.85, y: 96.4), CGPoint(x: 71.99, y: 97.96), CGPoint(x: 71.63, y: 99.33),
        CGPoint(x: 70.75, y: 100.0), CGPoint(x: 9.97, y: 100.02), CGPoint(x: 8.94, y: 99.85), CGPoint(x: 8.53, y: 99.59),
        CGPoint(x: 8.26, y: 99.2), CGPoint(x: 7.99, y: 97.87), CGPoint(x: 7.24, y: 96.77), CGPoint(x: 7.09, y: 96.3),
        CGPoint(x: 7.21, y: 95.34), CGPoint(x: 7.85, y: 94.61), CGPoint(x: 8.82, y: 94.28), CGPoint(x: 13.51, y: 93.46),
        CGPoint(x: 14.92, y: 92.82), CGPoint(x: 15.78, y: 92.2), CGPoint(x: 16.79, y: 90.99), CGPoint(x: 17.17, y: 90.05),
        CGPoint(x: 17.09, y: 89.25), CGPoint(x: 16.24, y: 88.48), CGPoint(x: 16.44, y: 87.74), CGPoint(x: 17.97, y: 87.09),
        CGPoint(x: 18.63, y: 86.49), CGPoint(x: 19.98, y: 86.09), CGPoint(x: 20.5, y: 85.47), CGPoint(x: 20.86, y: 83.01),
        CGPoint(x: 22.64, y: 78.74), CGPoint(x: 23.21, y: 73.39), CGPoint(x: 23.91, y: 70.32), CGPoint(x: 25.97, y: 65.02),
        CGPoint(x: 28.38, y: 60.42), CGPoint(x: 28.81, y: 58.92), CGPoint(x: 28.84, y: 57.28), CGPoint(x: 28.52, y: 56.35),
        CGPoint(x: 28.15, y: 56.06), CGPoint(x: 27.16, y: 55.87), CGPoint(x: 25.59, y: 56.09), CGPoint(x: 14.95, y: 58.7),
        CGPoint(x: 11.1, y: 58.78), CGPoint(x: 8.52, y: 58.27), CGPoint(x: 7.1, y: 57.63), CGPoint(x: 6.26, y: 56.98),
        CGPoint(x: 5.52, y: 56.19), CGPoint(x: 4.71, y: 54.85), CGPoint(x: 4.29, y: 53.35), CGPoint(x: 4.09, y: 51.75),
        CGPoint(x: 4.17, y: 50.12), CGPoint(x: 4.53, y: 48.59), CGPoint(x: 5.22, y: 47.2), CGPoint(x: 6.68, y: 45.61),
        CGPoint(x: 14.51, y: 40.26), CGPoint(x: 19.56, y: 36.28), CGPoint(x: 25.61, y: 30.89), CGPoint(x: 27.51, y: 28.41),
        CGPoint(x: 29.55, y: 26.78), CGPoint(x: 31.9, y: 23.83), CGPoint(x: 35.27, y: 18.52), CGPoint(x: 36.03, y: 16.6),
        CGPoint(x: 37.51, y: 10.5), CGPoint(x: 37.95, y: 9.57), CGPoint(x: 38.66, y: 8.96),
    ]
    static let tiers: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 10.49, y: 94.2), CGPoint(x: 69.46, y: 94.2)),
        (CGPoint(x: 18.91, y: 87.2), CGPoint(x: 61.04, y: 87.2)),
        (CGPoint(x: 21.76, y: 85.1), CGPoint(x: 61.14, y: 85.1)),
    ]
    static let eye = CGPoint(x: 29.03, y: 30.12)
    static let beads: [CGPoint] = [
        CGPoint(x: 43.46, y: 19.91), CGPoint(x: 44.97, y: 23.24), CGPoint(x: 47.97, y: 26.57), CGPoint(x: 49.97, y: 29.9), CGPoint(x: 51.89, y: 33.23), CGPoint(x: 53.33, y: 36.56), CGPoint(x: 54.37, y: 39.89), CGPoint(x: 55.34, y: 43.22), CGPoint(x: 55.97, y: 46.55), CGPoint(x: 56.59, y: 49.88), CGPoint(x: 57.15, y: 53.21), CGPoint(x: 57.69, y: 56.54),
    ]
    /// The mouth and nostril, carved into the muzzle.
    static let mouth = (CGPoint(x: 4.8, y: 53.2), CGPoint(x: 9.0, y: 53.8), CGPoint(x: 12.8, y: 52.8))
    static let nostril = (CGPoint(x: 8.2, y: 47.0), CGPoint(x: 9.8, y: 45.8), CGPoint(x: 11.4, y: 47.2))

    static let box = CGRect(x: 0, y: 6, width: 80, height: 96)

    /// Maps the box into a rect, fitted and centered.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / box.width, rect.height / box.height)
        let dx = rect.midX - box.midX * scale
        let dy = rect.midY - box.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)
    }

    static var rimPath: Path {
        var path = Path()
        path.addLines(rim)
        path.closeSubpath()
        return path
    }
}

/// The whole line art: outline, base tiers, eye, mane beads, mouth and nostril.
struct BoardKnightArt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = BoardKnightLines.rimPath
        for (a, b) in BoardKnightLines.tiers {
            path.move(to: a)
            path.addLine(to: b)
        }
        path.addEllipse(in: CGRect(x: BoardKnightLines.eye.x - 2.3, y: BoardKnightLines.eye.y - 2.3, width: 4.6, height: 4.6))
        for bead in BoardKnightLines.beads {
            path.addEllipse(in: CGRect(x: bead.x - 1.9, y: bead.y - 1.9, width: 3.8, height: 3.8))
        }
        let mouth = BoardKnightLines.mouth
        path.move(to: mouth.0)
        path.addQuadCurve(to: mouth.2, control: mouth.1)
        let nostril = BoardKnightLines.nostril
        path.move(to: nostril.0)
        path.addQuadCurve(to: nostril.2, control: nostril.1)
        return path.applying(BoardKnightLines.transform(into: rect))
    }
}

/// A stretch of the outline from `start` (0 to 1 around it), wrapping past the ear tip.
struct BoardKnightRimSegment: Shape {
    var start: Double
    var length: Double

    func path(in rect: CGRect) -> Path {
        let rim = BoardKnightLines.rimPath.applying(BoardKnightLines.transform(into: rect))
        let end = start + length
        guard end > 1 else { return rim.trimmedPath(from: start, to: end) }
        var path = rim.trimmedPath(from: start, to: 1)
        path.addPath(rim.trimmedPath(from: 0, to: end - 1))
        return path
    }
}

#Preview("Light") {
    KnightLoadingView().preferredColorScheme(.light)
}

#Preview("Dark") {
    KnightLoadingView().preferredColorScheme(.dark)
}
