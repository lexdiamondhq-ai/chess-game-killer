import ChessKit
import Foundation

/// The coach's verdict on the move just played, shown at the bottom of the screen.
struct MoveReview: Equatable, Identifiable {
    enum Grade: String, CaseIterable {
        case checkmate, best, excellent, good, inaccuracy, mistake, blunder
    }

    let id: Int
    let grade: Grade
    /// The move that was played, like "Nf3".
    let played: String
    /// The engine's choice, when it differs from the played move.
    let best: String?
    /// The position after the move, from the mover's point of view.
    let evaluation: Evaluation?

    // What the training coach needs to name the pattern behind the move.
    var fenBefore: String? = nil
    var fenAfter: String? = nil
    /// The move played and the engine's choice, in engine notation.
    var playedUCI: String? = nil
    var bestUCI: String? = nil
    /// The position before the move, from the mover's point of view.
    var before: Evaluation? = nil
    /// The opponent's best answer to the move played, in engine notation.
    var reply: String? = nil
    /// Where the moving piece started the game, so the army can name it.
    var origin: Square? = nil

    var title: String {
        switch grade {
        case .checkmate: return "Checkmate!"
        case .best: return "Best move"
        case .excellent: return "Excellent"
        case .good: return "Good move"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        }
    }

    var detail: String {
        let better = best ?? "another move"
        switch grade {
        case .checkmate: return "\(played) ends the game. Beautiful."
        case .best: return "\(played) is exactly what Stockfish would play."
        case .excellent: return "\(played) is nearly as strong as \(better)."
        case .good: return "\(played) is fine. \(better) was a little stronger."
        case .inaccuracy: return "\(played) lets some advantage slip. \(better) was better."
        case .mistake: return "\(played) loses ground. \(better) was much better."
        case .blunder: return "\(played) gives away a lot. \(better) was the move."
        }
    }

    /// Grades a move by how much it lowered the mover's chance of winning
    /// (Lichess's scale: 0.1 is an inaccuracy, 0.2 a mistake, 0.3 a blunder).
    static func grade(before: Evaluation, after: Evaluation, playedBest: Bool) -> Grade {
        if playedBest { return .best }
        let loss = before.winningChances - after.winningChances
        switch loss {
        case ..<0.04: return .excellent
        case ..<0.10: return .good
        case ..<0.20: return .inaccuracy
        case ..<0.30: return .mistake
        default: return .blunder
        }
    }
}

/// One of the two best moves drawn as an arrow. Rank 0 is the best.
struct MoveHint: Equatable, Identifiable {
    let rank: Int
    let from: Square
    let to: Square
    let san: String
    /// Engine notation, like "e1g1", so the move can be played on request.
    let uci: String
    /// The position after this move, from the mover's point of view.
    let evaluation: Evaluation

    var id: Int { rank }
}

/// Converts between engine notation ("g1f3") and what people read ("Nf3").
enum Notation {
    static func squares(of uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4 else { return nil }
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        guard isSquare(from), isSquare(to) else { return nil }
        return (Square(from), Square(to))
    }

    /// Standard notation for an engine move in the given position, or nil if it isn't legal there.
    static func san(of uci: String, fen: String) -> String? {
        guard let position = Position(fen: fen), let squares = squares(of: uci) else { return nil }
        var board = Board(position: position)
        guard let move = board.move(pieceAt: squares.from, to: squares.to) else { return nil }
        if case .promotion(let pawnMove) = board.state {
            return board.completePromotion(of: pawnMove, to: promotionKind(uci)).san
        }
        return move.san
    }

    /// An engine line in standard notation, like ["Nf3", "Nc6", "d4"], stopping at the first move that doesn't fit.
    static func sanLine(of moves: [String], fen: String, limit: Int = 6) -> [String] {
        guard let position = Position(fen: fen) else { return [] }
        var board = Board(position: position)
        var line: [String] = []
        for uci in moves.prefix(limit) {
            guard let squares = squares(of: uci), let move = board.move(pieceAt: squares.from, to: squares.to) else { break }
            if case .promotion(let pawnMove) = board.state {
                line.append(board.completePromotion(of: pawnMove, to: promotionKind(uci)).san)
            } else {
                line.append(move.san)
            }
        }
        return line
    }

    /// Numbers a line for reading: "1. Nf3 Nc6 2. d4", or "1... Nc6 2. d4" when black moves first.
    static func numbered(_ line: [String], blackFirst: Bool) -> String {
        var parts: [String] = []
        var number = 1
        var whiteToMove = !blackFirst
        for (index, san) in line.enumerated() {
            if whiteToMove {
                parts.append("\(number). \(san)")
            } else if index == 0 {
                parts.append("\(number)... \(san)")
            } else {
                parts.append(san)
            }
            if !whiteToMove { number += 1 }
            whiteToMove.toggle()
        }
        return parts.joined(separator: " ")
    }

    private static func promotionKind(_ uci: String) -> Piece.Kind {
        if uci.count == 5, let letter = uci.last, let kind = Piece.Kind(rawValue: letter.uppercased()) {
            return kind
        }
        return .queen
    }

    private static func isSquare(_ text: String) -> Bool {
        let files: ClosedRange<Character> = "a"..."h"
        let ranks: ClosedRange<Character> = "1"..."8"
        guard text.count == 2, let file = text.first, let rank = text.last else { return false }
        return files.contains(file) && ranks.contains(rank)
    }
}
