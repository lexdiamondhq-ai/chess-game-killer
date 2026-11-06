import ChessKit
import SwiftUI

/// A still board for the editor and the analyzer: draws any position in the
/// theme's style, with optional best-move arrows and square taps.
struct PositionBoard: View {
    let draft: PositionDraft
    var theme: BoardTheme = .neon
    var flipped = false
    var hints: [MoveHint] = []
    var onTap: ((Square) -> Void)?
    /// Squares tinted to draw the eye, like where a move came from and went.
    var tints: [Square: Color] = [:]
    /// Pieces drawn as ghosts: moves that could have been, not moves that were.
    var ghosts: Set<Square> = []
    var ghostColor: Color = .yellow
    /// The piece picked up, and the squares it can go to (drawn as dots, rings on a capture).
    var selected: Square? = nil
    var targets: Set<Square> = []
    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = theme.frameInset(side: side, coordinates: showsCoordinates)
            let sq = (side - inset * 2) / 8
            let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                // Only the board is cut to its rounded corners, so a tall piece on the far rank
                // may rise a little above the frame.
                ZStack {
                    if let art = theme.boardArt {
                        BoardArt(name: art, flipped: flipped, coordinates: showsCoordinates)
                    }
                    if let surface = theme.surface {
                        LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(corner)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { column in
                                    squareView(column: column, row: row, size: sq)
                                }
                            }
                        }
                    }
                    // One tap for the whole board, read where the finger landed: a tall piece's
                    // head is drawn over the square behind it.
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let onTap, let tapped = tappedSquare(at: value.location, size: sq) else { return }
                        onTap(tapped)
                    })
                    ZStack {
                        ForEach(Array(hints.reversed())) { hint in
                            MoveArrow(
                                from: center(of: hint.from, size: sq),
                                to: center(of: hint.to, size: sq),
                                squareSize: sq,
                                isBest: hint.rank == 0,
                                color: hint.rank == 0 ? theme.bestArrow : theme.secondArrow,
                                glow: theme.arrowGlow
                            )
                            .transition(.opacity)
                        }
                }
                .frame(width: sq * 8, height: sq * 8)
                .animation(.easeInOut(duration: 0.25), value: hints)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                }
                .frame(width: sq * 8, height: sq * 8)
                .padding(inset)
                if theme.boardArt != nil, showsCoordinates {
                    FrameCoordinates(flipped: flipped, inset: inset, squareSize: sq, color: theme.frameLabel(on: colorScheme))
                }
            }
            .frame(width: side, height: side)
            .overlay {
                if let edge = theme.boardEdge {
                    corner.strokeBorder(edge, lineWidth: 1)
                }
            }
            .background {
                ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                    corner.fill(color)
                        .blur(radius: sq * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                        .offset(y: theme.isDark ? 0 : sq * 0.08)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func squareAt(column: Int, row: Int) -> Square {
        flipped ? Square(file: 7 - column, rank: row) : Square(file: column, rank: 7 - row)
    }

    private func center(of square: Square, size: CGFloat) -> CGPoint {
        BoardTapResolver.center(of: square, squareSize: size, flipped: flipped)
    }

    /// The square a tap on the squares means: see `BoardTapResolver`. With a piece picked up,
    /// a tap near one of its dots means that square.
    private func tappedSquare(at point: CGPoint, size: CGFloat) -> Square? {
        var isSolid: ((Piece, CGPoint) -> Bool)?
        if theme.spritePieces {
            let theme = theme
            isSolid = { piece, offset in SpriteMasks.shared.isSolid(piece, in: theme, at: offset) }
        }
        let draft = draft
        return BoardTapResolver.square(
            at: point, squareSize: size, flipped: flipped,
            selected: selected, targets: targets,
            piece: { square in draft[square]?.piece(at: square) }, isSolid: isSolid
        )
    }

    private func squareView(column: Int, row: Int, size: CGFloat) -> some View {
        let square = squareAt(column: column, row: row)
        let isLight = (square.fileIndex + square.rankIndex) % 2 == 1
        let labelColor = isLight ? theme.labelOnLight : theme.labelOnDark
        let token = draft[square]

        return ZStack {
            Rectangle().fill(theme.squareFill(isLight: isLight))
            if let tint = tints[square] {
                Rectangle().fill(tint)
            }
            if let gridLine = theme.gridLine {
                Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
            }
            // Coordinates in the corners, like a printed board. A board picture has them in its frame.
            if theme.boardArt == nil, showsCoordinates {
                if column == 0 {
                    label("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
                }
                if row == 7 {
                    label(square.file.rawValue, size: size, color: labelColor, alignment: .bottomTrailing)
                }
            }
            if let token {
                let isGhost = ghosts.contains(square)
                PieceImage(piece: token.piece(at: square), theme: theme, size: size, onBoard: true)
                    .opacity(isGhost ? 0.62 : 1)
                    .shadow(color: isGhost ? ghostColor.opacity(0.9) : .clear, radius: size * 0.12)
                    .scaleEffect(square == selected ? 1.08 : 1)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if targets.contains(square) {
                targetMark(capture: token != nil, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(token.map { "\(square.notation), \($0.piece(at: square).spokenName)" } ?? square.notation)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { onTap?(square) }
    }

    /// Where the piece picked up can go: a soft dot, or a ring around a piece it can take.
    @ViewBuilder
    private func targetMark(capture: Bool, size: CGFloat) -> some View {
        let ink: Color = Color.black.opacity(0.28)
        if capture {
            Circle()
                .strokeBorder(ink, lineWidth: size * 0.08)
                .padding(size * 0.04)
                .allowsHitTesting(false)
        } else {
            Circle()
                .fill(ink)
                .frame(width: size * 0.3, height: size * 0.3)
                .allowsHitTesting(false)
        }
    }

    private func label(_ text: String, size: CGFloat, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(.app(size: size * 0.2, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(size * 0.05)
    }
}
