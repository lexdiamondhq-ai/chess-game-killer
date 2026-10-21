import SwiftUI

/// The colors Rewind uses on every board: one accent for the good, one warm tone
/// for moves to fix, and red for the ones that hurt.
enum RewindPalette {
    static let gold = Color(hex: 0xE6C17A)
    static let amber = Color(hex: 0xF0AE5A)
    static let coral = Color(hex: 0xEF7B6E)

    static func color(for moment: SavedMoment, rewritten: Bool) -> Color {
        if rewritten { return gold }
        switch moment.moveGrade {
        case .blunder: return coral
        case .mistake, .inaccuracy: return amber
        default: return gold
        }
    }
}

/// The whole game as one line: up when the player was winning, down when the
/// opponent was. Drag along it to move through the game; tap a dot to jump to it.
struct Lifeline: View {
    let game: SavedGame
    @Binding var ply: Int
    /// Where a ghost line branches off: from this ply, up to this value.
    var ghost: (ply: Int, value: Double)?
    /// The dots' centers, to stand out from the screen behind.
    var dotFill: Color = .black
    var onMoment: (SavedMoment) -> Void = { _ in }

    let inset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = game.lifeline.map { point(ply: $0.ply, value: $0.value, in: size) }
            let mid = size.height / 2
            let playX = x(for: ply, in: size)
            ZStack(alignment: .topLeading) {
                // Even.
                Path { path in
                    path.move(to: CGPoint(x: inset, y: mid))
                    path.addLine(to: CGPoint(x: size.width - inset, y: mid))
                }
                .stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

                Text("YOU").position(x: inset + 14, y: 8)
                Text(game.opponent.uppercased()).position(x: inset + 30, y: size.height - 8)

                // The tint between the line and even.
                Self.area(points, mid: mid)
                    .fill(LinearGradient(
                        colors: [RewindPalette.gold.opacity(0.16), .clear, RewindPalette.coral.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom))

                if let ghost {
                    let from = point(ply: ghost.ply, value: game.value(at: ghost.ply), in: size)
                    let toX = min(size.width - inset, from.x + max(44, size.width * 0.22))
                    let to = CGPoint(x: toX, y: y(for: ghost.value, in: size))
                    Path { path in
                        path.move(to: from)
                        path.addCurve(to: to, control1: CGPoint(x: (from.x + to.x) / 2, y: from.y),
                                      control2: CGPoint(x: (from.x + to.x) / 2, y: to.y))
                    }
                    .stroke(RewindPalette.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                    Circle().fill(RewindPalette.gold).frame(width: 7, height: 7).position(to)
                }

                // What hasn't happened yet at this point of the game sits back.
                Self.curve(points)
                    .stroke(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Self.curve(points)
                    .stroke(LinearGradient(colors: [RewindPalette.gold, Color.primary.opacity(0.9), RewindPalette.coral],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, playX))
                    }

                ForEach(game.keyMoments) { moment in
                    let center = point(ply: moment.ply, value: game.value(at: moment.ply), in: size)
                    let current = moment.ply == ply || moment.ply == ply + 1
                    let rewritten = game.rewritten.contains(moment.ply)
                    let color = RewindPalette.color(for: moment, rewritten: rewritten)
                    ZStack {
                        Circle().fill(dotFill)
                        Circle().strokeBorder(color, lineWidth: current ? 3 : 2)
                        if rewritten { Circle().fill(color).padding(current ? 6 : 4) }
                    }
                    .frame(width: current ? 18 : 12, height: current ? 18 : 12)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
                    .position(center)
                    .onTapGesture { onMoment(moment) }
                    .accessibilityElement()
                    .accessibilityLabel("\(moment.numbered), \(moment.moveGrade.rawValue)")
                    .accessibilityAddTraits(.isButton)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 1, height: size.height - 16)
                    .position(x: playX, y: size.height / 2)
                    .allowsHitTesting(false)
            }
            .font(.system(size: 9, weight: .semibold))
            .tracking(2)
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = plyAt(drag.location.x, in: size)
                        if next != ply { ply = next }
                    }
            )
            .animation(.snappy(duration: 0.2), value: ply)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: ply = min(game.moves.count, ply + 1)
            case .decrement: ply = max(0, ply - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Geometry

    private func x(for ply: Int, in size: CGSize) -> CGFloat {
        let total = max(1, game.moves.count)
        return inset + (size.width - inset * 2) * CGFloat(ply) / CGFloat(total)
    }

    private func y(for value: Double, in size: CGSize) -> CGFloat {
        let amplitude = size.height / 2 - 18
        return size.height / 2 - CGFloat(max(-1, min(1, value))) * amplitude
    }

    private func point(ply: Int, value: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: x(for: ply, in: size), y: y(for: value, in: size))
    }

    private func plyAt(_ x: CGFloat, in size: CGSize) -> Int {
        let total = max(1, game.moves.count)
        let share = (x - inset) / max(1, size.width - inset * 2)
        return max(0, min(total, Int((share * CGFloat(total)).rounded())))
    }

    /// The space between the line and even.
    static func area(_ points: [CGPoint], mid: CGFloat) -> Path {
        var path = curve(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: mid))
        path.addLine(to: CGPoint(x: first.x, y: mid))
        path.closeSubpath()
        return path
    }

    /// A smooth line through the points.
    static func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for (a, b) in zip(points, points.dropFirst()) {
                let midX = (a.x + b.x) / 2
                path.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
            }
        }
    }
}

/// A small version of the line, for the list of games.
struct LifelineSpark: View {
    let game: SavedGame
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let total = max(1, game.moves.count)
            let points = game.lifeline.map { point in
                CGPoint(x: geo.size.width * CGFloat(point.ply) / CGFloat(total),
                        y: geo.size.height / 2 - CGFloat(point.value) * (geo.size.height / 2 - 2))
            }
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                Lifeline.curve(points)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
