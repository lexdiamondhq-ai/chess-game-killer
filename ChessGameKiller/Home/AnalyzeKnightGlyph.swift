import SwiftUI

/// The knight on Home's gold Analyze button: the Gilded knight (the black-and-gold set), filled
/// solid in ink, with its striped mane, trim, knob, almond eye, nostril and base steps in pale
/// gold (Alex, 2026-11-10, "Gilded knight"). The same piece the photo-reading screen draws in
/// light. Traced from its 3D mesh (scripts/sculpted/knight_outline.py), in a 78 x 96 box
/// (x 4...82, y 6...102), muzzle to the right.
struct AnalyzeKnightGlyph: View {
    var ink = Color(hex: 0x2A1C08)
    var detail = Color(hex: 0xF6DB9C)

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: 4, y: 6, width: 78, height: 96)
            let k = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * k) / 2 - box.minX * k,
                                y: (size.height - box.height * k) / 2 - box.minY * k)
            context.scaleBy(x: k, y: k)

            var piece = Path()
            piece.addLines(Self.rim)
            piece.closeSubpath()
            context.fill(piece, with: .color(ink))

            var gold = Path()
            for shape in Self.details {
                gold.addLines(shape)
                gold.closeSubpath()
            }
            gold.addEllipse(in: CGRect(x: 73.9, y: 59.9, width: 3.2, height: 3.2))
            context.fill(gold, with: .color(detail))

            var steps = Path()
            for (y, from, to) in [(94.5, 10.2, 69.8), (92.1, 15.2, 64.8), (89.3, 14.1, 65.8), (86.9, 16.7, 63.2)] {
                steps.move(to: CGPoint(x: from, y: y))
                steps.addLine(to: CGPoint(x: to, y: y))
            }
            context.stroke(steps, with: .color(detail), lineWidth: 0.9)
        }
        .accessibilityHidden(true)
    }

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
}

#Preview {
    AnalyzeKnightGlyph().frame(width: 25, height: 30).padding().background(Color(hex: 0xE8C27A))
}
