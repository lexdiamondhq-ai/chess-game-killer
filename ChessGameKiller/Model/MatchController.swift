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

        /// How often the rival plays any legal move instead of the engine's.
        /// Stockfish's lowest skill level is still about 1300 Elo, so the weakest
        /// rivals have to miss things on purpose to be the beginners they say they are.
        var slipRate: Double {
            switch self {
            case .beginner: return 0.3
            case .casual: return 0.1
            default: return 0
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
        /// The flag fell, but the other side has nothing that could ever give mate.
        case timeoutDraw(flagged: Piece.Color)

        /// Nil for a draw.
        var winner: Piece.Color? {
            switch self {
            case .timeout(let loser): return loser.opposite
            case .timeoutDraw: return nil
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
    /// Counts up with every game started, so the screen can tell one game from the next.
    private(set) var gameNumber = 0
    /// Set when the engine couldn't answer, so the screen can say so.
    private(set) var engineFailed = false
    /// The clock, when the game is timed.
    private(set) var clock: ChessClock?
    /// Set when the game ended on the clock rather than on the board.
    private(set) var outcome: Outcome?
    /// The grade of each of the person's moves this game, by the ply count once the
    /// move was on the board, so a move that is taken back leaves the summary too.
    private var gradeLog: [Int: MoveReview.Grade] = [:]
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
    var winner: Piece.Color? {
        if let outcome { return outcome.winner }
        return game.winner
    }

    /// How many of the person's moves got each grade this game, for the summary at the end.
    var gradeCounts: [MoveReview.Grade: Int] {
        gradeLog.values.reduce(into: [MoveReview.Grade: Int]()) { $0[$1, default: 0] += 1 }
    }

    /// A number in 0..<1 drawn for each of the rival's slips: whether it slips, and
    /// which move it plays instead. Tests swap in a fixed value.
    @ObservationIgnored var chance: () -> Double = { Double.random(in: 0..<1) }

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
        gameNumber += 1
        resetWork()
        game.newGame(from: position)
        game.humanColors = setup.opponent == .computer ? [setup.playerColor] : [.white, .black]
        outcome = nil
        gradeLog = [:]
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

    /// A finished game stays finished, on the board as on the clock.
    var canUndo: Bool { game.canUndo && !isOver }

    /// Takes back the last move. Against the computer, its reply is taken back too,
    /// so it is the player's turn again.
    func undo() {
        guard canUndo else { return }
        resetWork()
        takeBack()
        if setup.opponent == .computer, !game.isHumanTurn, game.canUndo {
            takeBack()
        }
        // Grades of moves that are no longer on the board go with them.
        gradeLog = gradeLog.filter { $0.key <= game.plyCount }
        clock?.start(game.sideToMove)
        scheduleWork(after: nil)
    }

    /// Takes one move off the board and its increment off the clock. A pawn still
    /// waiting to be promoted never finished its move, so it earned no increment
    /// (and ChessKit already counts that as the other side's turn).
    private func takeBack() {
        if game.pendingPromotion == nil {
            clock?.tookBack(moveBy: game.sideToMove.opposite)
        }
        game.undo()
    }

    /// Freezes the clock while the board is out of sight: the app in the background,
    /// or a lesson over the game. A computer reply landing meanwhile can't restart it.
    func suspendClock() {
        clock?.hold()
    }

    /// Lets the clock run again once the board is back, unless the game is over.
    /// The side still choosing what its pawn becomes is the one on the clock.
    func resumeClock() {
        guard !isOver else { return }
        clock?.release(game.pendingPromotion?.piece.color ?? game.sideToMove)
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

    /// The clock ran out for `loser`: a win for the other side if it has anything
    /// that could ever give mate, a draw otherwise, as on Lichess and Chess.com.
    func flagFell(_ loser: Piece.Color) {
        guard outcome == nil, !game.isGameOver else { return }
        resetWork()
        // A pawn still waiting to be promoted never finished its move. Put it back,
        // so the picker goes away and the final position is the real one.
        if game.pendingPromotion != nil { game.undo() }
        if Self.hasMatingMaterial(game.board.position.pieces, for: loser.opposite) {
            outcome = .timeout(loser: loser)
            if setup.opponent == .friend || game.humanColors.contains(loser.opposite) {
                sounds?.play(.win)
            } else {
                sounds?.play(.gameOver)
            }
        } else {
            outcome = .timeoutDraw(flagged: loser)
            sounds?.play(.gameOver)
        }
    }

    /// Whether `color` has pieces that could ever deliver mate: any pawn, rook or
    /// queen can, and so can two or more minor pieces unless they are all bishops
    /// on one square colour. A lone king, or a king with one knight or one bishop, cannot.
    static func hasMatingMaterial(_ pieces: [Piece], for color: Piece.Color) -> Bool {
        let own = pieces.filter { $0.color == color && $0.kind != .king }
        if own.contains(where: { $0.kind == .pawn || $0.kind == .rook || $0.kind == .queen }) { return true }
        guard own.count >= 2 else { return false }
        if own.contains(where: { $0.kind == .knight }) { return true }
        return own.contains(where: { $0.square.color == .light }) && own.contains(where: { $0.square.color == .dark })
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

    /// The position a person's move led to, kept so it can be graded after the
    /// computer has already answered it.
    private struct PersonMove {
        let move: PlayedMove
        let fenAfter: String
        let endedGame: Bool
        /// The game's ply count once the move was on the board, for the grade log.
        let ply: Int
    }

    private func refreshHints() {
        hints = showBestMoves ? Array(cachedHints.prefix(showSecondBest ? 2 : 1)) : []
    }

    /// The computer answers first, so its reply never waits on the coach; the
    /// person's move is graded next, then the hints for their next move.
    private func scheduleWork(after personMove: PlayedMove?) {
        let gen = generation
        let played = personMove.map {
            PersonMove(move: $0, fenAfter: game.fen, endedGame: game.isGameOver, ply: game.plyCount)
        }
        work = Task { [weak self] in
            await self?.computerMoveIfNeeded(generation: gen)
            // The game may have moved on (an undo, a new game) while the computer thought.
            guard !Task.isCancelled, self?.generation == gen else { return }
            if let played { await self?.review(played, generation: gen) }
            guard !Task.isCancelled, self?.generation == gen else { return }
            await self?.prepareHints(generation: gen)
        }
    }

    private func review(_ played: PersonMove, generation gen: Int) async {
        guard gen == generation, !Task.isCancelled else { return }
        let move = played.move
        if played.endedGame, game.winner == move.color {
            publishReview(.checkmate, move: move, ply: played.ply, fenAfter: played.fenAfter, best: nil, evaluation: nil)
            return
        }
        guard let engine else { return }

        let before: [EngineLine]
        if let analysis, analysis.fen == move.fenBefore {
            before = analysis.lines
        } else {
            before = await engine.analyze(fen: move.fenBefore, depth: 12, lines: 2, maxTimeMs: 900)
        }
        guard gen == generation, let bestLine = before.first, let bestMove = bestLine.firstMove else { return }

        let playedBest = bestMove == move.uci
        let after: Evaluation
        // The opponent's best answer, so the coach can say what the move allows.
        var reply: String?
        if playedBest {
            after = bestLine.evaluation
            reply = bestLine.moves.dropFirst().first
        } else if before.count > 1, before[1].firstMove == move.uci {
            after = before[1].evaluation
            reply = before[1].moves.dropFirst().first
        } else if played.endedGame {
            after = .centipawns(0)
        } else {
            let answer = await engine.analyze(fen: played.fenAfter, depth: 12, lines: 1, maxTimeMs: 700)
            guard gen == generation, let line = answer.first else { return }
            after = line.evaluation.flipped
            reply = line.firstMove
        }

        let grade = MoveReview.grade(before: bestLine.evaluation, after: after, playedBest: playedBest)
        let bestSAN = playedBest ? nil : Notation.san(of: bestMove, fen: move.fenBefore)
        publishReview(grade, move: move, ply: played.ply, fenAfter: played.fenAfter, best: bestSAN, evaluation: after,
                      bestUCI: bestMove, before: bestLine.evaluation, reply: reply)
        // Only until the next hint search reports on the position as it stands now.
        if analysis?.fen != game.fen {
            evaluation = move.color == .white ? after : after.flipped
        }
    }

    private func publishReview(
        _ grade: MoveReview.Grade, move: PlayedMove, ply: Int, fenAfter: String, best: String?, evaluation: Evaluation?,
        bestUCI: String? = nil, before: Evaluation? = nil, reply: String? = nil
    ) {
        gradeLog[ply] = grade
        guard showVerdicts || grade == .checkmate else { return }
        review = MoveReview(
            id: nextReviewID, grade: grade, played: move.san, best: best, evaluation: evaluation,
            fenBefore: move.fenBefore, fenAfter: fenAfter, playedUCI: move.uci, bestUCI: bestUCI,
            before: before, reply: reply
        )
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
        let chosen = await engine.chooseMove(fen: game.fen, skill: setup.level.skill, thinkTimeMs: setup.level.thinkTimeMs)

        // A short pause so the reply never feels instant.
        let minimum = Duration.milliseconds(450)
        let elapsed = clock.now - started
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
        }
        guard gen == generation else { return }
        isComputerThinking = false

        // The weakest rivals miss things on purpose: now and then they play any
        // legal move instead of the engine's. An engine that gave no move stays a failure.
        let slips = chosen != nil && setup.level.slipRate > 0 && chance() < setup.level.slipRate
        let slip = slips ? randomLegalMove() : nil
        // A slip the game refuses (a castling ChessKit still offers after the rook was
        // taken) falls back to the engine's move.
        var moved = false
        if let slip { moved = game.playEngineMove(slip) }
        if !moved, let chosen { moved = game.playEngineMove(chosen) }
        guard moved, let played = game.lastPlayed else {
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

    /// Any legal move for the side to move, in engine notation; `chance` picks which.
    /// A pawn reaching the last rank becomes a queen (the four-letter form does that).
    private func randomLegalMove() -> String? {
        let board = game.board
        let moves = board.position.pieces
            .filter { $0.color == game.sideToMove }
            .flatMap { piece in board.legalMoves(forPieceAt: piece.square).map { piece.square.notation + $0.notation } }
            .sorted()
        guard !moves.isEmpty else { return nil }
        let index = max(0, min(moves.count - 1, Int(chance() * Double(moves.count))))
        return moves[index]
    }

    private func prepareHints(generation gen: Int) async {
        guard gen == generation, !Task.isCancelled else { return }
        guard let engine, !isOver, game.isHumanTurn, game.pendingPromotion == nil else { return }
        let fen = game.fen
        let lines = await engine.analyze(fen: fen, depth: 14, lines: 2, maxTimeMs: 2000)
        // Only a search that ran its course says anything about the engine; one cut
        // short by an undo or a new game doesn't.
        guard gen == generation, game.fen == fen, !Task.isCancelled else { return }
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
