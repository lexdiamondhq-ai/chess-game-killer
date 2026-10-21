import Foundation

/// How good a position is, from the point of view of the side to move.
enum Evaluation: Equatable, Sendable, Codable {
    /// Hundredths of a pawn. +100 means the side to move is a pawn ahead.
    case centipawns(Int)
    /// Forced mate. Positive: the side to move mates in n. Zero or negative: it gets mated.
    case mate(Int)

    /// The same position seen from the other side.
    var flipped: Evaluation {
        switch self {
        case .centipawns(let cp): return .centipawns(-cp)
        case .mate(let n): return .mate(-n)
        }
    }

    /// Chance of winning between -1 (lost) and 1 (won), the same curve Lichess uses
    /// to judge moves. Mates count as fully won or lost.
    var winningChances: Double {
        switch self {
        case .mate(let n):
            return n > 0 ? 1 : -1
        case .centipawns(let cp):
            let clamped = Double(max(-1000, min(1000, cp)))
            return 2 / (1 + exp(-0.00368208 * clamped)) - 1
        }
    }

    /// Short label like "+1.3", "-0.4" or "M3".
    var label: String {
        switch self {
        case .centipawns(let cp):
            let pawns = Double(cp) / 100
            return pawns >= 0 ? String(format: "+%.1f", pawns) : String(format: "%.1f", pawns)
        case .mate(let n):
            return n > 0 ? "M\(n)" : "-M\(abs(n))"
        }
    }
}

/// One line the engine found: the moves it expects, best first, and the score after them.
struct EngineLine: Equatable, Sendable {
    /// Moves in engine notation, like "e2e4" or "e7e8q".
    let moves: [String]
    let evaluation: Evaluation

    var firstMove: String? { moves.first }
}
