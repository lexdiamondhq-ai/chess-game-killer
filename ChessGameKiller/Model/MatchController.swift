import ChessKit
import Foundation
import Observation

/// Runs a match: who plays which side, the computer's replies, the coach's
/// verdict on each move and the two best-move arrows.
@MainActor
@Observable
final class MatchController {
    enum Opponent: String, CaseIterable, Identifiable {
        case computer, friend

        var id: Self { self }
        var title: String { self == .computer ? "Computer" : "Friend" }
        var symbol: String { self == .computer ? "cpu" : "person.2.fill" }
    }

    enum Level: Int, CaseIterable, Identifiable {
        case beginner, casual, club, expert, grandmaster

        var id: Self { self }

        var name: String {
            switch self {
            case .beginner: return "Beginner"
            case .casual: return "Casual"
            case .club: return "Club"
            case .expert: return "Expert"
            case .grandmaster: return "Grandmaster"
            }
        }

        var blurb: String {
            switch self {
            case .beginner: return "Learning the moves"
            case .casual: return "Plays for fun"
            case .club: return "A solid club player"
            case .expert: return "Tough and sharp"
            case .grandmaster: return "Full-strength Stockfish"
            }
        }

        /// Stockfish "Skill Level", 0 to 20.
        var skill: Int {
            switch self {
            case .beginner: return 0
            case .casual: return 4
            case .club: return 9
            case .expert: return 14
            case .grandmaster: return 20
            }
        }

        var thinkTimeMs: Int {
            switch self {
            case .beginner: return 150
            case .casual: return 250
            case .club: return 400
            case .expert: return 700
            case .grandmaster: return 1200
            }
        }
    }

    struct Setup: Equatable {
        var opponent: Opponent = .computer
        var playerColor: Piece.Color = .white
        var level: Level = .club
    }

    let game: GameModel
    private(set) var setup = Setup()
    /// The two best moves for the player to move, best first. Empty when hidden.
    private(set) var hints: [MoveHint] = []
    /// The coach's verdict on the last move a person played.
    private(set) var review: MoveReview?
    private(set) var isComputerThinking = false
    /// Set once the first game has been set up from the new-game sheet.
    private(set) var hasStarted = false
    /// Set when the engine couldn't answer, so the screen can say so.
    private(set) var engineFailed = false

    var showBestMoves = true {
        didSet { hints = showBestMoves ? cachedHints : [] }
    }

    /// Black at the bottom when the player chose black against the computer.
    var isBoardFlipped: Bool { setup.opponent == .computer && setup.playerColor == .black }

    private let engine: ChessEngine?
    private let sounds: SoundPlaying?
    private var work: Task<Void, Never>?
    /// Bumps whenever the game changes under running work, so stale results are dropped.
    private var generation = 0
    private var nextReviewID = 0
    /// Engine lines for the position the player is about to move in.
    private var analysis: (fen: String, lines: [EngineLine])?
    private var cachedHints: [MoveHint] = []

    init(game: GameModel = GameModel(), engine: ChessEngine?, sounds: SoundPlaying?) {
        self.game = game
        self.engine = engine
        self.sounds = sounds
    }

    /// The app's controller: on-device Stockfish and the bundled sounds.
    static func live() -> MatchController {
        MatchController(engine: StockfishEngine.shared, sounds: SoundPlayer.shared)
    }

    // MARK: Actions

    func start(_ setup: Setup, from position: Position = .standard, playSound: Bool = true) {
        self.setup = setup
        hasStarted = true
        resetWork()
        game.newGame(from: position)
        game.humanColors = setup.opponent == .computer ? [setup.playerColor] : [.white, .black]
        if playSound { sounds?.play(.gameStart) }
        scheduleWork(after: nil)
    }

    func tap(_ square: Square) {
        let movesBefore = game.moveCount
        let selectedBefore = game.selected
        game.tap(square)
        if game.moveCount != movesBefore {
            didPlayMove(byPerson: true)
        } else if let selected = game.selected, selected != selectedBefore {
            sounds?.play(.select)
        }
    }

    func promote(to kind: Piece.Kind) {
        let movesBefore = game.moveCount
        game.promote(to: kind)
        if game.moveCount != movesBefore {
            didPlayMove(byPerson: true)
        }
    }

    var canUndo: Bool { game.canUndo }

    /// Takes back the last move. Against the computer, its reply is taken back too,
    /// so it is the player's turn again.
    func undo() {
        guard game.canUndo else { return }
        resetWork()
        game.undo()
        if setup.opponent == .computer, !game.isHumanTurn, game.canUndo {
            game.undo()
        }
        scheduleWork(after: nil)
    }

    // MARK: Running the match

    private func resetWork() {
        work?.cancel()
        generation += 1
        isComputerThinking = false
        review = nil
        hints = []
        cachedHints = []
        analysis = nil
    }

    private func didPlayMove(byPerson: Bool) {
        guard let played = game.lastPlayed else { return }
        playSound(for: played)
        work?.cancel()
        generation += 1
        hints = []
        cachedHints = []
        scheduleWork(after: byPerson ? played : nil)
    }

    private func scheduleWork(after personMove: PlayedMove?) {
        let gen = generation
        work = Task { [weak self] in
            if let personMove { await self?.review(personMove, generation: gen) }
            await self?.computerMoveIfNeeded(generation: gen)
            await self?.prepareHints(generation: gen)
        }
    }

    private func review(_ move: PlayedMove, generation gen: Int) async {
        if game.winner == move.color {
            publishReview(.checkmate, move: move, best: nil, evaluation: nil)
            return
        }
        guard let engine else { return }

        let before: [EngineLine]
        if let analysis, analysis.fen == move.fenBefore {
            before = analysis.lines
        } else {
            before = await engine.analyze(fen: move.fenBefore, depth: 12, lines: 2)
        }
        guard gen == generation, let bestLine = before.first, let bestMove = bestLine.firstMove else { return }

        let playedBest = bestMove == move.uci
        let after: Evaluation
        if playedBest {
            after = bestLine.evaluation
        } else if before.count > 1, before[1].firstMove == move.uci {
            after = before[1].evaluation
        } else if game.isGameOver {
            after = .centipawns(0)
        } else {
            let reply = await engine.analyze(fen: game.fen, depth: 12, lines: 1)
            guard gen == generation, let line = reply.first else { return }
            after = line.evaluation.flipped
        }

        let grade = MoveReview.grade(before: bestLine.evaluation, after: after, playedBest: playedBest)
        let bestSAN = playedBest ? nil : Notation.san(of: bestMove, fen: move.fenBefore)
        publishReview(grade, move: move, best: bestSAN, evaluation: after)
    }

    private func publishReview(_ grade: MoveReview.Grade, move: PlayedMove, best: String?, evaluation: Evaluation?) {
        review = MoveReview(id: nextReviewID, grade: grade, played: move.san, best: best, evaluation: evaluation)
        nextReviewID += 1
    }

    private func computerMoveIfNeeded(generation gen: Int) async {
        guard
            let engine, setup.opponent == .computer,
            !game.isGameOver, !game.isHumanTurn, game.pendingPromotion == nil
        else { return }

        isComputerThinking = true
        let clock = ContinuousClock()
        let started = clock.now
        let move = await engine.chooseMove(fen: game.fen, skill: setup.level.skill, thinkTimeMs: setup.level.thinkTimeMs)

        // A short pause so the reply never feels instant.
        let minimum = Duration.milliseconds(450)
        let elapsed = clock.now - started
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
        }
        guard gen == generation else { return }
        isComputerThinking = false

        guard let move, game.playEngineMove(move), let played = game.lastPlayed else {
            engineFailed = true
            return
        }
        engineFailed = false
        playSound(for: played)
    }

    private func prepareHints(generation gen: Int) async {
        guard let engine, !game.isGameOver, game.isHumanTurn, game.pendingPromotion == nil else { return }
        let fen = game.fen
        let lines = await engine.analyze(fen: fen, depth: 14, lines: 2)
        guard gen == generation, game.fen == fen else { return }
        engineFailed = lines.isEmpty

        analysis = (fen, lines)
        cachedHints = lines.prefix(2).enumerated().compactMap { index, line in
            guard
                let uci = line.firstMove,
                let squares = Notation.squares(of: uci),
                let san = Notation.san(of: uci, fen: fen)
            else { return nil }
            return MoveHint(rank: index, from: squares.from, to: squares.to, san: san)
        }
        if showBestMoves { hints = cachedHints }
    }

    private func playSound(for move: PlayedMove) {
        guard let sounds else { return }
        if game.isGameOver {
            if let winner = game.winner, setup.opponent == .friend || game.humanColors.contains(winner) {
                sounds.play(.win)
            } else {
                sounds.play(.gameOver)
            }
        } else if move.isCapture {
            sounds.play(.capture)
        } else if move.givesCheck {
            sounds.play(.check)
        } else if move.isCastle {
            sounds.play(.castle)
        } else {
            sounds.play(.move)
        }
    }
}
