import SwiftUI

/// The knight on Home's gold Analyze button: the carved knight from the board, filled solid in
/// ink, with its mane beads, eye, mouth and base rings picked out in pale gold (Alex, 2026-11-10,
/// "A · Our board knight"). The outline is traced from the board knight's 3D mesh
/// (scripts/sculpted/knight_outline.py), in a 76 x 96 box, muzzle to the left.
struct AnalyzeKnightGlyph: View {
    var ink = Color(hex: 0x2A1C08)
    var detail = Color(hex: 0xF6DB9C)

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: 2, y: 6, width: 76, height: 96)
            let k = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * k) / 2 - box.minX * k,
                                y: (size.height - box.height * k) / 2 - box.minY * k)
            context.scaleBy(x: k, y: k)

            var piece = Path()
            piece.addLines(Self.rim)
            piece.closeSubpath()
            context.fill(piece, with: .color(ink))

            var dots = Path()
            for bead in Self.beads {
                dots.addEllipse(in: CGRect(x: bead.x - 2.9, y: bead.y - 1.7, width: 3.4, height: 3.4))
            }
            dots.addEllipse(in: CGRect(x: 26.4, y: 27.5, width: 5.2, height: 5.2))
            context.fill(dots, with: .color(detail))

            var lines = Path()
            lines.move(to: CGPoint(x: 4.8, y: 53.2))
            lines.addQuadCurve(to: CGPoint(x: 12.8, y: 52.8), control: CGPoint(x: 9, y: 53.8))
            lines.move(to: CGPoint(x: 8.2, y: 47))
            lines.addQuadCurve(to: CGPoint(x: 11.4, y: 47.2), control: CGPoint(x: 9.8, y: 45.8))
            context.stroke(lines, with: .color(detail), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

            var rings = Path()
            rings.move(to: CGPoint(x: 10.5, y: 94.2)); rings.addLine(to: CGPoint(x: 69.5, y: 94.2))
            rings.move(to: CGPoint(x: 18.9, y: 87.2)); rings.addLine(to: CGPoint(x: 61, y: 87.2))
            context.stroke(rings, with: .color(detail), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }

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

    static let beads: [CGPoint] = [
        CGPoint(x: 43.46, y: 19.91), CGPoint(x: 44.97, y: 23.24), CGPoint(x: 47.97, y: 26.57), CGPoint(x: 49.97, y: 29.9), CGPoint(x: 51.89, y: 33.23), CGPoint(x: 53.33, y: 36.56), CGPoint(x: 54.37, y: 39.89), CGPoint(x: 55.34, y: 43.22), CGPoint(x: 55.97, y: 46.55), CGPoint(x: 56.59, y: 49.88), CGPoint(x: 57.15, y: 53.21), CGPoint(x: 57.69, y: 56.54),
    ]
}

#Preview {
    AnalyzeKnightGlyph().frame(width: 25, height: 30).padding().background(Color(hex: 0xE8C27A))
}
