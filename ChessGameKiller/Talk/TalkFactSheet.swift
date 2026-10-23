import ChessKit
import Foundation

/// Stockfish's numbers for one talk, worked out while the player speaks: every legal move scored
/// (up to 40), and the opponent's best moves if it were their turn, which is what a threat is.
/// The server checks the player's claims against these; it never runs an engine itself.
enum TalkFactSheet {
    static let depth = 12
    /// Enough to cover any move a player would name; the rest are never the point.
    static let maxMoves = 40
    static let threatLines = 6
    static let movesTimeMs = 3000
    static let threatsTimeMs = 1500

    /// The numbers for `fen`, from the side to move's view. Nil when the FEN isn't a position,
    /// the side to move has no moves, or the engine had nothing to say.
    static func compute(fen: String, engine: ChessEngine) async -> TalkFacts? {
        guard !Task.isCancelled, let position = Position(fen: fen) else { return nil }
        let count = legalMoveCount(in: Board(position: position))
        guard count > 0 else { return nil }
        // ChessKit judges check for the side that just moved, so ask the draft, as GameModel does.
        let inCheck = PositionDraft(fen: fen)?.isInCheck(position.sideToMove) ?? false

        // One search after the other: the shared engine runs one at a time, and a new search
        // stops the one before it.
        let scored = await engine.analyze(fen: fen, depth: depth, lines: min(count, maxMoves), maxTimeMs: movesTimeMs)
        guard !Task.isCancelled else { return nil }
        let moves = scored.compactMap { TalkFactLine($0) }
        guard !moves.isEmpty else { return nil }

        // In check there is no "if it were their turn": the check is the threat.
        var threats: [TalkFactLine] = []
        if !inCheck, let passed = nullMoveFEN(fen), Position(fen: passed) != nil {
            let lines = await engine.analyze(fen: passed, depth: depth, lines: threatLines, maxTimeMs: threatsTimeMs)
            guard !Task.isCancelled else { return nil }
            threats = lines.compactMap { TalkFactLine($0) }
        }
        return TalkFacts(depth: depth, moves: moves, threats: threats)
    }

    /// The same position with the other side to move: what the opponent would play if the player
    /// passed. En passant goes (it belonged to the player's turn); castling stays; after black
    /// passes it is the next move number. Nil when the FEN has no side to move to flip.
    static func nullMoveFEN(_ fen: String) -> String? {
        var fields = fen.split(separator: " ").map(String.init)
        guard fields.count >= 2, fields[1] == "w" || fields[1] == "b" else { return nil }
        // A short FEN gets the fields it left out, so the result is always whole.
        let defaults = ["-", "-", "0", "1"]
        while fields.count < 6 {
            fields.append(defaults[fields.count - 2])
        }
        let blackPassed = fields[1] == "b"
        fields[1] = blackPassed ? "w" : "b"
        fields[3] = "-"
        if blackPassed, let number = Int(fields[5]) {
            fields[5] = String(number + 1)
        }
        return fields.prefix(6).joined(separator: " ")
    }

    /// Legal moves as the engine counts them: a promotion is four moves (queen, rook, bishop, knight).
    static func legalMoveCount(in board: Board) -> Int {
        TrainingChess.legalMoves(in: board).reduce(0) { count, uci in
            count + (uci.count == 5 ? 4 : 1)
        }
    }
}
