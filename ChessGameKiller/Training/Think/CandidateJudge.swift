import ChessKit
import Foundation

/// Leo's word for a move, instead of a number: how the position looks for the
/// player after it, from "mates" down to "allows mate".
enum CandidateVerdict: Int, Comparable, CaseIterable {
    case allowsMate, losesMaterial, worse, equal, edge, wins, mates

    /// Reads an evaluation of the position after the move, from the mover's side.
    init(_ evaluation: Evaluation) {
        switch evaluation {
        case .mate(let moves):
            self = moves > 0 ? .mates : .allowsMate
        case .centipawns(let cp):
            if cp >= 250 {
                self = .wins
            } else if cp >= 70 {
                self = .edge
            } else if cp > -70 {
                self = .equal
            } else if cp > -250 {
                self = .worse
            } else {
                self = .losesMaterial
            }
        }
    }

    var words: String {
        switch self {
        case .mates: return "mates"
        case .wins: return "wins"
        case .edge: return "keeps an edge"
        case .equal: return "about equal"
        case .worse: return "leaves you worse"
        case .losesMaterial: return "loses material"
        case .allowsMate: return "allows mate"
        }
    }

    /// Green for the moves that win, orange and red for the ones that hurt, and
    /// nil (plain text) for the playable moves in between.
    var color: TrainingColor? {
        switch self {
        case .mates, .wins: return .green
        case .edge, .equal: return nil
        case .worse: return .orange
        case .losesMaterial, .allowsMate: return .red
        }
    }

    static func < (lhs: CandidateVerdict, rhs: CandidateVerdict) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Leo's answer to a list of candidate moves: every move worth naming with its
/// verdict, what the list scored, and one line on what it teaches.
struct CandidateReport: Equatable {
    /// One move in the answer: the winner, one of Leo's top three, or one of the player's.
    struct Row: Equatable, Identifiable {
        /// Engine notation, like "e3f4".
        let uci: String
        /// Standard notation, like "Bf4".
        let san: String
        /// Nil when Leo couldn't judge the move.
        let verdict: CandidateVerdict?
        /// The puzzle's answer: the move that wins.
        let isWinner: Bool
        /// Its place in Leo's top three, from 0. Nil when it isn't there, or there was no engine.
        let leoRank: Int?
        /// Its place on the player's list, from 0. Nil when the player didn't list it.
        let listed: Int?

        var id: String { uci }

        /// The player listed it, and it was the winner or one of Leo's top three.
        var isMatch: Bool { listed != nil && (isWinner || leoRank != nil) }
    }

    /// The winner first, then the other moves from strongest to weakest.
    let rows: [Row]
    /// Where the winner was on the player's list, from 0. Nil when it wasn't on it.
    let foundAt: Int?
    /// The player's other moves that were in Leo's top three.
    let otherMatches: Int
    let points: Int
    /// Whether the engine judged the moves. Without it only the puzzle's answer counts.
    let usedEngine: Bool
    /// Leo's one line on the list.
    let takeaway: String

    var winner: Row? { rows.first { $0.isWinner } }
}

/// Checks a list of candidate moves against the puzzle's answer and the engine's
/// best moves. Scoring: the winner on the list is worth 2, and 1 more when it was
/// the first idea; each other move from Leo's top three is worth 1.
enum CandidateJudge {
    /// How many of the engine's best moves count as serious candidates.
    static let topCount = 3
    /// The most one position can score: the winner first, plus two more of Leo's top three.
    static let maxPoints = 5

    /// Whether two moves in engine notation are the same move. A promotion on the
    /// same square counts as one move, whatever piece it makes.
    static func same(_ a: String, _ b: String) -> Bool {
        a == b || (a.count == 5 && b.count == 5 && a.prefix(4) == b.prefix(4))
    }

    /// Judges the player's list.
    /// - Parameters:
    ///   - fen: the position the moves are played from.
    ///   - winner: the puzzle's answer.
    ///   - candidates: the player's moves, in the order they were listed.
    ///   - lines: the engine's best lines from `fen`, best first. Empty when there was no engine.
    ///   - extra: the engine's view of listed moves that aren't in `lines`, from the mover's side.
    ///   - mate: whether the puzzle is a mate puzzle, so its answer mates.
    static func report(fen: String, winner: String, candidates: [String], lines: [EngineLine],
                       extra: [String: Evaluation] = [:], mate: Bool = false) -> CandidateReport {
        let usedEngine = !lines.isEmpty
        var top: [String] = []
        for line in lines {
            guard let move = line.firstMove, !top.contains(where: { same($0, move) }) else { continue }
            top.append(move)
            if top.count == topCount { break }
        }

        func evaluation(of move: String) -> Evaluation? {
            if let line = lines.first(where: { $0.firstMove.map { same($0, move) } ?? false }) {
                return line.evaluation
            }
            return extra.first { same($0.key, move) }?.value
        }
        func listed(_ move: String) -> Int? { candidates.firstIndex { same($0, move) } }
        func rank(_ move: String) -> Int? { usedEngine ? top.firstIndex { same($0, move) } : nil }

        // The winner, then (when the engine judged them) Leo's top three and the player's other moves.
        var moves = [winner]
        if usedEngine {
            for move in top + candidates where !moves.contains(where: { same($0, move) }) {
                moves.append(move)
            }
        }
        let rows = moves.map { move -> CandidateReport.Row in
            let isWinner = same(move, winner)
            var verdict = usedEngine ? evaluation(of: move).map(CandidateVerdict.init) : nil
            if isWinner {
                // The puzzle's answer wins, whatever a short search made of it.
                verdict = mate || verdict == .mates ? .mates : .wins
            }
            return CandidateReport.Row(uci: move, san: Notation.san(of: move, fen: fen) ?? move, verdict: verdict,
                                       isWinner: isWinner, leoRank: rank(move), listed: listed(move))
        }
        let strength = { (row: CandidateReport.Row) -> Double in
            evaluation(of: row.uci)?.winningChances ?? -2
        }
        let rest = rows.dropFirst().enumerated().sorted { a, b in
            let (first, second) = (strength(a.element), strength(b.element))
            return first == second ? a.offset < b.offset : first > second
        }.map(\.element)

        let foundAt = listed(winner)
        let otherMatches = candidates.filter { !same($0, winner) && rank($0) != nil }.count
        let points = (foundAt == nil ? 0 : 2) + (foundAt == 0 ? 1 : 0) + otherMatches
        let winnerSAN = rows.first?.san ?? winner
        return CandidateReport(
            rows: Array(rows.prefix(1)) + rest,
            foundAt: foundAt,
            otherMatches: otherMatches,
            points: points,
            usedEngine: usedEngine,
            takeaway: takeaway(foundAt: foundAt, listed: candidates.count, winner: winnerSAN,
                               forcing: isForcing(winner, fen: fen))
        )
    }

    /// Leo's one line on where the winner was on the list.
    static func takeaway(foundAt: Int?, listed: Int, winner: String, forcing: Bool) -> String {
        switch foundAt {
        case 0? where listed == 1:
            return "You saw \(winner) at once. Still list two or three moves; it's the habit that counts."
        case 0?:
            return "Your first idea, \(winner), wins. Weighing the others is what makes it safe."
        case 1?:
            return "You found it as your second candidate: always list more than one."
        case 2?:
            return "Your third candidate won. That's exactly why we list three."
        default:
            return forcing
                ? "The winner was \(winner). Look at every check and capture before anything else."
                : "The winner was the quiet \(winner). After checks and captures, look for threats."
        }
    }

    /// Whether a move gives check or captures.
    static func isForcing(_ uci: String, fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        var board = Board(position: position)
        guard let move = TrainingChess.play(uci, on: &board) else { return false }
        return TrainingChess.givesCheck(move) || TrainingChess.isCapture(move)
    }

    /// The verdict on a move that ends the game: mate, or a stalemate's draw. Nil
    /// for any other move, which the engine has to judge.
    static func finalEvaluation(of uci: String, in fen: String) -> Evaluation? {
        guard let position = Position(fen: fen) else { return nil }
        var board = Board(position: position)
        guard TrainingChess.play(uci, on: &board) != nil else { return nil }
        switch board.state {
        case .checkmate: return .mate(1)
        case .draw(reason: .stalemate): return .centipawns(0)
        default: return nil
        }
    }
}

/// A round of the candidates drill: five positions and what they scored.
struct CandidateRound: Equatable {
    static let length = 5
    static var maxPoints: Int { length * CandidateJudge.maxPoints }

    private(set) var reports: [CandidateReport] = []

    var points: Int { reports.reduce(0) { $0 + $1.points } }
    /// Positions where the winner was on the list.
    var found: Int { reports.filter { $0.foundAt != nil }.count }
    /// Positions where the winner was the first idea.
    var foundFirst: Int { reports.filter { $0.foundAt == 0 }.count }
    var isFinished: Bool { reports.count >= Self.length }

    mutating func add(_ report: CandidateReport) {
        guard !isFinished else { return }
        reports.append(report)
    }

    /// Leo's line at the end of the round.
    var summary: String {
        switch found {
        case 5...:
            return "Five winners out of five. Your list never let you down."
        case 4:
            return "Four winners out of five. The habit is working."
        case 3:
            return "Three winners out of five. The habit is working."
        case 2:
            return "Two winners out of five. Start each list with checks, captures and threats."
        case 1:
            return "One winner out of five. Start each list with checks, captures and threats."
        default:
            return "No winners this time. Next round, start each list with checks, captures and threats."
        }
    }
}
