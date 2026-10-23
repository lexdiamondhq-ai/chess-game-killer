import ChessKit
import Foundation
import Observation

/// One position of the candidates drill, after Kotov: before calculating, list
/// the serious moves. The player names up to three by moving pieces; each
/// becomes a numbered arrow and the piece stays where it is, so the position
/// never changes. Then Leo checks the list against the puzzle's answer and the
/// engine's best moves.
@MainActor
@Observable
final class CandidateRunner {
    enum Phase: Equatable {
        /// The opponent's move that sets the position up is playing.
        case intro
        /// The player is listing candidates.
        case listing
        /// Leo is checking the list.
        case checking
        /// The verdict is up.
        case judged
        /// The winning line is playing on the board.
        case playingLine
        /// The winning line has played.
        case lineShown
    }

    /// A move on the player's list.
    struct Candidate: Equatable, Identifiable {
        /// Engine notation, like "e3f4".
        let uci: String
        /// Standard notation, like "Bf4".
        let san: String

        var id: String { uci }
    }

    static let maxCandidates = 3

    let puzzle: LichessPuzzle
    /// The player's side, at the bottom of the board.
    let learner: Piece.Color
    /// The position the candidates are played from, after the opponent's move.
    let fen: String
    private(set) var game: GameModel
    private(set) var phase: Phase = .intro
    private(set) var candidates: [Candidate] = []
    private(set) var report: CandidateReport?
    private(set) var message: String
    private(set) var tone: DrillRunner.Tone = .coach
    /// The arrow for the move about to play in the winning line.
    private(set) var lineArrow: BoardArrow?
    /// Called once, when the verdict is in.
    @ObservationIgnored var onJudged: ((CandidateReport) -> Void)?

    private let engine: ChessEngine?
    private let sounds: SoundPlaying?
    @ObservationIgnored private var pending: Task<Void, Never>?

    init?(puzzle: LichessPuzzle, engine: ChessEngine?, sounds: SoundPlaying?) {
        guard puzzle.moves.count >= 2, let start = Position(fen: puzzle.fen),
              let after = TrainingChess.fen(after: [puzzle.moves[0]], from: puzzle.fen) else { return nil }
        self.puzzle = puzzle
        self.engine = engine
        self.sounds = sounds
        fen = after
        learner = start.sideToMove.opposite
        let model = GameModel(position: start)
        model.humanColors = []
        game = model
        message = "Here's their move."
    }

    /// The puzzle's answer: the move that wins.
    var winner: String { puzzle.moves[1] }

    /// The winning line in standard notation, numbered, like "1. Bf4 Qf6 2. Bxd6".
    var lineText: String {
        let line = Array(puzzle.moves.dropFirst())
        return Notation.numbered(Notation.sanLine(of: line, fen: fen, limit: line.count), blackFirst: learner == .black)
    }

    // MARK: Starting

    /// Plays the opponent's move, then hands the board to the player.
    func begin() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.play(self.puzzle.moves[0])
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.phase = .listing
            self.game.humanColors = [self.learner]
            self.message = Self.prompt(listed: 0)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    // MARK: Listing

    /// A tap on the board: pick up a piece, or name the move it would make.
    func tap(_ square: Square) {
        guard phase == .listing else { return }
        if let from = game.selected, game.targets.contains(square) {
            let uci = move(from: from, to: square)
            // Tapping the picked-up piece again puts it down, so the board never changes.
            game.tap(from)
            add(uci)
            return
        }
        let before = game.selected
        game.tap(square)
        if let selected = game.selected, selected != before {
            sounds?.play(.select)
        }
    }

    /// Takes a move off the list.
    func remove(_ candidate: Candidate) {
        guard phase == .listing, let index = candidates.firstIndex(of: candidate) else { return }
        candidates.remove(at: index)
        tone = .coach
        message = Self.prompt(listed: candidates.count)
    }

    /// What Leo says while the list grows.
    static func prompt(listed: Int) -> String {
        switch listed {
        case 0: return "Which moves deserve a closer look? Move a piece to add one, up to three."
        case 1: return "Good. What else? Look at checks, captures and threats."
        case 2: return "One more, or check your list with me."
        default: return "That's your list. Tap a move below to drop it, or check it with me."
        }
    }

    private func add(_ uci: String) {
        if candidates.contains(where: { CandidateJudge.same($0.uci, uci) }) {
            tone = .hint
            message = "That one's already on your list."
            return
        }
        guard candidates.count < Self.maxCandidates else {
            tone = .hint
            message = "Three is plenty. Tap a move below to drop it first."
            return
        }
        candidates.append(Candidate(uci: uci, san: Notation.san(of: uci, fen: fen) ?? uci))
        tone = .coach
        message = Self.prompt(listed: candidates.count)
        sounds?.play(.select)
    }

    /// The move in engine notation. A pawn reaching the last rank makes a queen,
    /// or the piece the answer makes when it promotes on the same square.
    private func move(from: Square, to: Square) -> String {
        let uci = from.notation + to.notation
        guard game.piece(at: from)?.kind == .pawn, to.rankIndex == 0 || to.rankIndex == 7 else { return uci }
        if winner.count == 5, winner.hasPrefix(uci) { return winner }
        return uci + "q"
    }

    // MARK: Checking

    /// Hands the list to Leo.
    func check() {
        guard phase == .listing, !candidates.isEmpty else { return }
        if let selected = game.selected { game.tap(selected) }
        game.humanColors = []
        phase = .checking
        tone = .coach
        message = "Let me look at your list…"
        let fen = fen
        let moves = candidates.map(\.uci)
        pending = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let started = clock.now
            let (lines, extra) = await self.analysis(of: moves, from: fen)
            // A calm beat, so the answer never flashes past.
            let elapsed = clock.now - started
            if elapsed < .milliseconds(700) {
                try? await Task.sleep(for: .milliseconds(700) - elapsed)
            }
            guard !Task.isCancelled else { return }
            self.judge(lines: lines, extra: extra)
        }
    }

    /// The engine's best lines from the position, and its view of each listed move
    /// that isn't among them. Searches run one after another, a second or so each.
    private func analysis(of moves: [String], from fen: String) async -> ([EngineLine], [String: Evaluation]) {
        guard let engine else { return ([], [:]) }
        let lines = await engine.analyze(fen: fen, depth: 18, lines: 4, maxTimeMs: 1200)
        guard !lines.isEmpty else { return ([], [:]) }
        var extra: [String: Evaluation] = [:]
        for move in moves where !lines.contains(where: { $0.firstMove.map { CandidateJudge.same($0, move) } ?? false }) {
            guard !Task.isCancelled else { break }
            if let final = CandidateJudge.finalEvaluation(of: move, in: fen) {
                extra[move] = final
                continue
            }
            guard let after = TrainingChess.fen(after: [move], from: fen) else { continue }
            if let reply = await engine.analyze(fen: after, depth: 14, lines: 1, maxTimeMs: 500).first {
                extra[move] = reply.evaluation.flipped
            }
        }
        return (lines, extra)
    }

    private func judge(lines: [EngineLine], extra: [String: Evaluation]) {
        let made = CandidateJudge.report(fen: fen, winner: winner, candidates: candidates.map(\.uci),
                                         lines: lines, extra: extra, mate: puzzle.mateIn != nil)
        report = made
        phase = .judged
        tone = made.foundAt == nil ? .hint : .success
        message = made.takeaway
        if made.foundAt != nil { sounds?.play(.win) }
        onJudged?(made)
    }

    // MARK: The winning line

    /// Plays the puzzle's answer on the board, an arrow before each of the player's moves.
    func showLine() {
        guard phase == .judged else { return }
        phase = .playingLine
        tone = .coach
        message = "Here's how it goes."
        let line = Array(puzzle.moves.dropFirst())
        pending = Task { [weak self] in
            guard let self else { return }
            for (offset, uci) in line.enumerated() {
                if offset.isMultiple(of: 2), let squares = Notation.squares(of: uci) {
                    self.lineArrow = BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: nil)
                }
                try? await Task.sleep(for: .milliseconds(offset == 0 ? 600 : 850))
                guard !Task.isCancelled else { return }
                self.lineArrow = nil
                self.play(uci)
            }
            self.phase = .lineShown
            self.tone = .success
            self.message = "The winning line: \(self.lineText)"
        }
    }

    // MARK: Drawing

    /// The arrows on the board: the list while it's made, then the list judged,
    /// with the winner in green and (when the engine judged them) moves that didn't count dashed.
    var arrows: [BoardArrow] {
        switch phase {
        case .intro, .lineShown:
            return []
        case .playingLine:
            return lineArrow.map { [$0] } ?? []
        case .listing, .checking:
            return candidates.compactMap { arrow($0.uci, color: .blue, dashed: false) }
        case .judged:
            let rows = report?.rows ?? []
            let usedEngine = report?.usedEngine ?? false
            var arrows = candidates.compactMap { candidate -> BoardArrow? in
                let row = rows.first { CandidateJudge.same($0.uci, candidate.uci) }
                let isWinner = row?.isWinner ?? false
                return arrow(candidate.uci, color: isWinner ? .green : .blue,
                             dashed: usedEngine && !(isWinner || row?.leoRank != nil))
            }
            if report?.foundAt == nil, let missed = arrow(winner, color: .green, dashed: false) {
                arrows.append(missed)
            }
            return arrows
        }
    }

    /// The list's numbers on the squares the moves go to.
    var labels: [SquareLabel] {
        guard phase == .listing || phase == .checking || phase == .judged else { return [] }
        var labels: [SquareLabel] = []
        for (index, candidate) in candidates.enumerated() {
            guard let to = Notation.squares(of: candidate.uci)?.to.notation else { continue }
            let color: TrainingColor = phase == .judged && CandidateJudge.same(candidate.uci, winner) ? .green : .blue
            if let shared = labels.firstIndex(where: { $0.square == to }) {
                // Two moves to one square share a label: "1·2".
                let label = labels[shared]
                labels[shared] = SquareLabel(square: to, text: label.text + "·\(index + 1)", color: label.color)
            } else {
                labels.append(SquareLabel(square: to, text: "\(index + 1)", color: color))
            }
        }
        return labels
    }

    private func arrow(_ uci: String, color: TrainingColor, dashed: Bool) -> BoardArrow? {
        guard let squares = Notation.squares(of: uci) else { return nil }
        return BoardArrow(from: squares.from.notation, to: squares.to.notation, color: color, dashed: dashed ? true : nil)
    }

    private func play(_ uci: String) {
        guard game.playEngineMove(uci), let played = game.lastPlayed else { return }
        if played.isCapture {
            sounds?.play(.capture)
        } else if played.givesCheck {
            sounds?.play(.check)
        } else if played.isCastle {
            sounds?.play(.castle)
        } else {
            sounds?.play(.move)
        }
    }
}

/// A round of the candidates drill: five positions near the player's puzzle
/// rating, the running score, and what gets saved.
@MainActor
@Observable
final class CandidateSession {
    enum Stage: Equatable {
        case playing
        /// The round is over and its score is up.
        case summary
    }

    private(set) var round = CandidateRound()
    private(set) var runner: CandidateRunner?
    private(set) var stage: Stage = .playing
    /// Whether the round just finished is the best yet.
    private(set) var newBest = false

    /// The puzzle rating positions are picked near.
    let rating: Int
    private let puzzles: [LichessPuzzle]
    private let engine: ChessEngine?
    private let store: ThinkStore?
    private let sounds: SoundPlaying?
    @ObservationIgnored private var played: Set<String> = []
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()

    /// A round over `puzzles`. A round already under way can be passed in, as tests and previews do.
    init(puzzles: [LichessPuzzle], rating: Int, engine: ChessEngine?, store: ThinkStore?, sounds: SoundPlaying?,
         round: CandidateRound = CandidateRound()) {
        self.puzzles = puzzles
        self.rating = rating
        self.engine = engine
        self.store = store
        self.sounds = sounds
        self.round = round
    }

    /// The position on the board, from 1.
    var position: Int {
        min(CandidateRound.length, round.reports.count + (runner?.report == nil ? 1 : 0))
    }

    /// The best round so far, when results are being saved.
    var bestRound: Int? { store?.progress.bestRound }

    /// The next position, or the round's score once all five are done.
    func next() {
        guard stage == .playing, runner == nil || runner?.report != nil else { return }
        if round.isFinished {
            finishRound()
            return
        }
        runner?.cancel()
        let avoid = played.union(store?.progress.recent ?? [])
        guard let puzzle = ThinkPicker.candidatePosition(in: puzzles, near: rating, avoid: avoid, using: &generator),
              let made = CandidateRunner(puzzle: puzzle, engine: engine, sounds: sounds) else {
            runner = nil
            return
        }
        played.insert(puzzle.id)
        made.onJudged = { [weak self] report in
            self?.judged(report, puzzleID: puzzle.id)
        }
        runner = made
        made.begin()
    }

    /// A fresh round of five.
    func newRound() {
        runner?.cancel()
        runner = nil
        round = CandidateRound()
        newBest = false
        stage = .playing
        next()
    }

    func cancel() {
        runner?.cancel()
    }

    private func judged(_ report: CandidateReport, puzzleID: String) {
        round.add(report)
        store?.record(report, puzzleID: puzzleID)
    }

    private func finishRound() {
        runner?.cancel()
        newBest = store?.finishRound(points: round.points) ?? false
        stage = .summary
    }
}
