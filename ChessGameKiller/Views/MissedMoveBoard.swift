import ChessKit
import SwiftUI

/// The better move the person missed, ready to show on the board: the position before their move,
/// and the same position with the better move played. Made from the coach's verdict when the
/// person taps it (Alex, 2026-11-24).
struct MissedMove: Identifiable, Equatable {
    /// The verdict it came from, so tapping the same verdict again plays it again.
    let id: Int
    let before: PositionDraft
    let after: PositionDraft
    let from: Square
    let to: Square
    /// The move the person played instead, like "Bc4".
    let played: String

    /// Nil when the verdict has no better move, or it cannot be played out.
    init?(_ review: MoveReview) {
        guard review.best != nil, let fen = review.fenBefore, let uci = review.bestUCI,
              let squares = Notation.squares(of: uci),
              let before = PositionDraft(fen: fen), let position = Position(fen: fen)
        else { return nil }
        var board = Board(position: position)
        guard board.move(pieceAt: squares.from, to: squares.to) != nil else { return nil }
        if case .promotion(let pawnMove) = board.state {
            _ = board.completePromotion(of: pawnMove, to: Notation.promotionKind(uci))
        }
        guard let after = PositionDraft(fen: board.position.fen) else { return nil }
        id = review.id
        self.before = before
        self.after = after
        from = squares.from
        to = squares.to
        played = review.played
    }

    /// Whether a verdict has a better move to show, without playing it out.
    static func exists(for review: MoveReview) -> Bool {
        review.best != nil && review.fenBefore != nil && review.bestUCI != nil
    }
}

/// Laid over the live board for a few seconds after the person taps the coach's verdict: the board
/// softly goes back to the moment before their move, the better move's arrow fades in, and the
/// piece glides along it, see-through, to where it should have gone. Then it all fades back to
/// the game. A tap on the board ends it early.
struct MissedMoveBoard: View {
    let missed: MissedMove
    let theme: BoardTheme
    let flipped: Bool
    let in3D: Bool
    let framing: SculptedCamera.Framing
    let close: () -> Void

    @State private var showsArrow = false
    @State private var glided = false

    /// When the arrow fades in, when the piece glides, and how long it all stays after.
    static let arrowDelay: Double = 0.45
    static let glideDelay: Double = 0.75
    static let holdSeconds: Double = 2.3

    var body: some View {
        board
            .overlay(alignment: .bottom) {
                caption
                    // Just under the board, over the moves, as in the picture Alex picked.
                    .alignmentGuide(.bottom) { $0[.top] - 10 }
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { close() })
            .task(id: missed.id) { await play() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before \(missed.played). \(missed.from.notation) to \(missed.to.notation) was the better move.")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Goes back to the game.")
            .accessibilityAction { close() }
    }

    @ViewBuilder private var board: some View {
        if in3D {
            SculptedPositionBoard(
                pieces: (glided ? missed.after : missed.before).pieces,
                theme: theme, flipped: flipped,
                arrows: showsArrow ? [SculptedCoachArrow(from: missed.from, to: missed.to, color: ArrowColors.best, analysis: true, best: true)] : [],
                framing: framing
            )
        } else {
            PositionBoard(
                draft: glided ? missed.after : missed.before,
                theme: theme, flipped: flipped,
                hints: showsArrow ? [hint] : [],
                ghosts: glided ? [missed.to] : [],
                ghostColor: Color(hex: ArrowColors.bestTail)
            )
        }
    }

    /// The better move, drawn as the analysis board's best arrow.
    private var hint: MoveHint {
        MoveHint(rank: 0, from: missed.from, to: missed.to, san: "", uci: "", evaluation: .centipawns(0))
    }

    /// Which moment this is, in a small glass capsule.
    private var caption: some View {
        Text("Before \(missed.played)")
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassPane(Capsule())
            .opacity(showsArrow ? 1 : 0)
    }

    private func play() async {
        showsArrow = false
        glided = false
        try? await Task.sleep(for: .seconds(Self.arrowDelay))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.5)) { showsArrow = true }
        try? await Task.sleep(for: .seconds(Self.glideDelay))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { glided = true }
        try? await Task.sleep(for: .seconds(Self.holdSeconds))
        guard !Task.isCancelled else { return }
        close()
    }
}
