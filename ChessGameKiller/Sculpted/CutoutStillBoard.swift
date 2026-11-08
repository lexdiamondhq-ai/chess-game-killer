import ChessKit
import SwiftUI

/// A position drawn small and still, as the 3D board shows it flat from above: the look's own
/// stone and the Floating Cut-outs, each with its soft shadow off to the right. For lists and
/// previews, where a live 3D board in every row would be too heavy. Nothing rises above the
/// squares. With 3D pieces off, or a look without a 3D board, it is the flat board.
struct CutoutStillBoard: View {
    let fen: String
    let theme: BoardTheme
    var flipped = false

    @AppStorage("sculpted3D") private var sculpted3D = true

    private var draft: PositionDraft { PositionDraft(fen: fen) ?? .standard }

    var body: some View {
        if let look = theme.sculptedLook, sculpted3D {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let square = side / 8
                ZStack(alignment: .topLeading) {
                    // Seen from Black's side the camera walks round the board, so the stone turns too.
                    Image(look.squares)
                        .resizable()
                        .interpolation(.high)
                        .rotationEffect(flipped ? .degrees(180) : .zero)
                        .frame(width: side, height: side)
                    ForEach(draft.pieces, id: \.square) { piece in
                        let center = center(of: piece.square, square: square)
                        let span = square * SculptedFlatSet.span
                        Image(SculptedFlatSet.shadowName(piece.kind))
                            .resizable()
                            .opacity(0.42)
                            .frame(width: span, height: span)
                            .position(x: center.x + square * CGFloat(SculptedFlatSet.shadowOffset.x),
                                      y: center.y + square * CGFloat(SculptedFlatSet.shadowOffset.y))
                        Image(SculptedFlatSet.pictureName(piece.kind, color: piece.color))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: span, height: span)
                            .position(center)
                    }
                }
                .frame(width: side, height: side)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        } else {
            PositionBoard(draft: draft, theme: theme, flipped: flipped)
                .accessibilityHidden(true)
        }
    }

    private func center(of square: Square, square size: CGFloat) -> CGPoint {
        let column = flipped ? 7 - square.fileIndex : square.fileIndex
        let row = flipped ? square.rankIndex : 7 - square.rankIndex
        return CGPoint(x: (CGFloat(column) + 0.5) * size, y: (CGFloat(row) + 0.5) * size)
    }
}
