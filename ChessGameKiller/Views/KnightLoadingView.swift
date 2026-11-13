import SwiftUI

// MARK: - The board knight, drawn in light

/// What shows while a photo is read: the Gilded knight, drawn as fine white line art on
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
                    .frame(width: 224, height: 276)
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

/// The Gilded knight's outline (the black-and-gold set), traced from its 3D mesh
/// (scripts/sculpted/knight_outline.py), in a 78 x 96 box (x 4...82, y 6...102), muzzle to the
/// right. The rim starts at the top of the poll's knob.
enum BoardKnightLines {
    static let rim: [CGPoint] = [
        CGPoint(x: 51.33, y: 9.77), CGPoint(x: 51.94, y: 9.89), CGPoint(x: 52.63, y: 10.24), CGPoint(x: 53.02, y: 10.72),
        CGPoint(x: 53.42, y: 11.39), CGPoint(x: 53.82, y: 12.73), CGPoint(x: 54.02, y: 13.81), CGPoint(x: 54.21, y: 15.89),
        CGPoint(x: 54.39, y: 16.09), CGPoint(x: 55.19, y: 16.52), CGPoint(x: 55.59, y: 17.02), CGPoint(x: 55.75, y: 17.56),
        CGPoint(x: 55.91, y: 17.72), CGPoint(x: 56.33, y: 17.68), CGPoint(x: 57.29, y: 17.16), CGPoint(x: 61.22, y: 13.79),
        CGPoint(x: 62.79, y: 12.12), CGPoint(x: 63.18, y: 11.98), CGPoint(x: 63.36, y: 12.14), CGPoint(x: 63.43, y: 13.27),
        CGPoint(x: 63.27, y: 14.87), CGPoint(x: 63.03, y: 16.77), CGPoint(x: 62.67, y: 18.45), CGPoint(x: 61.95, y: 20.66),
        CGPoint(x: 61.5, y: 21.64), CGPoint(x: 59.98, y: 23.68), CGPoint(x: 59.79, y: 24.43), CGPoint(x: 59.85, y: 25.06),
        CGPoint(x: 61.84, y: 29.07), CGPoint(x: 65.29, y: 35.14), CGPoint(x: 68.03, y: 40.18), CGPoint(x: 71.81, y: 47.45),
        CGPoint(x: 74.06, y: 52.02), CGPoint(x: 78.01, y: 58.72), CGPoint(x: 78.74, y: 60.76), CGPoint(x: 79.02, y: 62.14),
        CGPoint(x: 78.93, y: 64.09), CGPoint(x: 78.51, y: 66.09), CGPoint(x: 77.9, y: 67.67), CGPoint(x: 76.86, y: 69.73),
        CGPoint(x: 76.25, y: 70.12), CGPoint(x: 75.47, y: 70.07), CGPoint(x: 73.35, y: 69.15), CGPoint(x: 70.91, y: 67.78),
        CGPoint(x: 69.36, y: 66.69), CGPoint(x: 67.99, y: 65.58), CGPoint(x: 65.62, y: 63.37), CGPoint(x: 65.73, y: 63.66),
        CGPoint(x: 66.47, y: 64.69), CGPoint(x: 70.08, y: 68.41), CGPoint(x: 71.06, y: 69.51), CGPoint(x: 71.29, y: 69.91),
        CGPoint(x: 71.29, y: 70.18), CGPoint(x: 70.99, y: 70.44), CGPoint(x: 70.04, y: 70.56), CGPoint(x: 69.24, y: 70.49),
        CGPoint(x: 67.79, y: 69.96), CGPoint(x: 66.34, y: 69.03), CGPoint(x: 65.79, y: 68.43), CGPoint(x: 63.29, y: 65.13),
        CGPoint(x: 61.15, y: 62.7), CGPoint(x: 58.51, y: 60.24), CGPoint(x: 56.37, y: 58.57), CGPoint(x: 54.53, y: 57.38),
        CGPoint(x: 53.28, y: 56.77), CGPoint(x: 51.56, y: 56.1), CGPoint(x: 49.19, y: 55.38), CGPoint(x: 45.91, y: 54.83),
        CGPoint(x: 44.23, y: 54.46), CGPoint(x: 43.6, y: 54.47), CGPoint(x: 43.25, y: 54.71), CGPoint(x: 43.11, y: 55.3),
        CGPoint(x: 43.16, y: 55.94), CGPoint(x: 44.38, y: 60.11), CGPoint(x: 45.85, y: 63.67), CGPoint(x: 46.83, y: 65.76),
        CGPoint(x: 48.75, y: 69.3), CGPoint(x: 49.68, y: 70.75), CGPoint(x: 51.37, y: 73.05), CGPoint(x: 54.1, y: 76.26),
        CGPoint(x: 55.25, y: 77.41), CGPoint(x: 57.99, y: 79.95), CGPoint(x: 60.7, y: 82.27), CGPoint(x: 63.65, y: 85.11),
        CGPoint(x: 63.89, y: 85.5), CGPoint(x: 64.02, y: 86.45), CGPoint(x: 64.2, y: 86.83), CGPoint(x: 64.61, y: 86.96),
        CGPoint(x: 66.76, y: 86.98), CGPoint(x: 67.05, y: 87.06), CGPoint(x: 67.35, y: 87.36), CGPoint(x: 67.46, y: 87.64),
        CGPoint(x: 67.5, y: 88.29), CGPoint(x: 67.35, y: 89.05), CGPoint(x: 66.91, y: 89.39), CGPoint(x: 66.13, y: 89.45),
        CGPoint(x: 65.98, y: 89.55), CGPoint(x: 66.81, y: 90.41), CGPoint(x: 66.97, y: 91.15), CGPoint(x: 66.87, y: 91.39),
        CGPoint(x: 66.04, y: 91.96), CGPoint(x: 65.97, y: 92.12), CGPoint(x: 66.29, y: 92.23), CGPoint(x: 68.44, y: 92.24),
        CGPoint(x: 68.89, y: 92.34), CGPoint(x: 69.22, y: 92.59), CGPoint(x: 69.42, y: 92.97), CGPoint(x: 69.51, y: 94.09),
        CGPoint(x: 69.61, y: 94.34), CGPoint(x: 69.86, y: 94.42), CGPoint(x: 70.84, y: 94.46), CGPoint(x: 71.41, y: 94.64),
        CGPoint(x: 72.07, y: 95.03), CGPoint(x: 72.52, y: 95.48), CGPoint(x: 72.83, y: 96.02), CGPoint(x: 73.01, y: 96.77),
        CGPoint(x: 72.96, y: 98.74), CGPoint(x: 72.82, y: 99.18), CGPoint(x: 72.0, y: 100.01), CGPoint(x: 8.36, y: 100.03),
        CGPoint(x: 7.76, y: 99.89), CGPoint(x: 7.11, y: 99.18), CGPoint(x: 6.99, y: 98.89), CGPoint(x: 6.9, y: 97.59),
        CGPoint(x: 6.95, y: 96.61), CGPoint(x: 7.17, y: 95.87), CGPoint(x: 7.62, y: 95.23), CGPoint(x: 8.12, y: 94.84),
        CGPoint(x: 8.68, y: 94.58), CGPoint(x: 9.13, y: 94.46), CGPoint(x: 10.11, y: 94.42), CGPoint(x: 10.35, y: 94.31),
        CGPoint(x: 10.52, y: 92.93), CGPoint(x: 10.66, y: 92.67), CGPoint(x: 11.0, y: 92.38), CGPoint(x: 11.45, y: 92.25),
        CGPoint(x: 13.61, y: 92.23), CGPoint(x: 13.96, y: 92.14), CGPoint(x: 13.92, y: 91.98), CGPoint(x: 13.15, y: 91.3),
        CGPoint(x: 12.97, y: 90.57), CGPoint(x: 13.12, y: 90.22), CGPoint(x: 13.96, y: 89.56), CGPoint(x: 13.84, y: 89.46),
        CGPoint(x: 12.92, y: 89.35), CGPoint(x: 12.59, y: 89.06), CGPoint(x: 12.43, y: 88.29), CGPoint(x: 12.47, y: 87.64),
        CGPoint(x: 12.58, y: 87.36), CGPoint(x: 12.9, y: 87.06), CGPoint(x: 13.2, y: 86.98), CGPoint(x: 15.19, y: 86.96),
        CGPoint(x: 15.55, y: 86.88), CGPoint(x: 15.4, y: 86.64), CGPoint(x: 14.8, y: 86.53), CGPoint(x: 14.54, y: 86.39),
        CGPoint(x: 13.15, y: 84.64), CGPoint(x: 11.77, y: 82.05), CGPoint(x: 10.92, y: 79.73), CGPoint(x: 10.19, y: 77.2),
        CGPoint(x: 9.33, y: 73.05), CGPoint(x: 8.66, y: 67.82), CGPoint(x: 8.38, y: 64.11), CGPoint(x: 8.37, y: 59.77),
        CGPoint(x: 8.51, y: 57.16), CGPoint(x: 8.99, y: 52.03), CGPoint(x: 9.4, y: 49.36), CGPoint(x: 9.92, y: 46.57),
        CGPoint(x: 11.08, y: 41.89), CGPoint(x: 12.24, y: 38.53), CGPoint(x: 13.25, y: 36.12), CGPoint(x: 15.1, y: 32.54),
        CGPoint(x: 17.38, y: 29.15), CGPoint(x: 20.09, y: 26.15), CGPoint(x: 22.41, y: 24.1), CGPoint(x: 24.21, y: 22.81),
        CGPoint(x: 26.18, y: 21.52), CGPoint(x: 30.17, y: 19.5), CGPoint(x: 32.18, y: 18.7), CGPoint(x: 35.73, y: 17.61),
        CGPoint(x: 38.35, y: 17.08), CGPoint(x: 41.51, y: 16.66), CGPoint(x: 45.2, y: 16.32), CGPoint(x: 47.5, y: 16.22),
        CGPoint(x: 47.93, y: 16.1), CGPoint(x: 48.15, y: 15.75), CGPoint(x: 48.39, y: 13.02), CGPoint(x: 48.77, y: 11.68),
        CGPoint(x: 49.46, y: 10.46), CGPoint(x: 49.95, y: 10.06), CGPoint(x: 50.52, y: 9.83),
    ]
    /// The gold mane stripes, trim and knob, and the eye: closed shapes.
    static let details: [[CGPoint]] = [
        [
            CGPoint(x: 11.03, y: 79.78), CGPoint(x: 10.23, y: 77.35), CGPoint(x: 9.35, y: 73.21), CGPoint(x: 8.64, y: 67.66),
            CGPoint(x: 8.37, y: 64.11), CGPoint(x: 8.37, y: 59.77), CGPoint(x: 8.7, y: 54.8), CGPoint(x: 9.39, y: 49.41),
            CGPoint(x: 10.99, y: 42.23), CGPoint(x: 12.3, y: 38.33), CGPoint(x: 15.11, y: 32.49), CGPoint(x: 17.42, y: 29.11),
            CGPoint(x: 19.92, y: 26.31), CGPoint(x: 22.55, y: 23.98), CGPoint(x: 26.2, y: 21.51), CGPoint(x: 30.2, y: 19.49),
            CGPoint(x: 35.61, y: 17.66), CGPoint(x: 39.42, y: 16.92), CGPoint(x: 47.92, y: 16.12), CGPoint(x: 48.16, y: 15.79),
            CGPoint(x: 48.52, y: 12.44), CGPoint(x: 49.32, y: 10.6), CGPoint(x: 49.92, y: 10.06), CGPoint(x: 50.64, y: 9.8),
            CGPoint(x: 51.62, y: 9.8), CGPoint(x: 52.49, y: 10.12), CGPoint(x: 53.35, y: 11.22), CGPoint(x: 53.74, y: 12.4),
            CGPoint(x: 54.18, y: 15.88), CGPoint(x: 55.06, y: 16.39), CGPoint(x: 55.73, y: 17.26), CGPoint(x: 55.48, y: 18.1),
            CGPoint(x: 48.84, y: 18.17), CGPoint(x: 43.83, y: 18.44), CGPoint(x: 38.76, y: 19.07), CGPoint(x: 36.23, y: 19.63),
            CGPoint(x: 37.73, y: 19.42), CGPoint(x: 38.07, y: 19.78), CGPoint(x: 37.5, y: 32.82), CGPoint(x: 37.85, y: 38.68),
            CGPoint(x: 39.35, y: 45.56), CGPoint(x: 41.65, y: 50.28), CGPoint(x: 43.29, y: 52.93), CGPoint(x: 43.23, y: 53.35),
            CGPoint(x: 42.07, y: 54.84), CGPoint(x: 40.13, y: 54.01), CGPoint(x: 15.38, y: 41.28), CGPoint(x: 13.97, y: 40.4),
            CGPoint(x: 14.05, y: 39.81), CGPoint(x: 15.24, y: 36.8), CGPoint(x: 15.76, y: 35.86), CGPoint(x: 15.99, y: 35.76),
            CGPoint(x: 40.82, y: 53.46), CGPoint(x: 20.28, y: 29.26), CGPoint(x: 20.99, y: 28.25), CGPoint(x: 22.92, y: 26.47),
            CGPoint(x: 25.45, y: 24.53), CGPoint(x: 25.98, y: 24.51), CGPoint(x: 36.0, y: 43.72), CGPoint(x: 34.73, y: 38.02),
            CGPoint(x: 32.86, y: 21.12), CGPoint(x: 33.15, y: 20.64), CGPoint(x: 34.92, y: 20.01), CGPoint(x: 32.5, y: 20.71),
            CGPoint(x: 30.22, y: 21.66), CGPoint(x: 27.46, y: 23.04), CGPoint(x: 25.23, y: 24.5), CGPoint(x: 22.34, y: 26.78),
            CGPoint(x: 20.67, y: 28.37), CGPoint(x: 18.98, y: 30.34), CGPoint(x: 17.18, y: 32.93), CGPoint(x: 15.01, y: 37.04),
            CGPoint(x: 12.93, y: 42.85), CGPoint(x: 11.76, y: 47.7), CGPoint(x: 10.79, y: 53.97), CGPoint(x: 10.3, y: 61.6),
            CGPoint(x: 10.57, y: 67.16), CGPoint(x: 11.61, y: 74.24), CGPoint(x: 12.95, y: 79.5), CGPoint(x: 12.86, y: 79.71),
            CGPoint(x: 12.55, y: 79.76), CGPoint(x: 11.38, y: 79.44),
        ],
        [
            CGPoint(x: 28.61, y: 57.22), CGPoint(x: 11.41, y: 52.83), CGPoint(x: 11.12, y: 52.34), CGPoint(x: 11.88, y: 47.97),
            CGPoint(x: 12.07, y: 47.77), CGPoint(x: 12.48, y: 47.87), CGPoint(x: 27.15, y: 55.71), CGPoint(x: 28.63, y: 56.56),
            CGPoint(x: 28.8, y: 56.81),
        ],
        [
            CGPoint(x: 13.21, y: 66.63), CGPoint(x: 11.09, y: 66.63), CGPoint(x: 10.73, y: 66.4), CGPoint(x: 10.5, y: 61.64),
            CGPoint(x: 10.74, y: 61.14), CGPoint(x: 29.44, y: 63.74), CGPoint(x: 29.8, y: 64.01), CGPoint(x: 30.62, y: 66.01),
            CGPoint(x: 30.54, y: 66.23), CGPoint(x: 30.24, y: 66.3),
        ],
        [
            CGPoint(x: 33.01, y: 77.56), CGPoint(x: 12.81, y: 77.55), CGPoint(x: 12.48, y: 77.28), CGPoint(x: 11.66, y: 73.45),
            CGPoint(x: 11.81, y: 73.22), CGPoint(x: 12.29, y: 73.17), CGPoint(x: 27.36, y: 73.17), CGPoint(x: 29.27, y: 73.39),
            CGPoint(x: 31.16, y: 74.5), CGPoint(x: 32.47, y: 75.77), CGPoint(x: 33.17, y: 77.16),
        ],
        [
            CGPoint(x: 62.82, y: 39.3), CGPoint(x: 60.44, y: 39.08), CGPoint(x: 57.98, y: 38.13), CGPoint(x: 55.87, y: 36.36),
            CGPoint(x: 54.63, y: 34.52), CGPoint(x: 54.65, y: 34.08), CGPoint(x: 56.6, y: 33.97), CGPoint(x: 57.88, y: 34.13),
            CGPoint(x: 59.37, y: 34.58), CGPoint(x: 60.74, y: 35.33), CGPoint(x: 61.99, y: 36.36), CGPoint(x: 63.44, y: 38.28),
            CGPoint(x: 63.75, y: 39.07),
        ],
    ]
    static let tiers: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 10.19, y: 94.5), CGPoint(x: 69.76, y: 94.5)),
        (CGPoint(x: 15.15, y: 92.1), CGPoint(x: 64.78, y: 92.1)),
        (CGPoint(x: 14.06, y: 89.3), CGPoint(x: 65.82, y: 89.3)),
        (CGPoint(x: 16.67, y: 86.9), CGPoint(x: 63.21, y: 86.9)),
    ]
    static let nostril = CGPoint(x: 75.5, y: 61.5)

    static let box = CGRect(x: 4, y: 6, width: 78, height: 96)

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

/// The whole line art: outline, gold stripes and trim, eye, nostril and base tiers.
struct BoardKnightArt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = BoardKnightLines.rimPath
        for shape in BoardKnightLines.details {
            path.addLines(shape)
            path.closeSubpath()
        }
        for (a, b) in BoardKnightLines.tiers {
            path.move(to: a)
            path.addLine(to: b)
        }
        let nostril = BoardKnightLines.nostril
        path.addEllipse(in: CGRect(x: nostril.x - 2.2, y: nostril.y - 2.2, width: 4.4, height: 4.4))
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

/// The same knight and spark at pill size, beside "Reading your board…" while a photo is read
/// over its analysis board (Alex, 2026-11-13, "Board right away"): the outline with a small
/// spark running round it, and no big glow.
struct KnightTraceMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : (context.date.timeIntervalSinceReferenceDate / 3.2)
                .truncatingRemainder(dividingBy: 1)
            ZStack {
                BoardKnightArt()
                    .stroke(Color.primary.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                if !reduceMotion {
                    BoardKnightRimSegment(start: phase, length: 0.16)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .shadow(color: .white.opacity(0.7), radius: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
