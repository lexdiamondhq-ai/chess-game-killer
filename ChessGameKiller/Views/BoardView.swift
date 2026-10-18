import ChessKit
import SwiftUI

/// The interactive board: tap a piece to see its moves, tap a dot to play.
struct BoardView: View {
    let game: GameModel
    var theme: BoardTheme = .walnut

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
                if let promotion = game.pendingPromotion {
                    PromotionPicker(color: promotion.piece.color, theme: theme, squareSize: sq) { kind in
                        withAnimation(.snappy(duration: 0.2)) { game.promote(to: kind) }
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
    }

    // MARK: Squares, highlights and hints

    private func squares(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach((0..<8).reversed(), id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        square(Square(file: file, rank: rank), size: size)
                    }
                }
            }
        }
    }

    private func square(_ square: Square, size: CGFloat) -> some View {
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
            if square.fileIndex == 0 {
                coordinate("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
            }
            if square.rankIndex == 0 {
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
            withAnimation(.snappy(duration: 0.22)) { game.tap(square) }
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
        return parts.joined(separator: ", ")
    }

    // MARK: Pieces

    /// Pieces sit in their own layer so they can slide between squares.
    private func pieces(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.pieces) { placed in
                PieceImage(piece: placed.piece, theme: theme, size: size)
                    .scaleEffect(game.selected == placed.square ? 1.08 : 1)
                    .position(
                        x: (CGFloat(placed.square.fileIndex) + 0.5) * size,
                        y: (CGFloat(7 - placed.square.rankIndex) + 0.5) * size
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One piece drawn in the theme's style: a soft shadow on Walnut, a colored glow on Neon.
private struct PieceImage: View {
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
    BoardView(game: GameModel()).padding()
}

#Preview("Neon") {
    BoardView(game: GameModel(), theme: .neon)
        .padding()
        .background(NeonBackdrop())
}
