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
            ZStack(alignment: .topLeading) {
                squares(size: sq)
                pieces(size: sq)
                if let promotion = game.pendingPromotion {
                    PromotionPicker(color: promotion.piece.color, squareSize: sq) { kind in
                        withAnimation(.snappy(duration: 0.2)) { game.promote(to: kind) }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: sq * 0.25, y: sq * 0.08)
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
        let labelColor = isLight ? theme.dark : theme.light
        let occupant = game.piece(at: square)
        let isTarget = game.targets.contains(square)

        return ZStack {
            Rectangle().fill(isLight ? theme.light : theme.dark)

            if let last = game.lastMove, last.from == square || last.to == square {
                Rectangle().fill(theme.lastMove)
            }
            if game.selected == square {
                Rectangle().fill(theme.selected)
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
                if occupant == nil {
                    Circle().fill(theme.hint).frame(width: size * 0.32, height: size * 0.32)
                } else {
                    Circle().strokeBorder(theme.hint, lineWidth: size * 0.08).padding(size * 0.02)
                }
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
                Image(placed.piece.assetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(size * 0.04)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.02)
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

/// Lets the player choose what a pawn becomes on the last rank.
private struct PromotionPicker: View {
    let color: Piece.Color
    let squareSize: CGFloat
    let choose: (Piece.Kind) -> Void

    private let kinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing: squareSize * 0.15) {
                ForEach(kinds, id: \.self) { kind in
                    let piece = Piece(kind, color: color, square: .a1)
                    Button { choose(kind) } label: {
                        Image(piece.assetName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(squareSize * 0.12)
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

#Preview {
    BoardView(game: GameModel()).padding()
}
