import ChessKit
import Foundation

/// The coach's verdict on the move just played.
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
        case .checkmate: return "Checkmate"
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
        case .checkmate: return "\(played) ends it."
        case .best: return "\(played) is the engine's first choice."
        case .excellent: return "\(played) is nearly as strong as \(better)."
        case .good: return "\(played) is fine. \(better) was a little stronger."
        case .inaccuracy: return "\(played) gives a little back. \(better) was better."
        case .mistake: return "\(played) loses ground. \(better) was much better."
        case .blunder: return "\(played) gives away a lot. \(better) was the move."
        }
    }

    /// Grades a move by what it cost the mover, taking the harshest of three readings:
    ///
    /// - The drop in winning chances (Lichess's scale: 0.1 is an inaccuracy, 0.2 a mistake,
    ///   0.3 a blunder). Right in a level game, but the curve goes flat once a side is far
    ///   ahead (it stops at ten pawns), so on its own it called hanging a piece "Excellent"
    ///   and walking into mate "Good" whenever the game was already lopsided.
    /// - Allowing a forced mate is a blunder, however bad things already were.
    /// - Material the engine's own lines say the move gives away (`materialLoss`, in pawns,
    ///   from `materialLoss(fen:best:played:)`): a piece is a blunder, two pawns a mistake,
    ///   a pawn an inaccuracy. It only counts when the engine also scores the move worse,
    ///   so a sound sacrifice isn't punished. A move that leaves the mover clearly winning
    ///   is at worst a mistake by this reading: it gave a lot back without throwing the game.
    static func grade(before: Evaluation, after: Evaluation, playedBest: Bool, materialLoss: Int? = nil) -> Grade {
        if playedBest { return .best }
        var result = grade(chanceLoss: before.winningChances - after.winningChances)
        if after.isGettingMated, !before.isGettingMated {
            result = .blunder
        }
        if let materialLoss, before.centipawnsForGrading - after.centipawnsForGrading > 20 {
            var byMaterial: Grade
            switch materialLoss {
            case 3...: byMaterial = .blunder
            case 2: byMaterial = .mistake
            case 1: byMaterial = .inaccuracy
            default: byMaterial = .excellent
            }
            if after.isClearlyWinning, byMaterial == .blunder { byMaterial = .mistake }
            result = worse(result, byMaterial)
        }
        return result
    }

    private static func grade(chanceLoss loss: Double) -> Grade {
        switch loss {
        case ..<0.04: return .excellent
        case ..<0.10: return .good
        case ..<0.20: return .inaccuracy
        case ..<0.30: return .mistake
        default: return .blunder
        }
    }

    /// Grades are declared from best to worst.
    private static func worse(_ a: Grade, _ b: Grade) -> Grade {
        let order = Grade.allCases
        return (order.firstIndex(of: a) ?? 0) >= (order.firstIndex(of: b) ?? 0) ? a : b
    }

    /// How many pawns' worth of material the played line ends up behind the best line,
    /// for the side to move in `fen`. Both lines start from `fen`: `best` is the engine's
    /// line, `played` is the move played followed by the engine's line after it.
    ///
    /// Material is compared after 2, 4 and 6 moves (each side's turn done) and the
    /// smallest gap counts, so a trade that is just a move further along in one line
    /// than the other isn't mistaken for a loss. A piece really given away stays missing
    /// at every step. Nil when either line is too short to tell.
    static func materialLoss(fen: String, best: [String], played: [String]) -> Int? {
        let horizon = min(6, best.count, played.count)
        guard horizon >= 2 else { return nil }
        var smallest: Int?
        for plies in stride(from: 2, through: horizon, by: 2) {
            guard let mine = Notation.materialLead(after: Array(best.prefix(plies)), from: fen),
                  let theirs = Notation.materialLead(after: Array(played.prefix(plies)), from: fen) else { break }
            smallest = min(smallest ?? .max, mine - theirs)
        }
        return smallest
    }
}

private extension Evaluation {
    /// Centipawns with mates as 20 pawns, to tell whether the engine scores a move worse at all.
    var centipawnsForGrading: Int {
        switch self {
        case .centipawns(let cp): return cp
        case .mate(let n): return n > 0 ? 2000 : -2000
        }
    }

    var isGettingMated: Bool {
        if case .mate(let n) = self { return n <= 0 }
        return false
    }

    var isClearlyWinning: Bool {
        switch self {
        case .centipawns(let cp): return cp >= 500
        case .mate(let n): return n > 0
        }
    }
}

/// One of the two best moves, marked on the board. Rank 0 is the best.
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
    /// `from` is the move number the line starts on.
    static func numbered(_ line: [String], blackFirst: Bool, from first: Int = 1) -> String {
        var parts: [String] = []
        var number = max(first, 1)
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

    /// How far the side to move in `fen` is ahead in material, in pawns, once `moves`
    /// are played. Nil when a move doesn't fit.
    static func materialLead(after moves: [String], from fen: String) -> Int? {
        guard let position = Position(fen: fen) else { return nil }
        let mover = position.sideToMove
        var board = Board(position: position)
        for uci in moves {
            guard let squares = squares(of: uci), board.move(pieceAt: squares.from, to: squares.to) != nil else { return nil }
            if case .promotion(let pawnMove) = board.state {
                _ = board.completePromotion(of: pawnMove, to: promotionKind(uci))
            }
        }
        return board.position.pieces.reduce(0) { total, piece in
            total + (pieceValues[piece.kind] ?? 0) * (piece.color == mover ? 1 : -1)
        }
    }

    private static let pieceValues: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9]

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
