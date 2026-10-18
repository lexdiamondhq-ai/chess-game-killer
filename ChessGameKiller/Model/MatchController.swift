import ChessKit
import Foundation
import Observation

/// Runs a match: who plays which side, the computer's replies, the coach's
/// verdict on each move, the two best-move arrows and the clock.
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
        var timeControl: TimeControl = .unlimited
    }

    /// How the game ended when the board itself doesn't say (the clock did).
    enum Outcome: Equatable {
        case timeout(loser: Piece.Color)

        var winner: Piece.Color {
            switch self {
            case .timeout(let loser): return loser.opposite
            }
        }
    }

    let game: GameModel
    private(set) var setup = Setup()
    /// The two best moves for the player to move, best first. Empty when hidden.
    private(set) var hints: [MoveHint] = []
    /// The coach's verdict on the last move a person played.
    private(set) var review: MoveReview?
    /// How the position stands, from Gold's (White's) point of view. Drives the eval ring.
    private(set) var evaluation: Evaluation?
    private(set) var isComputerThinking = false
    /// Set once the first game has been set up from the new-game sheet.
    private(set) var hasStarted = false
    /// Set when the engine couldn't answer, so the screen can say so.
    private(set) var engineFailed = false
    /// The clock, when the game is timed.
    private(set) var clock: ChessClock?
    /// Set when the game ended on the clock rather than on the board.
    private(set) var outcome: Outcome?
    /// How many of the person's moves got each grade this game, for the summary at the end.
    private(set) var gradeCounts: [MoveReview.Grade: Int] = [:]
    /// Flipped by the Flip button, on top of the usual "your side at the bottom".
    private(set) var isFlippedByHand = false

    var showBestMoves = true {
        didSet { refreshHints() }
    }

    /// Whether the runner-up arrow is drawn too.
    var showSecondBest = true {
        didSet { refreshHints() }
    }

    /// Whether moves are graded. Checkmate is always announced.
    var showVerdicts = true {
        didSet { if !showVerdicts, review?.grade != .checkmate { review = nil } }
    }

    /// Black at the bottom when the player chose black against the computer.
    var isBoardFlipped: Bool {
        (setup.opponent == .computer && setup.playerColor == .black) != isFlippedByHand
    }

    /// Over on the board (mate, draw) or on the clock.
    var isOver: Bool { game.isGameOver || outcome != nil }

    /// Who won, on the board or on the clock. Nil for a draw or a game still going.
    var winner: Piece.Color? { outcome?.winner ?? game.winner }

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
        outcome = nil
        gradeCounts = [:]
        isFlippedByHand = false
        evaluation = nil
        startClock()
        if playSound { sounds?.play(.gameStart) }
        scheduleWork(after: nil)
    }

    /// The same game again: same rival, same side, same clock.
    func rematch() {
        start(setup)
    }

    func tap(_ square: Square) {
        guard outcome == nil else { return }
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
        guard outcome == nil else { return }
        let movesBefore = game.moveCount
        game.promote(to: kind)
        if game.moveCount != movesBefore {
            didPlayMove(byPerson: true)
        }
    }

    /// Plays one of the suggested moves for the person, as if they had tapped it out.
    func play(_ hint: MoveHint) {
        guard outcome == nil, game.isHumanTurn, game.pendingPromotion == nil else { return }
        let movesBefore = game.moveCount
        game.playEngineMove(hint.uci)
        if game.moveCount != movesBefore {
            didPlayMove(byPerson: true)
        }
    }

    var canUndo: Bool { game.canUndo && outcome == nil }

    /// Takes back the last move. Against the computer, its reply is taken back too,
    /// so it is the player's turn again.
    func undo() {
        guard canUndo else { return }
        resetWork()
        game.undo()
        if setup.opponent == .computer, !game.isHumanTurn, game.canUndo {
            game.undo()
        }
        clock?.start(game.sideToMove)
        scheduleWork(after: nil)
    }

    /// Turns the board around.
    func flipBoard() {
        isFlippedByHand.toggle()
    }

    /// A rough quality score for the person's moves this game, 0 to 100.
    var accuracy: Int? {
        let weights: [MoveReview.Grade: Int] = [
            .checkmate: 100, .best: 100, .excellent: 95, .good: 85, .inaccuracy: 60, .mistake: 35, .blunder: 10,
        ]
        let graded = gradeCounts.reduce(into: (sum: 0, count: 0)) { acc, entry in
            acc.sum += (weights[entry.key] ?? 0) * entry.value
            acc.count += entry.value
        }
        guard graded.count > 0 else { return nil }
        return graded.sum / graded.count
    }

    // MARK: The clock

    private func startClock() {
        clock?.pause()
        guard setup.timeControl.isTimed else {
            clock = nil
            return
        }
        let clock = ChessClock(control: setup.timeControl)
        clock.onFlag = { [weak self] loser in self?.flagFell(loser) }
        self.clock = clock
        clock.start(game.sideToMove)
    }

    private func flagFell(_ loser: Piece.Color) {
        guard outcome == nil, !game.isGameOver else { return }
        resetWork()
        outcome = .timeout(loser: loser)
        if setup.opponent == .friend || game.humanColors.contains(loser.opposite) {
            sounds?.play(.win)
        } else {
            sounds?.play(.gameOver)
        }
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
        if game.isGameOver {
            clock?.pause()
        } else {
            clock?.moved(by: played.color)
        }
        work?.cancel()
        generation += 1
        hints = []
        cachedHints = []
        scheduleWork(after: byPerson ? played : nil)
    }

    private func refreshHints() {
        hints = showBestMoves ? Array(cachedHints.prefix(showSecondBest ? 2 : 1)) : []
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
        evaluation = move.color == .white ? after : after.flipped
    }

    private func publishReview(_ grade: MoveReview.Grade, move: PlayedMove, best: String?, evaluation: Evaluation?) {
        gradeCounts[grade, default: 0] += 1
        guard showVerdicts || grade == .checkmate else { return }
        review = MoveReview(id: nextReviewID, grade: grade, played: move.san, best: best, evaluation: evaluation)
        nextReviewID += 1
    }

    private func computerMoveIfNeeded(generation gen: Int) async {
        guard
            let engine, setup.opponent == .computer,
            !isOver, !game.isHumanTurn, game.pendingPromotion == nil
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
        if game.isGameOver {
            self.clock?.pause()
        } else {
            self.clock?.moved(by: played.color)
        }
    }

    private func prepareHints(generation gen: Int) async {
        guard let engine, !isOver, game.isHumanTurn, game.pendingPromotion == nil else { return }
        let fen = game.fen
        let lines = await engine.analyze(fen: fen, depth: 14, lines: 2)
        guard gen == generation, game.fen == fen else { return }
        engineFailed = lines.isEmpty

        analysis = (fen, lines)
        if let best = lines.first {
            evaluation = game.sideToMove == .white ? best.evaluation : best.evaluation.flipped
        }
        cachedHints = lines.prefix(2).enumerated().compactMap { index, line in
            guard
                let uci = line.firstMove,
                let squares = Notation.squares(of: uci),
                let san = Notation.san(of: uci, fen: fen)
            else { return nil }
            return MoveHint(rank: index, from: squares.from, to: squares.to, san: san, uci: uci, evaluation: line.evaluation)
        }
        refreshHints()
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
