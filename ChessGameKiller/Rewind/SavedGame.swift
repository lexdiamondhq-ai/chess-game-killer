import ChessKit
import Foundation

/// One of the player's moves as the coach graded it, kept with the game for Rewind.
struct SavedMoment: Codable, Equatable, Identifiable {
    /// The game's ply count once the move was on the board (1 is White's first move).
    let ply: Int
    let grade: String
    /// The move played, in standard and engine notation.
    let san: String
    let uci: String
    let byWhite: Bool
    let fenBefore: String
    let fenAfter: String
    /// The engine's choice, when it differs from the move played.
    var best: String?
    var bestUCI: String?
    /// The engine's whole line from the position before the move, best move first.
    var bestLine: [String] = []
    /// The opponent's best answer to the move played, in engine notation.
    var reply: String?
    /// Winning chances for the mover, -1 to 1, before and after the move.
    let before: Double
    let after: Double
    /// The engine's scores for the mover, so a missed mate can be named.
    var beforeEval: Evaluation?
    var afterEval: Evaluation?

    var id: Int { ply }

    var moveGrade: MoveReview.Grade { MoveReview.Grade(rawValue: grade) ?? .good }

    /// How much the move gave away, in winning chances.
    var loss: Double { max(0, before - after) }

    /// The coach's review of the move, so the pattern finder can name what happened.
    var review: MoveReview {
        MoveReview(
            id: ply, grade: moveGrade, played: san, best: best, evaluation: afterEval,
            fenBefore: fenBefore, fenAfter: fenAfter, playedUCI: uci, bestUCI: bestUCI,
            before: beforeEval, reply: reply
        )
    }

    /// "6. O-O" or "6... Nxd5".
    var numbered: String {
        let number = TrainingChess.moveNumber(fenBefore)
        return byWhite ? "\(number). \(san)" : "\(number)... \(san)"
    }
}

/// A finished game, kept on this device so it can be rewound.
struct SavedGame: Codable, Equatable, Identifiable {
    enum Result: String, Codable {
        case win, loss, draw, unfinished

        var title: String {
            switch self {
            case .win: return "Win"
            case .loss: return "Loss"
            case .draw: return "Draw"
            case .unfinished: return "Unfinished"
            }
        }
    }

    let id: UUID
    var date: Date
    /// The rival's name, or "Friend".
    let opponent: String
    /// The rival's level, for the portrait. Nil against a friend.
    let level: Int?
    let playerIsWhite: Bool
    var result: Result
    var accuracy: Int?
    /// Every position, the start first and the final one last.
    var positions: [String]
    /// Every move in standard notation; one fewer than the positions.
    var moves: [String]
    var moments: [SavedMoment]
    /// Plies the player has gone back and fixed.
    var rewritten: Set<Int> = []
    /// The time control, like "3+2", so a rematch is the same game. Nil in games saved before it was kept.
    var clock: String? = nil

    var playerColor: Piece.Color { playerIsWhite ? .white : .black }
    var finalFEN: String { positions.last ?? "" }
    var moveCount: Int { (moves.count + 1) / 2 }

    /// The player's moves, in order. Against a friend both sides count.
    var playerMoments: [SavedMoment] {
        moments
            .filter { level == nil || $0.byWhite == playerIsWhite }
            .sorted { $0.ply < $1.ply }
    }

    // MARK: The moments worth a stop

    /// Moves to go back and fix: the worst few that cost something and have a
    /// better move to find, in the order they were played.
    var toRewrite: [SavedMoment] {
        let costly = playerMoments.filter {
            [.inaccuracy, .mistake, .blunder].contains($0.moveGrade) && $0.bestUCI != nil
        }
        let worst = costly.sorted { $0.loss > $1.loss }.prefix(Self.maxToRewrite)
        return worst.sorted { $0.ply < $1.ply }
    }

    /// Moves to be proud of: a mate, and the best moves that gained the most.
    var highlights: [SavedMoment] {
        let moments = playerMoments
        var picked: [SavedMoment] = moments.filter { $0.moveGrade == .checkmate }
        var previous = 0.0
        var gains: [(SavedMoment, Double)] = []
        for moment in moments {
            gains.append((moment, moment.after - previous))
            previous = moment.after
        }
        let strong = gains
            .filter { [.best, .excellent].contains($0.0.moveGrade) && $0.1 > 0.12 }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
        picked.append(contentsOf: strong.filter { !picked.contains($0) })
        return picked
    }

    /// Every stop on the line, in the order played.
    var keyMoments: [SavedMoment] {
        let rewrite = toRewrite
        let proud = highlights.filter { moment in !rewrite.contains { $0.ply == moment.ply } }
        return (rewrite + proud).sorted { $0.ply < $1.ply }
    }

    var leftToRewrite: Int { toRewrite.filter { !rewritten.contains($0.ply) }.count }

    // MARK: The line

    /// Who was winning after each of the player's moves, from the player's side,
    /// -1 to 1, by ply. Starts level at ply 0.
    var lifeline: [(ply: Int, value: Double)] {
        var points: [(ply: Int, value: Double)] = [(0, 0)]
        for moment in moments.sorted(by: { $0.ply < $1.ply }) {
            let forWhite = moment.byWhite ? moment.after : -moment.after
            points.append((moment.ply, playerIsWhite ? forWhite : -forWhite))
        }
        if result != .unfinished, let last = points.last, last.ply < moves.count {
            // The final move was the opponent's: show how it ended.
            let end: Double = result == .win ? 1 : result == .loss ? -1 : 0
            points.append((moves.count, result == .draw ? last.value : end))
        }
        return points
    }

    /// The line's value at any ply, between the graded moves.
    func value(at ply: Int) -> Double {
        let points = lifeline
        guard let after = points.firstIndex(where: { $0.ply >= ply }) else { return points.last?.value ?? 0 }
        if after == 0 { return points[0].value }
        let a = points[after - 1], b = points[after]
        guard b.ply > a.ply else { return b.value }
        let t = Double(ply - a.ply) / Double(b.ply - a.ply)
        return a.value + (b.value - a.value) * t
    }

    // MARK: Ghost lines

    /// The better line from a moment, as positions after each move and the moves
    /// in standard notation. Stops at the first move that doesn't fit.
    static func ghostLine(for moment: SavedMoment, limit: Int = 4) -> (positions: [String], moves: [String], uci: [String]) {
        var line = moment.bestLine
        if line.isEmpty, let best = moment.bestUCI { line = [best] }
        var positions: [String] = []
        var played: [String] = []
        var fen = moment.fenBefore
        for uci in line.prefix(limit) {
            guard let san = Notation.san(of: uci, fen: fen), let next = TrainingChess.fen(after: [uci], from: fen) else { break }
            positions.append(next)
            played.append(san)
            fen = next
        }
        return (positions, played, Array(line.prefix(positions.count)))
    }

    static let maxToRewrite = 5
}

extension SavedGame {
    /// Builds a saved game from what the match kept.
    static func make(
        id: UUID, date: Date, opponent: String, level: Int?, playerColor: Piece.Color,
        winner: Piece.Color?, isOver: Bool, accuracy: Int?, positions: [String], moves: [String],
        moments: [SavedMoment], clock: TimeControl? = nil
    ) -> SavedGame {
        let result: Result
        if !isOver {
            result = .unfinished
        } else if let winner {
            result = winner == playerColor ? .win : .loss
        } else {
            result = .draw
        }
        return SavedGame(
            id: id, date: date, opponent: opponent, level: level, playerIsWhite: playerColor == .white,
            result: result, accuracy: accuracy, positions: positions, moves: moves, moments: moments,
            clock: clock?.rawValue
        )
    }
}
