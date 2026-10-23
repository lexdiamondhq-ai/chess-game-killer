import ChessKit
import Foundation

// Talk it through in training: a Talk button next to Hint and Show me on a find-the-move puzzle,
// in Leo's sessions and in rated puzzles. Leo never names the answer, a send counts like a hint,
// and Play makes the checked move as the learner's answer, judged like one made on the board.
// Rush and Cycles give no help, so they have no Talk.

extension DrillRunner {
    /// A talk about the puzzle's position, for the learner. Nil when Talk isn't on offer.
    func talkSession() -> TalkSession? {
        guard canTalkItThrough else { return nil }
        let session = TalkSession(fen: game.fen, player: learner, context: .session, reveal: false,
                                  lastMove: lastMoveUCI)
        session.onSend = { [weak self] in self?.talkedItThrough() }
        return session
    }
}
