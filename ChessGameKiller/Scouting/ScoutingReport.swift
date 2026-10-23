import ChessKit
import Foundation

/// What the rivals have learned about the player from the games saved on this phone: the
/// positions where the player went wrong before (traps a rival can steer back into), the
/// moves the player usually plays, and up to three habits worth a line on the New Game card.
///
/// Built only from finished games against the computer, and only from the player's own
/// moves. A habit is named only when at least `minimumExamples` games or moves show it, so a
/// report never invents a habit from one game. A trap is a single fact and needs one.
struct ScoutingReport: Equatable {
    /// A position the player has stood in before and answered with a mistake.
    struct Trap: Equatable {
        /// `TrainingChess.key` of the position before the player's move.
        let key: String
        let fen: String
        let gameID: UUID
        let date: Date
        let ply: Int
        /// The move number as written on a scoresheet.
        let moveNumber: Int
        /// The move the player chose, in both notations.
        let played: String
        let playedUCI: String
        /// The better move, when the engine named one.
        let best: String?
        /// "mistake" or "blunder".
        let grade: String
        /// How much the move gave away, in winning chances (0 to 2).
        let loss: Double
    }

    /// One line of the report, as the rival says it, with the game it comes from.
    struct Finding: Equatable, Identifiable {
        enum Kind: String, Equatable {
            case trap, opening, phase, piece, castling
        }

        let kind: Kind
        /// The rival's line, in the first person.
        let line: String
        /// How many games or moves back it up.
        let examples: Int
        /// A game and position that shows it, for the small diagram and a tap into Rewind.
        let gameID: UUID?
        let fen: String?
        let ply: Int?

        var id: String { kind.rawValue }
    }

    /// Finished games against the computer it was read from.
    let gamesStudied: Int
    /// Up to three findings, the most telling first.
    let findings: [Finding]
    /// Every trap, by position key. The most recent mistake wins when a position repeats.
    let traps: [String: Trap]
    /// The player's usual move in each position they have been in, by position key.
    let repertoire: [String: String]

    static let minimumExamples = 5
    /// Games the report reads, newest first.
    static let gamesRead = 60
    /// Below this, the card says the rival is still watching.
    static let gamesForAReport = 3

    static let empty = ScoutingReport(gamesStudied: 0, findings: [], traps: [:], repertoire: [:])

    var isReady: Bool { gamesStudied >= Self.gamesForAReport && !findings.isEmpty }

    /// The trap waiting in `fen`, if the player has gone wrong here before.
    func trap(at fen: String) -> Trap? {
        traps[TrainingChess.key(fen)]
    }
}

// MARK: Reading the games

extension ScoutingReport {
    static func make(from games: [SavedGame], now: Date = .now) -> ScoutingReport {
        let studied = games
            .filter { $0.level != nil && $0.result != .unfinished && !$0.moves.isEmpty }
            .sorted { $0.date > $1.date }
            .prefix(gamesRead)
        let list = Array(studied)
        guard !list.isEmpty else { return .empty }

        var traps: [String: Trap] = [:]
        var tally: [String: [String: Int]] = [:]
        for game in list.reversed() {   // oldest first, so a newer mistake replaces an older one
            for moment in game.playerMoments {
                let key = TrainingChess.key(moment.fenBefore)
                tally[key, default: [:]][moment.uci, default: 0] += 1
                guard ["mistake", "blunder"].contains(moment.grade), moment.loss >= 0.1 else { continue }
                traps[key] = Trap(
                    key: key, fen: moment.fenBefore, gameID: game.id, date: game.date, ply: moment.ply,
                    moveNumber: TrainingChess.moveNumber(moment.fenBefore), played: moment.san,
                    playedUCI: moment.uci, best: moment.best, grade: moment.grade, loss: moment.loss
                )
            }
        }
        let repertoire = tally.compactMapValues { counts in
            counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        }

        var findings: [Finding] = []
        if let trap = Self.trapFinding(traps, now: now) { findings.append(trap) }
        if let opening = Self.openingFinding(list) { findings.append(opening) }
        let habits = [Self.phaseFinding(list), Self.pieceFinding(list), Self.castlingFinding(list)]
            .compactMap { $0 }
            .sorted { $0.examples > $1.examples }
        findings.append(contentsOf: habits)

        return ScoutingReport(
            gamesStudied: list.count, findings: Array(findings.prefix(3)), traps: traps, repertoire: repertoire
        )
    }

    /// The trap the rival is most likely to reach: early in the game, costly and recent.
    static func trapFinding(_ traps: [String: Trap], now: Date) -> Finding? {
        let early = traps.values.filter { $0.ply <= 30 }
        guard let pick = early.max(by: { score($0) < score($1) }) else { return nil }
        let line = "Move \(pick.moveNumber), \(when(pick.date, now: now)): you played \(pick.played). I remember."
        return Finding(kind: .trap, line: line, examples: 1, gameID: pick.gameID, fen: pick.fen, ply: pick.ply)
    }

    private static func score(_ trap: Trap) -> Double {
        trap.loss + (trap.ply <= 16 ? 0.5 : 0) + trap.date.timeIntervalSinceReferenceDate / 1e10
    }

    /// The player's usual first answer, when it is a strong habit.
    static func openingFinding(_ games: [SavedGame]) -> Finding? {
        var best: Finding?
        for (asWhite, after) in [(true, ""), (false, "e2e4"), (false, "d2d4")] {
            let relevant = games.filter { game in
                guard game.playerIsWhite == asWhite, game.moves.count >= (asWhite ? 1 : 2) else { return false }
                return asWhite || uciOfFirstMove(game) == after
            }
            guard relevant.count >= minimumExamples else { continue }
            var counts: [String: Int] = [:]
            for game in relevant { counts[game.moves[asWhite ? 0 : 1], default: 0] += 1 }
            guard let top = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) else { continue }
            let move = top.key, count = top.value
            let share = Double(count) / Double(relevant.count)
            guard share >= 0.6 else { continue }
            let tenths = max(6, min(10, Int((share * 10).rounded())))
            let line: String
            if asWhite {
                line = "You open with 1. \(move) \(tenths) times in 10. I've prepared for it."
            } else {
                let first = after == "e2e4" ? "1. e4" : "1. d4"
                line = "You answer \(first) with \(move) \(tenths) times in 10."
            }
            let ply = asWhite ? 1 : 2
            let sample = relevant.first { $0.moves[ply - 1] == move }
            let positions = sample?.positions ?? []
            let fen: String? = positions.count > ply ? positions[ply] : nil
            let finding = Finding(kind: .opening, line: line, examples: relevant.count,
                                  gameID: sample?.id, fen: fen, ply: ply)
            if best == nil || finding.examples > best!.examples { best = finding }
        }
        return best
    }

    /// The first move of a game in engine notation, read from its first two positions.
    private static func uciOfFirstMove(_ game: SavedGame) -> String? {
        guard game.positions.count >= 2 else { return nil }
        if let moment = game.moments.first(where: { $0.ply == 1 }) { return moment.uci }
        // The rival's first move isn't graded: work it out from the board.
        guard let board = TrainingChess.board(after: [], from: game.positions[0]) else { return nil }
        let target = TrainingChess.key(game.positions[1])
        return TrainingChess.legalMoves(in: board).first { uci in
            TrainingChess.fen(after: [uci], from: game.positions[0]).map(TrainingChess.key) == target
        }
    }

    enum Phase: String {
        case opening, middlegame, endgame

        /// Opening for the first 12 moves; endgame once each side has at most 13 points of pieces.
        static func of(_ fen: String) -> Phase {
            if TrainingChess.moveNumber(fen) <= 12 { return .opening }
            let placement = fen.split(separator: " ").first ?? ""
            let value: [Character: Int] = ["q": 9, "r": 5, "b": 3, "n": 3]
            var white = 0, black = 0
            for character in placement {
                guard let points = value[Character(character.lowercased())] else { continue }
                if character.isUppercase { white += points } else { black += points }
            }
            return white <= 13 && black <= 13 ? .endgame : .middlegame
        }

        var phrase: String {
            switch self {
            case .opening: return "in the opening"
            case .middlegame: return "in the middlegame"
            case .endgame: return "once the queens come off"
            }
        }
    }

    /// The phase where the player errs most often, when it clearly stands out.
    static func phaseFinding(_ games: [SavedGame]) -> Finding? {
        var moves: [Phase: Int] = [:], errors: [Phase: [(SavedGame, SavedMoment)]] = [:]
        for game in games {
            for moment in game.playerMoments {
                let phase = Phase.of(moment.fenBefore)
                moves[phase, default: 0] += 1
                if ["mistake", "blunder"].contains(moment.grade) { errors[phase, default: []].append((game, moment)) }
            }
        }
        let total = moves.values.reduce(0, +), totalErrors = errors.values.reduce(0) { $0 + $1.count }
        guard total > 0, totalErrors >= minimumExamples else { return nil }
        let average = Double(totalErrors) / Double(total)
        let rated = errors.compactMap { phase, list -> (Phase, Double, [(SavedGame, SavedMoment)])? in
            guard let count = moves[phase], count >= 20, list.count >= minimumExamples else { return nil }
            return (phase, Double(list.count) / Double(count), list)
        }
        guard let worst = rated.max(by: { $0.1 < $1.1 }), worst.1 >= average * 1.3 else { return nil }
        let oneIn = max(2, Int((1 / worst.1).rounded()))
        let example = worst.2.max { $0.1.loss < $1.1.loss }
        return Finding(kind: .phase, line: "You slip most \(worst.0.phrase): 1 move in \(oneIn).",
                       examples: worst.2.count, gameID: example?.0.id, fen: example?.1.fenBefore, ply: example?.1.ply)
    }

    /// The piece whose moves cost the player most often.
    static func pieceFinding(_ games: [SavedGame]) -> Finding? {
        var errors: [Piece.Kind: [(SavedGame, SavedMoment)]] = [:]
        for game in games {
            for moment in game.playerMoments where ["mistake", "blunder"].contains(moment.grade) {
                errors[kind(of: moment.san), default: []].append((game, moment))
            }
        }
        let total = errors.values.reduce(0) { $0 + $1.count }
        guard total >= minimumExamples * 2,
              let top = errors.max(by: { $0.value.count < $1.value.count }),
              top.value.count >= minimumExamples, Double(top.value.count) / Double(total) >= 0.35
        else { return nil }
        let kind = top.key, list = top.value
        let example = list.max { $0.1.loss < $1.1.loss }
        let line: String
        switch kind {
        case .pawn: line = "Your pawn moves cost you most. I'll wait for the next one."
        case .king: line = "Your king walks into trouble. I'll be there."
        default: line = "Your \(kind.word) moves cost you most: \(list.count) mistakes so far."
        }
        return Finding(kind: .piece, line: line, examples: list.count,
                       gameID: example?.0.id, fen: example?.1.fenBefore, ply: example?.1.ply)
    }

    static func kind(of san: String) -> Piece.Kind {
        if san.hasPrefix("O-O") { return .king }
        switch san.first {
        case "K": return .king
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return .pawn
        }
    }

    /// Late castling, or none, when it is the player's habit.
    static func castlingFinding(_ games: [SavedGame]) -> Finding? {
        let long = games.filter { $0.moves.count >= 30 }
        guard long.count >= minimumExamples else { return nil }
        var castledAt: [Int] = [], never = 0
        for game in long {
            let mine = game.moves.enumerated().filter { ($0.offset % 2 == 0) == game.playerIsWhite }
            if let castle = mine.first(where: { $0.element.hasPrefix("O-O") }) {
                castledAt.append(castle.offset / 2 + 1)
            } else {
                never += 1
            }
        }
        let sample = long.first
        if Double(never) / Double(long.count) >= 0.5 {
            return Finding(kind: .castling, line: "Half your games, your king never castles. I notice.",
                           examples: never, gameID: sample?.id, fen: nil, ply: nil)
        }
        let sorted = castledAt.sorted()
        guard sorted.count >= minimumExamples else { return nil }
        let median = sorted[sorted.count / 2]
        guard median >= 12 else { return nil }
        return Finding(kind: .castling, line: "You castle late, around move \(median). I'll come early.",
                       examples: sorted.count, gameID: sample?.id, fen: nil, ply: nil)
    }

    /// "today", "yesterday", "on Tuesday", "on 12 Oct".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2...6:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE"
            return "on " + formatter.string(from: date)
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = "d MMM"
            return "on " + formatter.string(from: date)
        }
    }
}

// MARK: Steering

extension ScoutingReport {
    /// A move for the rival that heads for one of the player's traps, when it costs the rival
    /// no more than `tolerance` centipawns against the move it was going to play. Looks one
    /// move ahead (the rival's move lands the player in a trap) and three (the rival's move,
    /// the player's usual answer, then a rival move that lands the trap).
    ///
    /// `lines` are the engine's best lines from `fen`, best first, with scores for the rival.
    /// The rival's level stays the same: it only chooses among moves the engine rates within
    /// the tolerance of its own choice.
    func steer(fen: String, lines: [EngineLine], chosen: String, tolerance: Int) -> (uci: String, trap: Trap)? {
        guard !traps.isEmpty, !lines.isEmpty else { return nil }
        let floor = Self.centipawns(lines.first { $0.firstMove == chosen }?.evaluation ?? lines.last!.evaluation) - tolerance
        var choice: (uci: String, trap: Trap, depth: Int, value: Int)?
        for line in lines {
            guard let uci = line.firstMove else { continue }
            let value = Self.centipawns(line.evaluation)
            guard value >= floor, let next = TrainingChess.fen(after: [uci], from: fen) else { continue }
            if let trap = self.trap(at: next) {
                if choice == nil || choice!.depth > 1 || value > choice!.value { choice = (uci, trap, 1, value) }
                continue
            }
            guard choice == nil || choice!.depth > 3,
                  let usual = repertoire[TrainingChess.key(next)],
                  let afterReply = TrainingChess.fen(after: [usual], from: next),
                  let board = TrainingChess.board(after: [], from: afterReply)
            else { continue }
            for follow in TrainingChess.legalMoves(in: board) {
                guard let landed = TrainingChess.fen(after: [follow], from: afterReply), let trap = self.trap(at: landed) else { continue }
                if choice == nil || value > choice!.value { choice = (uci, trap, 3, value) }
                break
            }
        }
        guard let choice, choice.uci != chosen else { return nil }
        return (choice.uci, choice.trap)
    }

    /// Mates count as far beyond any material score.
    static func centipawns(_ evaluation: Evaluation) -> Int {
        switch evaluation {
        case .centipawns(let cp): return cp
        case .mate(let n): return n > 0 ? 100_000 - n : -100_000 - n
        }
    }
}

extension MatchController.Level {
    /// How far below its own choice (in centipawns) a rival will go to steer toward a trap.
    /// The strongest rival never gives anything away; the beginners care less.
    var steeringTolerance: Int {
        switch self {
        case .beginner: return 60
        case .casual: return 45
        case .club: return 30
        case .expert: return 15
        case .grandmaster: return 0
        }
    }
}
