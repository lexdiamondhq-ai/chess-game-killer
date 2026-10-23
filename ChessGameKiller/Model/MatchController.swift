import ChessKit
import Foundation
import Observation

/// Runs a match: who plays which side, the computer's replies, the coach's
/// verdict on each move, the best-move hints and the clock.
@MainActor
@Observable
final class MatchController {
    /// Who the person plays. Every game here is against a computer rival.
    enum Opponent: String {
        case computer
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
            case .grandmaster: return "Full engine strength"
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
    /// The coach's verdict on the person's last graded move, while verdicts are on.
    private(set) var review: MoveReview?
    /// The same verdict, written into the person's own line by the board for a few seconds.
    private(set) var verdictLine: MoveReview?
    /// How the position stands, from White's point of view. Drives the eval ring.
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
    /// Set while the board is out of sight: the app in the background, or another screen over it.
    /// The clock and the engine wait.
    private(set) var isSuspended = false
    /// The grade of each of the person's moves this game, by the ply count once the
    /// move was on the board, so a move that is taken back leaves the summary too.
    private var gradeLog: [Int: MoveReview.Grade] = [:]
    /// Every graded move of the person's, by ply, for the highlight reel.
    private(set) var reelLog: [Int: ReelMoment] = [:]
    /// Names this game in the player's saved games. A new one for every game.
    private(set) var gameID = UUID()
    /// When this game began.
    private(set) var startedAt = Date()
    /// Where this game began: the standard position, or one set up in Analyze. A rematch starts here too.
    private(set) var startPosition: Position = .standard
    /// Handed the game as it stood whenever a new one starts, so games left
    /// unfinished can still be rewound.
    @ObservationIgnored var onArchive: (@MainActor (SavedGame) -> Void)?
    /// Flipped by the Flip button, on top of the usual "your side at the bottom".
    private(set) var isFlippedByHand = false
    /// Set once the person takes a move back or lets the coach play one for them,
    /// so the army knows the game had help.
    private(set) var wasAssisted = false
    /// Called when a game against the computer is left for a new one: it counts as a loss.
    /// Short games (fewer than two moves each) don't count.
    @ObservationIgnored var onAbandon: ((_ ledger: PieceLedger, _ setup: Setup, _ assisted: Bool) -> Void)?
    /// Handed every grade of the person's moves, shown or not, so the coach can learn from it.
    /// `latest` is false for a move graded late, after the person had already moved again.
    /// Nil when the grades are cleared: an undo, a new game.
    @ObservationIgnored var onReview: (@MainActor (_ review: MoveReview?, _ latest: Bool) -> Void)?
    /// Seconds from a move being played until its piece touches down. The 3D board sets it, so
    /// the move is heard when it lands; the flat board's slide is quick enough to sound at once.
    @ObservationIgnored var landingDelay: @MainActor (PlayedMove) -> TimeInterval = { _ in 0 }
    /// Seconds from the mating move until the end is seen: the king has fallen, in 3D.
    @ObservationIgnored var finaleDelay: @MainActor (PlayedMove) -> TimeInterval = { _ in 0.4 }

    /// The rival's latest remark, shown for a few seconds in its line by the board.
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

    /// Whether the runner-up is marked too.
    var showSecondBest = true {
        didSet { refreshHints() }
    }

    /// Whether moves are graded on screen. Checkmate is always announced.
    var showVerdicts = true {
        didSet {
            guard !showVerdicts else { return }
            if review?.grade != .checkmate { review = nil }
            clearVerdictLine()
        }
    }

    /// Black at the bottom when the player chose black, unless flipped by hand.
    var isBoardFlipped: Bool {
        (setup.playerColor == .black) != isFlippedByHand
    }

    /// Over on the board (mate, draw) or off it (the clock, a resignation).
    var isOver: Bool { game.isGameOver || outcome != nil }

    /// Who won, on the board or off it. Nil for a draw or a game still going.
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
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Bumps whenever the game changes under running work, so stale results are dropped.
    @ObservationIgnored private var generation = 0
    /// Set from the moment work is owed for the position on the board until it has all been
    /// done, so work cut short while the board was out of sight is picked up again.
    @ObservationIgnored private var workPending = false
    @ObservationIgnored private var nextReviewID = 0
    /// The person's moves still to be graded, oldest first. The computer answers before the
    /// coach grades, so a quick player can have a move or two waiting.
    @ObservationIgnored private var pendingReviews: [PersonMove] = []
    /// Engine lines for recent positions, newest last, so a grade or an undo needn't search again.
    @ObservationIgnored private var analyses: [(fen: String, lines: [EngineLine])] = []
    /// Every evaluation shown this game, by position, so an undo puts the right one back.
    @ObservationIgnored private var evaluations: [String: Evaluation] = [:]
    private var cachedHints: [MoveHint] = []
    /// Plies on the board before the person's first move: 1 when the rival opens.
    @ObservationIgnored private var firstPersonPly = 0
    @ObservationIgnored private var lineExpiry: Task<Void, Never>?
    @ObservationIgnored private var verdictExpiry: Task<Void, Never>?

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

    /// How many plies a game needs before leaving it for a new one counts as a loss.
    static let pliesToForfeit = 4

    /// Starting another game now would count this one as a loss. The screens that can start
    /// a game ask first.
    var newGameForfeits: Bool {
        hasStarted && !isOver && game.plyCount >= Self.pliesToForfeit
    }

    /// Starts a game. It begins quietly: the first sound is the first move.
    func start(_ setup: Setup, from position: Position = .standard) {
        // An ending still playing doesn't run into the new game.
        sounds?.stopAll(fade: 0.3)
        // A pawn waiting on the last rank never finished its move: it isn't part of the record.
        if game.pendingPromotion != nil { game.undo() }
        if newGameForfeits {
            if let ledger = game.ledger { onAbandon?(ledger, self.setup, wasAssisted) }
            // Recorded as a loss, quietly: the saved game and the army agree.
            outcome = .resigned(loser: self.setup.playerColor)
        }
        if hasStarted, isOver || game.plyCount >= Self.pliesWorthKeeping, let saved = savedGame() {
            onArchive?(saved)
        }
        gameID = UUID()
        startedAt = Date()
        self.setup = setup
        startPosition = position
        wasAssisted = false
        hasStarted = true
        gameNumber += 1
        resetWork()
        pendingReviews = []
        analyses = []
        evaluations = [:]
        game.newGame(from: position)
        game.humanColors = [setup.playerColor]
        firstPersonPly = game.sideToMove == setup.playerColor ? 0 : 1
        outcome = nil
        hopelessTurns = 0
        gradeLog = [:]
        reelLog = [:]
        isFlippedByHand = false
        evaluation = nil
        engineFailed = false
        startClock()
        clearRivalLine()
        lastLinePly = -10
        rivalSays(.greeting)
        restartWork()
    }

    // MARK: The rival's voice

    /// Has the rival say something about `moment`: always for the big moments, and
    /// otherwise only now and then, never on two moves running. The remark stays a few
    /// seconds (longer ones a little longer), then the rival's line shows its status again.
    func rivalSays(_ moment: RivalMoment) {
        if !moment.isBig {
            guard game.plyCount - lastLinePly >= 3, chance() < 0.75 else { return }
        }
        guard let text = RivalVoice.line(for: moment, level: setup.level, pick: chance()) else { return }
        lastLinePly = game.plyCount
        let line = RivalLine(id: nextLineID, text: text)
        nextLineID += 1
        rivalLine = line
        lineExpiry?.cancel()
        lineExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.0 + Double(text.count) * 0.04))
            guard !Task.isCancelled, let self, self.rivalLine?.id == line.id else { return }
            self.rivalLine = nil
        }
    }

    private func clearRivalLine() {
        lineExpiry?.cancel()
        lineExpiry = nil
        rivalLine = nil
    }

    /// What the move just played means to the rival.
    private func rivalReacts(to played: PlayedMove) {
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

    /// The same game again: same rival, same side, same clock, from the same position.
    func rematch() {
        start(setup, from: startPosition)
    }

    func tap(_ square: Square) {
        guard outcome == nil else { return }
        let movesBefore = game.moveCount
        game.tap(square)
        if game.moveCount != movesBefore {
            didPlayMove(byPerson: true)
        } else if game.selected != nil {
            // The person is on to their next move: the verdict on the last one has had its moment.
            clearVerdictLine()
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

    /// The person changed their mind about a pawn's last step: it goes back, as if never
    /// moved. Nothing was played, so it isn't help and the clock carries on as it was.
    func cancelPromotion() {
        guard game.pendingPromotion != nil, outcome == nil else { return }
        game.undo()
    }

    /// Plays one of the suggested moves for the person. The coach chose it, so it isn't graded:
    /// no grade, no praise, no place in the highlight reel.
    func play(_ hint: MoveHint) {
        guard outcome == nil, game.isHumanTurn, game.pendingPromotion == nil else { return }
        let movesBefore = game.moveCount
        game.playEngineMove(hint.uci)
        if game.moveCount != movesBefore {
            wasAssisted = true
            didPlayMove(byPerson: true, byCoach: true)
        }
    }

    /// Plays a move the person chose off the board, like Play in Talk it through: it is their
    /// own move, so it is graded the same as one made on the board. False when it can't be played.
    @discardableResult
    func playOwnMove(_ uci: String) -> Bool {
        guard outcome == nil, game.isHumanTurn, game.pendingPromotion == nil else { return false }
        let movesBefore = game.moveCount
        guard game.playEngineMove(uci), game.moveCount != movesBefore else { return false }
        didPlayMove(byPerson: true)
        return true
    }

    /// A finished game stays finished. Before the person's first move there is nothing of
    /// theirs to take back (playing Black, the rival's opening move stays).
    var canUndo: Bool { game.canUndo && !isOver && game.plyCount > firstPersonPly }

    /// Takes back the last move. Against the computer, its reply is taken back too,
    /// so it is the player's turn again.
    func undo() {
        guard canUndo else { return }
        // A pawn waiting on the last rank never finished its move: putting it back isn't help.
        if game.pendingPromotion != nil {
            cancelPromotion()
            return
        }
        resetWork()
        wasAssisted = true
        takeBack()
        if !game.isHumanTurn, game.canUndo {
            takeBack()
        }
        // Grades of moves that are no longer on the board go with them.
        pendingReviews.removeAll { $0.ply > game.plyCount }
        gradeLog = gradeLog.filter { $0.key <= game.plyCount }
        reelLog = reelLog.filter { $0.key <= game.plyCount }
        hopelessTurns = 0
        evaluation = evaluations[game.fen]
        clearRivalLine()
        if clockRuns { clock?.start(game.sideToMove) }
        restartWork()
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

    /// The board went out of sight: the app in the background, or a screen over the game.
    /// The clock stops, and so does the match's engine work: the engine is shared with the
    /// screens that open over the game, and the rival shouldn't move, or be heard, where
    /// nobody can see it. Everything carries on in `resume()`.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        clock?.hold()
        if workPending { cancelWork() }
    }

    /// The board is back: the clock runs again if the game is under way, and the computer's
    /// reply, the grades and the hints pick up where they stopped.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        clock?.release(clockRuns ? game.activeColor : nil)
        guard workPending else { return }
        if isOver {
            gradeWhatsLeft()
        } else {
            restartWork()
        }
    }

    /// Turns the board around.
    func flipBoard() {
        isFlippedByHand.toggle()
    }

    /// Whether the person can resign now: a game under way that isn't over.
    var canResign: Bool { hasStarted && !isOver && game.plyCount > 0 }

    /// The person looked at the engine's lines for the game in progress: like Undo, that is help.
    func markAssisted() {
        guard canResign else { return }
        wasAssisted = true
    }

    /// The person gives up.
    func resign() {
        guard canResign else { return }
        end(.resigned(loser: setup.playerColor))
    }

    /// Ends the game off the board: the engine stops, the clock stops, and the right sound plays.
    private func end(_ result: Outcome) {
        cancelWork()
        workPending = false
        hints = []
        cachedHints = []
        clearVerdictLine()
        if game.pendingPromotion != nil { game.undo() }
        game.clearSelection()
        outcome = result
        clock?.pause()
        playEndSound(winner: result.winner)
        switch result {
        case .resigned(let loser) where game.humanColors.contains(loser):
            rivalSays(.playerResigned)
        case .resigned:
            rivalSays(.rivalResigns)
        case .timeout(let loser):
            rivalSays(game.humanColors.contains(loser) ? .rivalWins : .playerWins)
        case .timeoutDraw:
            rivalSays(.draw)
        }
        gradeWhatsLeft()
    }

    /// The victory theme when a person wins, a quiet chime otherwise.
    private func playEndSound(winner: Piece.Color?, after delay: TimeInterval = 0) {
        if let winner, game.humanColors.contains(winner) {
            sounds?.play(.victory, after: delay)
        } else {
            sounds?.play(.gameOver, after: delay)
        }
    }

    /// How far ahead the person must be (in centipawns) for the rival to resign.
    static let resignThreshold = 1500
    /// The person's turns in a row the rival has been that far behind.
    @ObservationIgnored private var hopelessTurns = 0

    /// A rival resigns when it is hopelessly lost two turns running, like a real
    /// player would. A forced mate is left on the board for the person to finish.
    private func rivalConsidersResigning(_ evaluation: Evaluation) {
        guard !isOver, game.isHumanTurn else { return }
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
        GameReel.make(log: reelLog, player: "You", opponent: opponentName, playerColor: setup.playerColor,
                      winner: winner, isOver: isOver, accuracy: accuracy,
                      moveCount: (game.plyCount + 1) / 2, finalFEN: game.fen,
                      pieceName: pieceName, hero: hero)
    }

    /// The opponent by name, for saved games and the highlight reel.
    var opponentName: String {
        setup.level.rival.name
    }

    /// An unfinished game this long is kept when a new one starts.
    static let pliesWorthKeeping = 10

    /// The game so far, for the player's saved games. Nil before the first move.
    func savedGame() -> SavedGame? {
        guard hasStarted, game.plyCount > 0 else { return nil }
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
            id: gameID, date: startedAt, opponent: opponentName,
            level: setup.level.rawValue,
            playerColor: setup.playerColor,
            winner: winner, isOver: isOver, accuracy: accuracy,
            positions: game.positionFENs, moves: game.moves, moments: moments,
            clock: setup.timeControl
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

    /// The clock runs from the first move until the game ends, as on Lichess and Chess.com:
    /// nobody's time goes while the game is still being set up.
    private var clockRuns: Bool { !isOver && game.plyCount > 0 }

    private func startClock() {
        clock?.pause()
        guard setup.timeControl.isTimed else {
            clock = nil
            return
        }
        let clock = ChessClock(control: setup.timeControl)
        clock.onFlag = { [weak self] loser in self?.flagFell(loser) }
        if isSuspended { clock.hold() }
        self.clock = clock
    }

    /// The clock ran out for `loser`: a win for the other side if it has anything
    /// that could ever give mate, a draw otherwise, as on Lichess and Chess.com.
    func flagFell(_ loser: Piece.Color) {
        guard outcome == nil, !game.isGameOver else { return }
        // A pawn still waiting to be promoted never finished its move. Put it back,
        // so the picker goes away and the final position is the real one.
        if game.pendingPromotion != nil { game.undo() }
        if Self.hasMatingMaterial(game.board.position.pieces, for: loser.opposite) {
            end(.timeout(loser: loser))
        } else {
            end(.timeoutDraw(flagged: loser))
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

    // MARK: The coach's verdict in the person's line

    /// How long a verdict stays in the person's line.
    static let verdictSeconds: Double = 4

    private func showVerdict(_ made: MoveReview) {
        verdictLine = made
        verdictExpiry?.cancel()
        verdictExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MatchController.verdictSeconds))
            guard !Task.isCancelled, let self, self.verdictLine?.id == made.id else { return }
            self.verdictLine = nil
        }
    }

    private func clearVerdictLine() {
        verdictExpiry?.cancel()
        verdictExpiry = nil
        verdictLine = nil
    }

    // MARK: Running the match

    /// Cancels the engine work in flight; whatever it was about to report is dropped.
    private func cancelWork() {
        work?.cancel()
        work = nil
        generation += 1
        isComputerThinking = false
    }

    /// Forgets what the engine said about the position on the board: an undo or a new game changed it.
    private func resetWork() {
        cancelWork()
        workPending = false
        review = nil
        clearVerdictLine()
        hints = []
        cachedHints = []
        onReview?(nil, true)
    }

    private func didPlayMove(byPerson: Bool, byCoach: Bool = false) {
        guard let played = game.lastPlayed else { return }
        if byPerson {
            clearVerdictLine()
            if !byCoach {
                pendingReviews.append(PersonMove(
                    move: played, fenAfter: game.fen,
                    mated: game.isGameOver && game.winner == played.color,
                    endedGame: game.isGameOver, ply: game.plyCount,
                    origin: game.ledger?.origin(of: Square(String(played.uci.dropFirst(2).prefix(2))))
                ))
            }
        }
        moveLanded(played)
        hints = []
        cachedHints = []
        restartWork()
    }

    /// What every move brings, the person's or the computer's: its sound, the rival's
    /// reaction, and the clock.
    private func moveLanded(_ played: PlayedMove) {
        playSound(for: played)
        rivalReacts(to: played)
        if game.isGameOver {
            clock?.pause()
            game.clearSelection()
        } else {
            clock?.moved(by: played.color)
        }
    }

    /// One of the person's moves, kept so it can be graded after the computer has already answered it.
    private struct PersonMove {
        let move: PlayedMove
        let fenAfter: String
        /// The move gave checkmate.
        let mated: Bool
        let endedGame: Bool
        /// The game's ply count once the move was on the board, for the grade log.
        let ply: Int
        /// Where the moving piece started the game, so the army can name it.
        let origin: Square?
    }

    private func refreshHints() {
        hints = showBestMoves ? Array(cachedHints.prefix(showSecondBest ? 2 : 1)) : []
    }

    /// Starts the work owed for the position on the board, or leaves it owed while the board is out of sight.
    private func restartWork() {
        cancelWork()
        workPending = true
        guard !isSuspended else { return }
        let gen = generation
        work = Task { [weak self] in
            await self?.runWork(generation: gen)
        }
    }

    /// The computer answers first, so its reply never waits on the coach. Then the person's
    /// moves still waiting are graded, oldest first (only the newest one is shown), and last
    /// come the hints for their next move.
    private func runWork(generation gen: Int) async {
        await computerMoveIfNeeded(generation: gen)
        while gen == generation, !Task.isCancelled, let next = pendingReviews.first {
            let latest = pendingReviews.count == 1
            // False when the game moved on under it: it stays queued for the next round.
            guard await review(next, generation: gen, latest: latest) else { return }
            if pendingReviews.first?.ply == next.ply { pendingReviews.removeFirst() }
        }
        guard gen == generation, !Task.isCancelled else { return }
        await prepareHints(generation: gen)
        if gen == generation, !Task.isCancelled { workPending = false }
    }

    /// Grades the person's moves still waiting when the game ends off the board (a resignation,
    /// the clock), quietly: the summary and the saved game pick them up as they come in.
    private func gradeWhatsLeft() {
        cancelWork()
        guard engine != nil, !pendingReviews.isEmpty else {
            workPending = false
            return
        }
        workPending = true
        guard !isSuspended else { return }
        let gen = generation
        work = Task { [weak self] in
            guard let self else { return }
            while gen == self.generation, !Task.isCancelled, let next = self.pendingReviews.first {
                guard await self.review(next, generation: gen, latest: false) else { return }
                if self.pendingReviews.first?.ply == next.ply { self.pendingReviews.removeFirst() }
            }
            if gen == self.generation { self.workPending = false }
        }
    }

    /// Engine lines already found for a position, if any.
    private func knownLines(for fen: String) -> [EngineLine]? {
        analyses.last(where: { $0.fen == fen })?.lines
    }

    /// Keeps the lines for a position. Only searches that found something are kept.
    private func remember(_ lines: [EngineLine], for fen: String) {
        guard !lines.isEmpty else { return }
        analyses.removeAll { $0.fen == fen }
        analyses.append((fen: fen, lines: lines))
        if analyses.count > 8 { analyses.removeFirst(analyses.count - 8) }
    }

    /// Shows how the position stands (from White's side) and remembers it for undo.
    private func setEvaluation(_ whiteView: Evaluation, for fen: String) {
        evaluation = whiteView
        evaluations[fen] = whiteView
    }

    /// Grades one of the person's moves. Returns false when the game moved on before it was
    /// done (it stays queued), and true once it is graded, or when the engine had nothing to
    /// grade it with (it is let go, so it never holds up the hints).
    private func review(_ played: PersonMove, generation gen: Int, latest: Bool) async -> Bool {
        guard gen == generation, !Task.isCancelled else { return false }
        let move = played.move
        if played.mated {
            publishReview(.checkmate, move: move, ply: played.ply, fenAfter: played.fenAfter, best: nil, evaluation: nil,
                          origin: played.origin, latest: latest)
            return true
        }
        guard let engine else { return true }

        let before: [EngineLine]
        if let known = knownLines(for: move.fenBefore) {
            before = known
        } else {
            before = await engine.analyze(fen: move.fenBefore, depth: 12, lines: 2, maxTimeMs: 900)
            guard gen == generation, !Task.isCancelled else { return false }
            remember(before, for: move.fenBefore)
        }
        guard let bestLine = before.first, let bestMove = bestLine.firstMove else { return true }

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
            guard gen == generation, !Task.isCancelled else { return false }
            guard let line = answer.first else { return true }
            after = line.evaluation.flipped
            reply = line.firstMove
        }

        let grade = MoveReview.grade(before: bestLine.evaluation, after: after, playedBest: playedBest)
        let bestSAN = playedBest ? nil : Notation.san(of: bestMove, fen: move.fenBefore)
        publishReview(grade, move: move, ply: played.ply, fenAfter: played.fenAfter, best: bestSAN, evaluation: after,
                      bestUCI: bestMove, before: bestLine.evaluation, reply: reply, origin: played.origin,
                      line: playedBest ? [] : bestLine.moves, latest: latest)
        // Only until the next hint search reports on the position as it stands now.
        if latest, outcome == nil, knownLines(for: game.fen) == nil {
            setEvaluation(move.color == .white ? after : after.flipped, for: played.fenAfter)
        }
        return true
    }

    private func publishReview(
        _ grade: MoveReview.Grade, move: PlayedMove, ply: Int, fenAfter: String, best: String?, evaluation: Evaluation?,
        bestUCI: String? = nil, before: Evaluation? = nil, reply: String? = nil, origin: Square? = nil,
        line: [String] = [], latest: Bool
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
        let made = MoveReview(
            id: nextReviewID, grade: grade, played: move.san, best: best, evaluation: evaluation,
            fenBefore: move.fenBefore, fenAfter: fenAfter, playedUCI: move.uci, bestUCI: bestUCI,
            before: before, reply: reply, origin: origin
        )
        nextReviewID += 1
        onReview?(made, latest)
        guard latest else { return }
        // The rival notices a blunder, and now and then a best move in a game still in the balance.
        if !isOver {
            switch grade {
            case .blunder: rivalSays(.playerBlunder)
            case .best where (before?.winningChances ?? 0) < 0.85 && chance() < 0.4: rivalSays(.playerGreatMove)
            default: break
            }
        }
        guard showVerdicts || grade == .checkmate else { return }
        review = made
        // The end of a game is announced by the board and the summary, not by a verdict.
        if showVerdicts, !isOver { showVerdict(made) }
    }

    private func computerMoveIfNeeded(generation gen: Int) async {
        guard
            let engine, !isOver, !game.isHumanTurn, game.pendingPromotion == nil
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
        guard gen == generation, !Task.isCancelled else { return }
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
        moveLanded(played)
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
        let lines: [EngineLine]
        if let known = knownLines(for: fen), known.count > 1 {
            lines = known
        } else {
            lines = await engine.analyze(fen: fen, depth: 14, lines: 2, maxTimeMs: 2000)
            // Only a search that ran its course says anything about the engine; one cut
            // short by an undo or a new game doesn't.
            guard gen == generation, game.fen == fen, !Task.isCancelled else { return }
        }
        engineFailed = lines.isEmpty
        // Nothing found is nothing to keep: a grade for the next move asks the engine itself.
        guard let best = lines.first else { return }
        remember(lines, for: fen)
        setEvaluation(game.sideToMove == .white ? best.evaluation : best.evaluation.flipped, for: fen)
        rivalConsidersResigning(best.evaluation)
        if isOver { return }
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

    /// The move's sound as its piece touches down. Check is the bigger news, so it wins over
    /// a capture. The end of a game is heard once it is seen: when the mated king has fallen.
    private func playSound(for move: PlayedMove) {
        guard let sounds else { return }
        let landing = landingDelay(move)
        if move.givesCheck, !game.isGameOver {
            sounds.play(.check, after: landing)
        } else if move.isCapture {
            sounds.play(.capture, after: landing)
        } else if move.isCastle {
            sounds.play(.castle, after: landing)
        } else {
            sounds.play(.move, after: landing)
        }
        if game.isGameOver {
            playEndSound(winner: game.winner, after: game.isCheckmate ? finaleDelay(move) : landing + 0.35)
        }
    }
}
