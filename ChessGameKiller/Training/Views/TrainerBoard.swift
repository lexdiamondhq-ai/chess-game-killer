import ChessKit
import SwiftUI

/// A training screen's board, as in a game: the real 3D board, tilted with the pieces standing
/// or flat from above, when the look has one and 3D pieces are on; otherwise the flat board.
/// Under it, whose move it is (when the screen says) and the Tilted / Flat switch the game has.
/// Puzzles, lessons, the openings trainer and the Grandmaster Room all show their board this way.
struct TrainerBoard: View {
    let game: GameModel
    let theme: BoardTheme
    /// How wide the screen makes the flat board, which is as tall, keeping `TrainingBoardView.sideRoom`
    /// beside it. The 3D board takes that room too, edge to edge as in a game, and is a little
    /// less tall, being seen at an angle.
    let side: CGFloat
    var flipped = false
    var arrows: [BoardArrow] = []
    var marks: [SquareMark] = []
    var labels: [SquareLabel] = []
    /// Taps on squares. Nil makes the board look-only.
    var onTap: ((Square) -> Void)?
    /// Finishes a pawn's promotion with the piece chosen. While a pawn waits on the last rank,
    /// the board shows the picker (Queen, Rook, Bishop, Knight), as a game does; a tap beside
    /// it puts the pawn back.
    var onPromote: ((Piece.Kind) -> Void)?
    /// Whose move it is, shown under the board beside the switch. Nil shows none.
    var turn: Piece.Color?
    /// Whether the turn shows now; its place is kept when it doesn't, so nothing jumps.
    var showsTurn = true

    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.auto

    private var threeD: Bool { BoardView.playsIn3D(theme, setting: sculpted3D) }
    private var framing: SculptedCamera.Framing { tilt.framing(bigBoard: false) }

    var body: some View {
        VStack(spacing: 6) {
            board
                .overlay { promotionPicker }
                .animation(.snappy(duration: 0.2), value: game.pendingPromotion != nil)
            HStack(spacing: 8) {
                if let turn {
                    TurnBadge(theme: theme, side: turn, showing: showsTurn)
                }
                Spacer(minLength: 0)
                BoardViewSwitch(theme: theme)
            }
            .frame(width: side)
        }
    }

    @ViewBuilder
    private var promotionPicker: some View {
        if let onPromote, let promotion = game.pendingPromotion {
            GeometryReader { geo in
                PromotionPicker(
                    color: promotion.piece.color, theme: theme,
                    squareSize: min(geo.size.width / 8, geo.size.height / 6),
                    cancel: { game.undo() },
                    choose: onPromote
                )
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var board: some View {
        if threeD {
            // Another position (the next puzzle, a line started over) brings a fresh game whose
            // piece ids start over: a fresh board fades in over the old one, rather than the
            // pieces walking to new places.
            ZStack {
                SculptedTrainingBoard(game: game, theme: theme, flipped: flipped,
                                      arrows: arrows, marks: marks, labels: labels, onTap: onTap, framing: framing)
                    .transition(.opacity)
                    .id(ObjectIdentifier(game))
            }
            .animation(.easeInOut(duration: 0.25), value: ObjectIdentifier(game))
            .frame(width: DrillBoard.width3D(side: side),
                   height: DrillBoard.height3D(side: DrillBoard.width3D(side: side), framing: framing))
        } else {
            TrainingBoardView(game: game, theme: theme, flipped: flipped,
                              arrows: arrows, marks: marks, labels: labels, onTap: onTap)
                .frame(width: side, height: side)
                .boardHeadroom(theme: theme, side: side)
        }
    }
}
