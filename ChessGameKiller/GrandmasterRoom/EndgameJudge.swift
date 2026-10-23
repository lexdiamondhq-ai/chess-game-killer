import ChessKit
import Foundation

/// Who judged the last move of a Perfect Endgame.
enum EndgameJudgeKind: Equatable, Sendable {
    /// The Lichess tablebase: perfect knowledge of every position with seven pieces or fewer.
    case tablebase
    /// Stockfish on the phone. `offline` when the tablebase couldn't be reached.
    case engine(offline: Bool)

    /// The quiet line under the board.
    var label: String {
        switch self {
        case .tablebase: return "Judged by the tablebase"
        case .engine(let offline): return offline ? "Judged by Stockfish, offline" : "Judged by Stockfish"
        }
    }
}

/// What a judge says about a position, for the side to move.
struct EndgameAssessment: Equatable, Sendable {
    let judge: EndgameJudgeKind
    /// The tablebase's exact result: +1 win, 0 draw, -1 loss. Nil when Stockfish judged.
    let outcome: Int?
    /// Stockfish's score. Nil when the tablebase judged.
    let evaluation: Evaluation?
    /// The best move, in engine notation; nil when there is none.
    let best: String?
    /// Moves to mate with best play, when known: positive when the side to move mates.
    let mate: Int?

    init(judge: EndgameJudgeKind, outcome: Int? = nil, evaluation: Evaluation? = nil, best: String?, mate: Int? = nil) {
        self.judge = judge
        self.outcome = outcome
        self.evaluation = evaluation
        self.best = best
        self.mate = mate
    }

    init(tablebase result: TablebaseResult) {
        self.init(judge: .tablebase, outcome: result.value, best: result.moves.first?.uci, mate: result.mateInMoves)
    }

    init(engine line: EngineLine, offline: Bool) {
        var mate: Int?
        if case .mate(let moves) = line.evaluation { mate = moves }
        self.init(judge: .engine(offline: offline), evaluation: line.evaluation, best: line.firstMove, mate: mate)
    }
}

/// How Stockfish's scores are read when there is no tablebase to ask.
///
/// A move is a slip when two things are true: Stockfish's score after it has fallen to the
/// next result down (no longer winning, or now losing), and it fell a long way from the score
/// before it. The second test keeps engine noise from crying wolf: in a fortress, where the
/// engine overrates the attacker, a sound move keeps the score where it was and is never
/// called a slip.
///
/// The numbers were tuned against the tablebase with scripts/grandmaster/calibrate_offline_judge.py,
/// at a deliberately weak 300,000 nodes a move: over 7,000 moves from these studies, no sound
/// move was called a slip and every slip was caught. Sound winning moves never scored below
/// +1.46, sound drawing moves never below -0.86; slips sat at +0.44 or less, and -2.33 or less.
enum EngineReferee {
    /// For a win: a score (in centipawns, for the player) at or below this no longer wins.
    static let notWinning = 90
    /// For a draw: a score at or below this loses.
    static let losing = -180
    /// How far the move must drop the player's winning chances (on Lichess's -1 to 1 scale).
    static let drop = 0.2

    /// Whether the player's move gave up the goal. Both scores are from the player's side:
    /// `played` after the move, `reference` before it (nil when unknown).
    static func isSlip(goal: EndgameStudy.Goal, played: Evaluation, reference: Evaluation?) -> Bool {
        if case .mate(let moves) = played {
            // Mating is never a slip; being mated always is.
            return moves <= 0
        }
        guard case .centipawns(let score) = played else { return false }
        let before = reference?.winningChances ?? (goal == .win ? 1 : 0)
        let fell = before - played.winningChances >= drop
        switch goal {
        case .win: return score <= notWinning && fell
        case .draw: return score <= losing && fell
        }
    }

    /// Whether a score, for the player, looks lost rather than drawn.
    static func looksLost(_ evaluation: Evaluation) -> Bool {
        switch evaluation {
        case .mate(let moves): return moves <= 0
        case .centipawns(let score): return score <= losing
        }
    }
}

/// Judges Perfect Endgames: the Lichess tablebase whenever it can be reached, and Stockfish on
/// the phone when it can't (or when the position has more than seven pieces).
@MainActor
final class EndgameJudge {
    /// How long Stockfish looks at each position, and how deep at most.
    static let engineTimeMs = 1200
    static let engineDepth = 30

    private let tablebase: TablebaseProbing?
    private let engine: ChessEngine?
    /// Set when the tablebase fails, so the rest of the study doesn't wait on it again.
    private(set) var tablebaseUnreachable = false

    init(tablebase: TablebaseProbing?, engine: ChessEngine?) {
        self.tablebase = tablebase
        self.engine = engine
    }

    /// The judges the app uses: Lichess online, Stockfish on the phone otherwise.
    static func live() -> EndgameJudge {
        EndgameJudge(tablebase: LichessTablebase(), engine: StockfishEngine.shared)
    }

    /// Whether Stockfish is standing in for the tablebase because it couldn't be reached.
    var isOffline: Bool { tablebase == nil || tablebaseUnreachable }

    /// Gives the tablebase another chance, for a fresh attempt at a study.
    func retryTablebase() {
        tablebaseUnreachable = false
    }

    /// What the position is worth for the side to move, and its best move. Nil when neither
    /// judge could answer.
    func assess(_ fen: String) async -> EndgameAssessment? {
        if let tablebase, !tablebaseUnreachable, Tablebase.covers(fen) {
            do {
                return EndgameAssessment(tablebase: try await tablebase.probe(fen))
            } catch {
                if Task.isCancelled { return nil }
                tablebaseUnreachable = true
                NSLog("Perfect Endgames: tablebase unavailable, Stockfish judges instead: %@", "\(error)")
            }
        }
        guard let engine else { return nil }
        let lines = await engine.analyze(fen: fen, depth: Self.engineDepth, lines: 1, maxTimeMs: Self.engineTimeMs)
        guard !Task.isCancelled, let line = lines.first else { return nil }
        return EndgameAssessment(engine: line, offline: isOffline)
    }
}
