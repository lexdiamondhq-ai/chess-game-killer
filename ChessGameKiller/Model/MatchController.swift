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
            case .beginner: return 80
            case .casual: return 120
            case .club: return 200
            case .expert: return 350
            case .grandmaster: return 600
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

    /// How the game ended when the board itself doesn't say (the clock, or a resignation).
    enum Outcome: Equatable {
        case timeout(loser: Piece.Color)
        /// The flag fell, but the other side has nothing that could ever give mate.
        case timeoutDraw(flagged: Piece.Color)
        /// One side gave up: the person, or a rival with no way back.
        case resigned(loser: Piece.Color)

        /// Nil for a draw.
        var winner: Piece.Color? {
            switch self {
            case .timeout(let loser), .resigned(let loser): return loser.opposite
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
    /// Every graded move of the person's, by ply, for the highlight reel.
    private(set) var reelLog: [Int: ReelMoment] = [:]
    /// Names this game in the player's saved games. A new one for every game.
    private(set) var gameID = UUID()
    /// When this game began.
    private(set) var startedAt = Date()
    /// Handed the game as it stood whenever a new one starts, so games left
    /// unfinished can still be rewound.
    @ObservationIgnored var onArchive: (@MainActor (SavedGame) -> Void)?
    /// Flipped by the Flip button, on top of the usual "your side at the bottom".
    private(set) var isFlippedByHand = false
    /// Set once the person takes a move back or lets the coach play one for them,
    /// so the army knows the game had help.
    private(set) var wasAssisted = false
    /// Called when a game against the computer is left unfinished for a new one,
    /// so it can count as a loss. Short games (fewer than two moves each) don't count.
    @ObservationIgnored var onAbandon: ((_ ledger: PieceLedger, _ setup: Setup, _ assisted: Bool) -> Void)?

    /// The rival's latest remark, shown in a bubble by its portrait. Nil against a friend.
    private(set) var rivalLine: RivalLine?
    private var nextLineID = 0
    /// The ply of the rival's last remark, so it doesn't talk over every move.
    private var lastLinePly = -10

    /// What this game is worth to the army.
    var armyStakes: GameStakes {
        GameStakes(level: setup.level, assisted: wasAssisted)
    }

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
        if hasStarted, self.setup.opponent == .computer, !isOver, game.plyCount >= 4,
           let ledger = game.ledger {
            onAbandon?(ledger, self.setup, wasAssisted)
        }
        if hasStarted, isOver || game.plyCount >= Self.pliesWorthKeeping, let saved = savedGame() {
            onArchive?(saved)
        }
        gameID = UUID()
        startedAt = Date()
        self.setup = setup
        wasAssisted = false
        hasStarted = true
        gameNumber += 1
        resetWork()
        game.newGame(from: position)
        game.humanColors = setup.opponent == .computer ? [setup.playerColor] : [.white, .black]
        outcome = nil
        hopelessTurns = 0
        gradeLog = [:]
        reelLog = [:]
        isFlippedByHand = false
        evaluation = nil
        startClock()
        if playSound { sounds?.play(.gameStart) }
        rivalLine = nil
        lastLinePly = -10
        rivalSays(.greeting)
        scheduleWork(after: nil)
    }

    // MARK: The rival's voice

    /// Has the rival say something about `moment`: always for the big moments, and
    /// otherwise only now and then, never on two moves running.
    func rivalSays(_ moment: RivalMoment) {
        guard setup.opponent == .computer else { return }
        if !moment.isBig {
            guard game.plyCount - lastLinePly >= 3, chance() < 0.75 else { return }
        }
        guard let text = RivalVoice.line(for: moment, level: setup.level, pick: chance()) else { return }
        lastLinePly = game.plyCount
        rivalLine = RivalLine(id: nextLineID, text: text)
        nextLineID += 1
    }

    /// What the move just played means to the rival.
    private func rivalReacts(to played: PlayedMove) {
        guard setup.opponent == .computer else { return }
        let byRival = !game.humanColors.contains(played.color)
        if game.isGameOver {
            if let winner = game.winner {
                rivalSays(game.humanColors.contains(winner) ? .playerWins : .rivalWins)
            } else {
                rivalSays(.draw)
            }
            return
        }
        if played.isCapture, let taken = game.captureEvents.last?.piece.kind {
            rivalSays(byRival ? .tookPiece(taken) : .lostPiece(taken))
        } else if played.givesCheck {
            rivalSays(byRival ? .givesCheck : .inCheck)
        }
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
            wasAssisted = true
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
        wasAssisted = true
        takeBack()
        if setup.opponent == .computer, !game.isHumanTurn, game.canUndo {
            takeBack()
        }
        // Grades of moves that are no longer on the board go with them.
        gradeLog = gradeLog.filter { $0.key <= game.plyCount }
        reelLog = reelLog.filter { $0.key <= game.plyCount }
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

    /// Whether the person can resign now: a game under way that isn't over.
    var canResign: Bool { hasStarted && !isOver && game.plyCount > 0 }

    /// The person gives up. Against a friend, the side to move does.
    func resign() {
        guard canResign else { return }
        let loser = setup.opponent == .computer ? setup.playerColor : game.activeColor
        end(.resigned(loser: loser))
    }

    /// Ends the game off the board: work stops, the clock stops, and the right sound plays.
    private func end(_ result: Outcome) {
        resetWork()
        if game.pendingPromotion != nil { game.undo() }
        outcome = result
        clock?.pause()
        playEndSound(winner: result.winner)
        if case .resigned(let loser) = result, !game.humanColors.contains(loser) {
            rivalSays(.rivalResigns)
        } else if let winner = result.winner {
            rivalSays(game.humanColors.contains(winner) ? .playerWins : .rivalWins)
        } else {
            rivalSays(.draw)
        }
    }

    /// The victory theme when a person wins, a quiet chime otherwise.
    private func playEndSound(winner: Piece.Color?) {
        if let winner, setup.opponent == .friend || game.humanColors.contains(winner) {
            sounds?.play(.victory)
        } else {
            sounds?.play(.gameOver)
        }
    }

    /// How far ahead the person must be (in centipawns) for the rival to resign.
    static let resignThreshold = 1500
    /// The person's turns in a row the rival has been that far behind.
    private var hopelessTurns = 0

    /// A rival resigns when it is hopelessly lost two turns running, like a real
    /// player would. A forced mate is left on the board for the person to finish.
    private func rivalConsidersResigning(_ evaluation: Evaluation) {
        guard setup.opponent == .computer, !isOver, game.isHumanTurn else { return }
        if case .centipawns(let cp) = evaluation, cp >= Self.resignThreshold {
            hopelessTurns += 1
        } else {
            hopelessTurns = 0
        }
        if hopelessTurns >= 2 {
            end(.resigned(loser: setup.playerColor.opposite))
        }
    }

    /// The game's story for the highlight reel. `pieceName` names the player's
    /// piece that started on a square, and `hero` is the Piece of the Match line.
    func highlightReel(pieceName: (Square) -> String? = { _ in nil }, hero: String? = nil) -> GameReel {
        let opponent = setup.opponent == .computer ? setup.level.rival.name : "Friend"
        return GameReel.make(log: reelLog, player: "You", opponent: opponent, playerColor: setup.playerColor,
                             winner: winner, isOver: isOver, accuracy: accuracy,
                             moveCount: (game.plyCount + 1) / 2, finalFEN: game.fen,
                             pieceName: pieceName, hero: hero)
    }

    /// An unfinished game this long is kept when a new one starts.
    static let pliesWorthKeeping = 10

    /// The game so far, for the player's saved games. Nil before the first move.
    func savedGame() -> SavedGame? {
        guard hasStarted, game.plyCount > 0 else { return nil }
        let isComputer = setup.opponent == .computer
        let moments = reelLog.values.sorted { $0.ply < $1.ply }.map { moment in
            SavedMoment(
                ply: moment.ply, grade: moment.grade.rawValue, san: moment.san, uci: moment.uci,
                byWhite: moment.color == .white, fenBefore: moment.fenBefore, fenAfter: moment.fenAfter,
                best: moment.best, bestUCI: moment.bestUCI, bestLine: moment.bestLine, reply: moment.reply,
                before: moment.before, after: moment.after,
                beforeEval: moment.beforeEval, afterEval: moment.afterEval
            )
        }
        return SavedGame.make(
            id: gameID, date: startedAt, opponent: isComputer ? setup.level.rival.name : "Friend",
            level: isComputer ? setup.level.rawValue : nil,
            playerColor: isComputer ? setup.playerColor : .white,
            winner: winner, isOver: isOver, accuracy: accuracy,
            positions: game.positionFENs, moves: game.moves, moments: moments
        )
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
            playEndSound(winner: loser.opposite)
            rivalSays(game.humanColors.contains(loser.opposite) ? .playerWins : .rivalWins)
        } else {
            outcome = .timeoutDraw(flagged: loser)
            sounds?.play(.gameOver)
            rivalSays(.draw)
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
        rivalReacts(to: played)
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
        /// Where the moving piece started the game, so the army can name it.
        let origin: Square?
    }

    private func refreshHints() {
        hints = showBestMoves ? Array(cachedHints.prefix(showSecondBest ? 2 : 1)) : []
    }

    /// The computer answers first, so its reply never waits on the coach; the
    /// person's move is graded next, then the hints for their next move.
    private func scheduleWork(after personMove: PlayedMove?) {
        let gen = generation
        let played = personMove.map {
            PersonMove(move: $0, fenAfter: game.fen, endedGame: game.isGameOver, ply: game.plyCount,
                       origin: game.ledger?.origin(of: Square(String($0.uci.dropFirst(2).prefix(2)))))
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
            publishReview(.checkmate, move: move, ply: played.ply, fenAfter: played.fenAfter, best: nil, evaluation: nil,
                          origin: played.origin)
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
                      bestUCI: bestMove, before: bestLine.evaluation, reply: reply, origin: played.origin,
                      line: playedBest ? [] : bestLine.moves)
        // Only until the next hint search reports on the position as it stands now.
        if analysis?.fen != game.fen {
            evaluation = move.color == .white ? after : after.flipped
        }
    }

    private func publishReview(
        _ grade: MoveReview.Grade, move: PlayedMove, ply: Int, fenAfter: String, best: String?, evaluation: Evaluation?,
        bestUCI: String? = nil, before: Evaluation? = nil, reply: String? = nil, origin: Square? = nil,
        line: [String] = []
    ) {
        gradeLog[ply] = grade
        reelLog[ply] = ReelMoment(
            ply: ply, grade: grade, san: move.san, uci: move.uci, color: move.color,
            fenBefore: move.fenBefore, fenAfter: fenAfter, best: best,
            before: before?.winningChances ?? evaluation?.winningChances ?? 0,
            after: grade == .checkmate ? 1 : (evaluation?.winningChances ?? 0),
            origin: origin,
            bestUCI: best == nil ? nil : bestUCI, bestLine: line, reply: reply,
            beforeEval: before, afterEval: evaluation
        )
        // The rival notices a blunder, and now and then a best move in a game still in the balance.
        switch grade {
        case .blunder: rivalSays(.playerBlunder)
        case .best where (before?.winningChances ?? 0) < 0.85 && chance() < 0.4: rivalSays(.playerGreatMove)
        default: break
        }
        guard showVerdicts || grade == .checkmate else { return }
        review = MoveReview(
            id: nextReviewID, grade: grade, played: move.san, best: best, evaluation: evaluation,
            fenBefore: move.fenBefore, fenAfter: fenAfter, playedUCI: move.uci, bestUCI: bestUCI,
            before: before, reply: reply, origin: origin
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
        let fen = game.fen
        let level = setup.level
        // The engine can miss an answer (a search it was still finishing, a stop it
        // never acknowledged). Ask again before giving up, with a little more time.
        var chosen: String?
        for attempt in 0..<Self.engineAttempts {
            chosen = await engine.chooseMove(fen: fen, skill: level.skill,
                                             thinkTimeMs: level.thinkTimeMs * (attempt + 1))
            guard gen == generation, !Task.isCancelled else { return }
            if chosen != nil { break }
            NSLog("Computer move: engine gave no move (attempt %d)", attempt + 1)
        }
        let engineAnswered = chosen != nil

        // A short pause so the reply never feels instant.
        let minimum = Duration.milliseconds(250)
        let elapsed = clock.now - started
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
        }
        guard gen == generation else { return }
        isComputerThinking = false

        // The weakest rivals miss things on purpose: now and then they play any
        // legal move instead of the engine's.
        let slips = engineAnswered && level.slipRate > 0 && chance() < level.slipRate
        let slip = slips ? randomLegalMove() : nil
        // A slip the game refuses (a castling ChessKit still offers after the rook was
        // taken) falls back to the engine's move.
        var moved = false
        if let slip { moved = game.playEngineMove(slip) }
        if !moved, let chosen { moved = game.playEngineMove(chosen) }
        // The game must never freeze on the computer's turn: with no answer from the
        // engine at all, the rival still plays a sensible move of its own.
        if !moved, let fallback = fallbackMove() { moved = game.playEngineMove(fallback) }
        guard moved, let played = game.lastPlayed else {
            engineFailed = true
            return
        }
        engineFailed = !engineAnswered
        playSound(for: played)
        rivalReacts(to: played)
        if game.isGameOver {
            self.clock?.pause()
        } else {
            self.clock?.moved(by: played.color)
        }
    }

    /// How many times the computer asks the engine for its move before playing one of its own.
    static let engineAttempts = 3

    /// A move for the side to move when the engine has nothing: mate if there is one,
    /// otherwise the most valuable safe-looking capture, otherwise any legal move.
    private func fallbackMove() -> String? {
        let board = game.board
        let position = board.position
        let value: (Piece.Kind) -> Int = { kind in
            switch kind {
            case .pawn: return 1
            case .knight, .bishop: return 3
            case .rook: return 5
            case .queen: return 9
            case .king: return 0
            }
        }
        var best: (move: String, score: Int)?
        for piece in position.pieces where piece.color == game.sideToMove {
            for target in board.legalMoves(forPieceAt: piece.square) {
                let uci = piece.square.notation + target.notation
                let probe = GameModel(position: position)
                guard probe.playEngineMove(uci) else { continue }
                var score = 0
                if probe.isGameOver, probe.winner == piece.color { score = 1000 }
                if let taken = position.pieces.first(where: { $0.square == target }) { score += value(taken.kind) * 10 - value(piece.kind) }
                if best == nil || score > best!.score { best = (uci, score) }
            }
        }
        if let best, best.score > 0 { return best.move }
        return randomLegalMove()
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
            rivalConsidersResigning(best.evaluation)
            if isOver { return }
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
            playEndSound(winner: game.winner)
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
