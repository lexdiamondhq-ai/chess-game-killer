import ChessKit
import SwiftUI

/// The interactive board: tap a piece to see its moves, tap a dot to play.
/// Shows the two best moves as arrows and blows up captured pieces.
struct BoardView: View {
    let match: MatchController
    var theme: BoardTheme = .walnut

    private var game: GameModel { match.game }
    private var flipped: Bool { match.isBoardFlipped }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sq = side / 8
            let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                if let surface = theme.surface {
                    LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                squares(size: sq)
                pieces(size: sq)
                arrows(size: sq)
                if let promotion = game.pendingPromotion {
                    PromotionPicker(color: promotion.piece.color, theme: theme, squareSize: sq) { kind in
                        withAnimation(.snappy(duration: 0.2)) { match.promote(to: kind) }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .clipShape(corner)
            .overlay {
                if let edge = theme.boardEdge {
                    corner.strokeBorder(edge, lineWidth: 1)
                }
            }
            // Explosions sit outside the clip so shards can fly past the edge.
            .overlay(alignment: .topLeading) { explosions(size: sq) }
            .background {
                // Soft shadow (Walnut) or colored glow (Neon) around the board.
                ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                    corner.fill(color)
                        .blur(radius: sq * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                        .offset(y: theme.isDark ? 0 : sq * 0.08)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: game.moveCount)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: game.captureEvents.last?.id)
    }

    // MARK: Layout

    /// Where a square is drawn: column 0 is the left edge, row 0 the top.
    private func cell(of square: Square) -> (column: Int, row: Int) {
        flipped
            ? (7 - square.fileIndex, square.rankIndex)
            : (square.fileIndex, 7 - square.rankIndex)
    }

    private func center(of square: Square, size: CGFloat) -> CGPoint {
        let cell = cell(of: square)
        return CGPoint(x: (CGFloat(cell.column) + 0.5) * size, y: (CGFloat(cell.row) + 0.5) * size)
    }

    private func square(column: Int, row: Int) -> Square {
        flipped
            ? Square(file: 7 - column, rank: row)
            : Square(file: column, rank: 7 - row)
    }

    // MARK: Squares, highlights and hints

    private func squares(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        squareView(square(column: column, row: row), column: column, row: row, size: size)
                    }
                }
            }
        }
    }

    private func squareView(_ square: Square, column: Int, row: Int, size: CGFloat) -> some View {
        let isLight = (square.fileIndex + square.rankIndex) % 2 == 1
        let labelColor = isLight ? theme.labelOnLight : theme.labelOnDark
        let occupant = game.piece(at: square)
        let isTarget = game.targets.contains(square)
        let ringWidth = size * 0.035

        return ZStack {
            Rectangle().fill(isLight ? theme.light : theme.dark)

            if let gridLine = theme.gridLine {
                Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
            }
            if let last = game.lastMove, last.from == square || last.to == square {
                Rectangle().fill(theme.lastMove)
                if let ring = theme.lastMoveRing {
                    Rectangle().strokeBorder(ring, lineWidth: ringWidth)
                }
            }
            if game.selected == square {
                Rectangle().fill(theme.selected)
                if let ring = theme.selectedRing {
                    Rectangle().strokeBorder(ring, lineWidth: ringWidth)
                        .shadow(color: ring, radius: size * 0.08)
                }
            }
            if game.checkedKing == square {
                RadialGradient(
                    colors: [theme.check, theme.check.opacity(0.6), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.62
                )
            }

            // Coordinates in the corners, like a printed board.
            if column == 0 {
                coordinate("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
            }
            if row == 7 {
                coordinate(square.file.rawValue, size: size, color: labelColor, alignment: .bottomTrailing)
            }

            // Legal-move hints: a dot on empty squares, a ring around captures.
            if isTarget {
                Group {
                    if occupant == nil {
                        Circle().fill(theme.hint).frame(width: size * 0.3, height: size * 0.3)
                    } else {
                        Circle().strokeBorder(theme.hint, lineWidth: size * 0.08).padding(size * 0.02)
                    }
                }
                .shadow(color: theme.hintGlow ?? .clear, radius: theme.hintGlow == nil ? 0 : size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { match.tap(square) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(square, occupant: occupant, isTarget: isTarget))
        .accessibilityAddTraits(.isButton)
    }

    private func coordinate(_ text: String, size: CGFloat, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(size * 0.05)
    }

    private func accessibilityLabel(_ square: Square, occupant: Piece?, isTarget: Bool) -> String {
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if isTarget { parts.append(occupant == nil ? "move here" : "capture") }
        if let hint = match.hints.first(where: { $0.from == square }) {
            parts.append(hint.rank == 0 ? "best move \(hint.san)" : "second best move \(hint.san)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Pieces

    /// Pieces sit in their own layer so they can slide between squares.
    private func pieces(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.pieces) { placed in
                PieceImage(piece: placed.piece, theme: theme, size: size)
                    .scaleEffect(game.selected == placed.square ? 1.08 : 1)
                    .position(center(of: placed.square, size: size))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .frame(width: size * 8, height: size * 8)
        // The computer's moves arrive without a tap, so animate every change here.
        .animation(.snappy(duration: 0.3), value: game.pieces)
        .animation(.snappy(duration: 0.45), value: flipped)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Best-move arrows

    /// The best move as a solid arrow, the second best as a dashed one.
    private func arrows(size: CGFloat) -> some View {
        ZStack {
            ForEach(Array(match.hints.reversed())) { hint in
                MoveArrow(
                    from: center(of: hint.from, size: size),
                    to: center(of: hint.to, size: size),
                    squareSize: size,
                    isBest: hint.rank == 0,
                    color: hint.rank == 0 ? theme.bestArrow : theme.secondArrow,
                    glow: theme.arrowGlow
                )
                .transition(.opacity)
            }
        }
        .frame(width: size * 8, height: size * 8)
        .animation(.easeInOut(duration: 0.25), value: match.hints)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Captures

    private func explosions(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.captureEvents) { event in
                CaptureExplosion(
                    piece: event.piece,
                    theme: theme,
                    size: size,
                    seed: event.id
                )
                .position(center(of: event.piece.square, size: size))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An arrow from one square to another. Solid for the best move, dashed for the runner-up.
private struct MoveArrow: View {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat
    let isBest: Bool
    let color: Color
    let glow: Color?

    var body: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length
        let uy = dy / length
        let headLength = squareSize * (isBest ? 0.42 : 0.36)
        let headWidth = squareSize * (isBest ? 0.5 : 0.42)
        let shaftWidth = squareSize * (isBest ? 0.17 : 0.11)
        // Start a little off the piece's center, stop at the arrowhead.
        let start = CGPoint(x: from.x + ux * squareSize * 0.18, y: from.y + uy * squareSize * 0.18)
        let tip = CGPoint(x: to.x - ux * squareSize * 0.08, y: to.y - uy * squareSize * 0.08)
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)

        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: base)
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: shaftWidth,
                lineCap: isBest ? .round : .butt,
                dash: isBest ? [] : [shaftWidth * 1.6, shaftWidth * 1.1]
            ))

            Path { path in
                path.move(to: tip)
                path.addLine(to: CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2))
                path.addLine(to: CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2))
                path.closeSubpath()
            }
            .fill(color)
        }
        .shadow(color: glow?.opacity(isBest ? 0.9 : 0.6) ?? .black.opacity(0.15),
                radius: glow == nil ? 1 : squareSize * (isBest ? 0.12 : 0.08))
    }
}

/// A captured piece bursting apart: a flash, a shockwave, the piece breaking
/// into shards and a spray of sparks in the theme's colors.
private struct CaptureExplosion: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat
    let seed: Int

    @State private var burst = false

    private struct Shard: Identifiable {
        let id: Int
        let start: Angle
        let end: Angle
        let distance: CGFloat
        let spin: Double
    }

    private struct Spark: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let radius: CGFloat
        let colorIndex: Int
        let delay: Double
    }

    private var colors: [Color] { theme.sparks(for: piece.color) }

    var body: some View {
        let canvas = size * 3.2
        ZStack {
            // Flash
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white, colors[1 % colors.count], colors[1 % colors.count].opacity(0)],
                    center: .center, startRadius: 0, endRadius: size * 0.6
                ))
                .frame(width: size * 1.2, height: size * 1.2)
                .scaleEffect(burst ? 1.9 : 0.3)
                .opacity(burst ? 0 : 0.95)
                .animation(.easeOut(duration: 0.45), value: burst)

            // Shockwave
            Circle()
                .strokeBorder(colors[0], lineWidth: size * (burst ? 0.02 : 0.12))
                .frame(width: size, height: size)
                .scaleEffect(burst ? 2.6 : 0.4)
                .opacity(burst ? 0 : 0.9)
                .shadow(color: colors[1 % colors.count], radius: size * 0.1)
                .animation(.easeOut(duration: 0.6), value: burst)

            // The piece, broken into wedges that fly apart.
            ForEach(shards) { shard in
                PieceShardImage(piece: piece, theme: theme, size: size)
                    .clipShape(Wedge(start: shard.start, end: shard.end))
                    .rotationEffect(.degrees(burst ? shard.spin : 0))
                    .offset(flight(of: shard))
                    .scaleEffect(burst ? 0.75 : 1)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 0.75), value: burst)
            }

            // Sparks
            ForEach(sparks) { spark in
                let color = colors[spark.colorIndex % colors.count]
                Circle()
                    .fill(color)
                    .frame(width: spark.radius * 2, height: spark.radius * 2)
                    .shadow(color: color, radius: spark.radius * 1.5)
                    .offset(x: burst ? CGFloat(cos(spark.angle)) * spark.distance : 0,
                            y: burst ? CGFloat(sin(spark.angle)) * spark.distance : 0)
                    .scaleEffect(burst ? 0.2 : 1)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 0.8).delay(spark.delay), value: burst)
            }
        }
        .frame(width: canvas, height: canvas)
        .blendMode(theme.isDark ? .plusLighter : .normal)
        .onAppear {
            // On the next frame, so the burst animates from its starting state.
            Task { @MainActor in burst = true }
        }
    }

    /// How far a shard has flown: outward through the middle of its wedge.
    private func flight(of shard: Shard) -> CGSize {
        guard burst else { return .zero }
        let middle = (shard.start.radians + shard.end.radians) / 2
        return CGSize(width: CGFloat(cos(middle)) * shard.distance, height: CGFloat(sin(middle)) * shard.distance)
    }

    /// Shapes and paths that vary from capture to capture but stay put while one plays.
    private var shards: [Shard] {
        var random = SeededRandom(seed: seed)
        let count = 6
        let turn = 360.0 / Double(count)
        let first = random.next() * turn
        return (0..<count).map { i in
            let start = first + Double(i) * turn
            return Shard(
                id: i,
                start: .degrees(start),
                end: .degrees(start + turn),
                distance: size * CGFloat(0.55 + random.next() * 0.5),
                spin: (random.next() - 0.5) * 160
            )
        }
    }

    private var sparks: [Spark] {
        var random = SeededRandom(seed: seed &* 31 &+ 7)
        return (0..<22).map { i in
            Spark(
                id: i,
                angle: random.next() * 2 * .pi,
                distance: size * CGFloat(0.6 + random.next() * 0.95),
                radius: size * CGFloat(0.025 + random.next() * 0.035),
                colorIndex: Int(random.next() * 4),
                delay: random.next() * 0.06
            )
        }
    }
}

/// The piece image for a shard, without the board's glow (the explosion has its own).
private struct PieceShardImage: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        Image(theme.imageName(for: piece))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(size * 0.04)
            .frame(width: size, height: size)
    }
}

/// A pie slice from the center, used to cut a piece into shards.
private struct Wedge: Shape {
    let start: Angle
    let end: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Small repeatable random numbers, so each explosion looks different but stays stable.
private struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// A number from 0 up to (not including) 1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// One piece drawn in the theme's style: a soft shadow on Walnut, a colored glow on Neon.
struct PieceImage: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        let glow = piece.color == .white ? theme.whiteGlow : theme.blackGlow
        Image(theme.imageName(for: piece))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .padding(size * 0.04)
            .frame(width: size, height: size)
            .shadow(color: glow?.opacity(0.95) ?? .black.opacity(0.18),
                    radius: glow == nil ? size * 0.02 : size * 0.025,
                    y: glow == nil ? size * 0.02 : 0)
            .shadow(color: glow?.opacity(0.6) ?? .clear, radius: glow == nil ? 0 : size * 0.09)
    }
}

/// Lets the player choose what a pawn becomes on the last rank.
private struct PromotionPicker: View {
    let color: Piece.Color
    let theme: BoardTheme
    let squareSize: CGFloat
    let choose: (Piece.Kind) -> Void

    private let kinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing: squareSize * 0.15) {
                ForEach(kinds, id: \.self) { kind in
                    Button { choose(kind) } label: {
                        PieceImage(piece: Piece(kind, color: color, square: .a1), theme: theme, size: squareSize)
                            .padding(squareSize * 0.08)
                            .frame(width: squareSize * 1.25, height: squareSize * 1.25)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: squareSize * 0.2, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Promote to \(String(describing: kind))")
                }
            }
        }
        .frame(width: squareSize * 8, height: squareSize * 8)
    }
}

#Preview("Walnut") {
    BoardView(match: MatchController(engine: nil, sounds: nil)).padding()
}

#Preview("Neon") {
    BoardView(match: MatchController(engine: nil, sounds: nil), theme: .neon)
        .padding()
        .background(NeonBackdrop())
}
