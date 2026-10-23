import ChessKit
import Foundation
import Observation

/// Perfect Endgames: the player keeps the result (a win, or a draw) against an opponent who
/// never makes a mistake. The Lichess tablebase judges every move when it can be reached;
/// offline, Stockfish on the phone judges instead and plays the other side at full strength.
@MainActor
@Observable
final class EndgameRunner {
    enum Phase: Equatable {
        /// Asking the judge about the starting position.
        case loading
        /// The player's turn.
        case playing
        /// Judging the player's move, finding the reply, or looking for a hint.
        case thinking
        case won, held, failed
        /// Neither the tablebase nor Stockfish could answer.
        case unavailable

        /// The study has ended, well or badly.
        var isFinished: Bool {
            switch self {
            case .won, .held, .failed, .unavailable: return true
            case .loading, .playing, .thinking: return false
            }
        }
    }

    /// How a study was completed, for Leo's closing words.
    enum Finish: Equatable {
        case mate
        /// The player's pawn became a queen and the win holds.
        case promotion
        /// The opponent has nothing left but the king, and the win holds.
        case bareKing
        /// The draw held for the study's number of moves.
        case held
        /// The opponent has no pawns left to win with.
        case noPawns
        /// A draw by rule: stalemate, repetition, too little material.
        case drawn(Board.State.DrawReason)
    }

    let study: EndgameStudy
    let player: Piece.Color
    private(set) var board: GameModel
    private(set) var phase: Phase = .loading
    private(set) var message: String
    private(set) var tone: DrillRunner.Tone = .coach
    /// Leo's hint: the piece to move, then where it goes.
    private(set) var marks: [SquareMark] = []
    /// Who judged last, for the line under the board.
    private(set) var judgeKind: EndgameJudgeKind?
    /// In a mating study: moves to mate with perfect play from here, when the tablebase knows.
    private(set) var mateLeft: Int?
    /// The player's moves that kept the result.
    private(set) var movesMade = 0
    private(set) var slips = 0
    private(set) var hintsUsed = 0

    /// The study ends in mate: the opponent has only a king and the player no pawns.
    let endsInMate: Bool

    private let judge: EndgameJudge
    private let progress: EndgameProgress?
    private let sounds: SoundPlaying?
    /// What the opponent started with, to tell when it has run out.
    private let opponentHadPieces: Bool
    private let opponentHadPawns: Bool
    /// Moves to mate with perfect play from the start, when the tablebase knows.
    @ObservationIgnored private var perfectMate: Int?
    /// Offline only: Stockfish's score, for the player, of the position the player is to move
    /// in. Each move is measured against it.
    @ObservationIgnored private var reference: Evaluation?
    /// The judge's word on the position the player is to move in, kept for hints. A slip
    /// that is taken back leaves it standing.
    @ObservationIgnored private var current: EndgameAssessment?
    /// How far the hint has gone in this position: 0 none, 1 the piece, 2 the move.
    @ObservationIgnored private var hintLevel = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(study: EndgameStudy, judge: EndgameJudge, progress: EndgameProgress? = nil, playsSounds: Bool = true) {
        self.study = study
        self.judge = judge
        self.progress = progress
        sounds = playsSounds ? SoundPlayer.shared : nil
        player = study.player
        let start = Self.startingBoard(for: study)
        board = start
        message = study.idea
        let opponent = start.pieces.map(\.piece).filter { $0.color != study.player }
        opponentHadPieces = opponent.contains { $0.kind != .king }
        opponentHadPawns = opponent.contains { $0.kind == .pawn }
        let playerHasPawns = start.pieces.contains { $0.piece.color == study.player && $0.piece.kind == .pawn }
        endsInMate = study.goal == .win && !opponentHadPieces && !playerHasPawns
    }

    /// The runner the app uses: the Lichess tablebase online, Stockfish offline, progress saved.
    static func live(study: EndgameStudy) -> EndgameRunner {
        EndgameRunner(study: study, judge: .live(), progress: .shared)
    }

    private static func startingBoard(for study: EndgameStudy) -> GameModel {
        let model = GameModel(position: Position(fen: study.fen) ?? .standard)
        model.humanColors = []
        return model
    }

    // MARK: Reading

    /// No slips and no hints so far.
    var isClean: Bool { slips == 0 && hintsUsed == 0 }

    // MARK: Playing

    func start() {
        pending?.cancel()
        phase = .loading
        board.humanColors = []
        pending = Task { [weak self] in
            guard let self else { return }
            guard let assessment = await self.judge.assess(self.board.fen) else {
                if !Task.isCancelled { self.becomeUnavailable() }
                return
            }
            guard !Task.isCancelled else { return }
            self.judgeKind = assessment.judge
            self.current = assessment
            self.reference = assessment.evaluation
            if self.endsInMate, assessment.outcome != nil, let mate = assessment.mate, mate > 0 {
                self.perfectMate = mate
                self.mateLeft = mate
            }
            self.yieldTurn()
        }
    }

    func restart() {
        pending?.cancel()
        board = Self.startingBoard(for: study)
        movesMade = 0
        slips = 0
        hintsUsed = 0
        hintLevel = 0
        marks = []
        mateLeft = nil
        perfectMate = nil
        reference = nil
        current = nil
        tone = .coach
        message = study.idea
        judge.retryTablebase()
        start()
    }

    func cancel() { pending?.cancel() }

    func tap(_ square: Square) {
        guard phase == .playing else { return }
        let before = board.moveCount
        board.tap(square)
        if board.pendingPromotion != nil { board.promote(to: .queen) }
        if board.moveCount != before, let played = board.lastPlayed {
            respond(to: played)
        }
    }

    /// Leo's hint, in two steps: first the piece to move, then the move itself.
    func hint() {
        guard phase == .playing else { return }
        if let best = current?.best {
            showHint(best)
            return
        }
        phase = .thinking
        pending = Task { [weak self] in
            guard let self else { return }
            let assessment = await self.judge.assess(self.board.fen)
            guard !Task.isCancelled else { return }
            if let assessment {
                self.current = assessment
                self.judgeKind = assessment.judge
                if let evaluation = assessment.evaluation { self.reference = evaluation }
            }
            self.yieldTurn()
            if let best = assessment?.best {
                self.showHint(best)
            } else {
                self.tone = .hint
                self.message = "No hint just now. Trust the plan: \(self.study.idea)"
            }
        }
    }

    // MARK: Judging

    private func yieldTurn() {
        phase = .playing
        board.humanColors = [player]
    }

    private func respond(to played: PlayedMove) {
        board.humanColors = []
        marks = []
        hintLevel = 0
        if board.isGameOver {
            endOfGame(after: played)
            return
        }
        phase = .thinking
        pending = Task { [weak self] in
            await self?.judgeMove(played)
        }
    }

    private func judgeMove(_ played: PlayedMove) async {
        guard let after = await judge.assess(board.fen) else {
            if !Task.isCancelled { becomeUnavailable() }
            return
        }
        guard !Task.isCancelled else { return }
        judgeKind = after.judge
        // Offline, a move is measured against Stockfish's score before it. When the tablebase
        // judged until now there is none yet, so Stockfish looks at the position before the move.
        if after.outcome == nil, reference == nil {
            let before = await judge.assess(played.fenBefore)
            guard !Task.isCancelled else { return }
            reference = before?.evaluation
        }
        if let result = slipResult(after) {
            await takeBack(saying: slipLine(played.san, result: result))
            return
        }
        movesMade += 1
        // A new position is coming, so the old word on it (kept for hints after a slip) goes.
        current = nil
        reference = after.evaluation?.flipped
        if endsInMate {
            mateLeft = after.outcome != nil ? after.mate.flatMap { $0 < 0 ? -$0 : nil } : nil
        }
        if let finish = finish(after: played) {
            succeed(finish)
            return
        }
        tone = .success
        message = goodLine()
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        guard let reply = after.best, board.playEngineMove(reply) else {
            becomeUnavailable()
            return
        }
        sounds?.play(.move)
        if board.isGameOver {
            endOfGame(after: nil)
            return
        }
        yieldTurn()
    }

    /// The player's result after a move that gave the goal away (0 a draw, -1 a loss), or nil
    /// when the move kept it.
    private func slipResult(_ after: EndgameAssessment) -> Int? {
        if let outcome = after.outcome {
            let result = -outcome
            return result < study.goal.value ? result : nil
        }
        guard let evaluation = after.evaluation?.flipped,
              EngineReferee.isSlip(goal: study.goal, played: evaluation, reference: reference) else { return nil }
        return EngineReferee.looksLost(evaluation) ? -1 : 0
    }

    /// Shows what went wrong and why, then takes the move back for another try.
    private func takeBack(saying line: String) async {
        phase = .thinking
        slips += 1
        tone = .wrong
        message = line
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        board.undo()
        yieldTurn()
    }

    /// Whether the study is complete after one of the player's good moves.
    private func finish(after played: PlayedMove) -> Finish? {
        let opponent = board.pieces.map(\.piece).filter { $0.color != player }
        switch study.goal {
        case .win:
            if played.uci.count == 5 { return .promotion }
            if opponentHadPieces, !opponent.contains(where: { $0.kind != .king }) { return .bareKing }
            return nil
        case .draw:
            if opponentHadPawns, !opponent.contains(where: { $0.kind == .pawn }) { return .noPawns }
            return movesMade >= study.movesToHold ? .held : nil
        }
    }

    /// The game is over on the board: mate, stalemate, or a draw by rule. `played` is the
    /// player's move when it was the one that ended it.
    private func endOfGame(after played: PlayedMove?) {
        if let winner = board.winner {
            if winner == player {
                movesMade += 1
                succeed(.mate)
            } else {
                fail("Checkmate: that one got away. \(study.tip)")
            }
            return
        }
        guard case .draw(let reason) = board.state else { return }
        if study.goal == .draw {
            if played != nil { movesMade += 1 }
            succeed(.drawn(reason))
        } else if reason == .fiftyMoves {
            fail("Fifty moves without a capture or a pawn move: that's a draw. Try again, a little quicker.")
        } else if let played {
            phase = .thinking
            pending = Task { [weak self] in
                guard let self else { return }
                await self.takeBack(saying: "\(Self.drawLine(played.san, reason)) \(self.study.tip)")
            }
        } else {
            fail("A draw by \(reason.displayName), and the win is gone. \(study.tip)")
        }
    }

    private func succeed(_ finish: Finish) {
        phase = study.goal == .draw ? .held : .won
        board.humanColors = []
        marks = []
        tone = .success
        message = closingLine(finish)
        sounds?.play(.win)
        progress?.record(study, moves: movesMade, clean: isClean)
    }

    private func fail(_ line: String) {
        phase = .failed
        board.humanColors = []
        marks = []
        tone = .wrong
        message = line
    }

    private func becomeUnavailable() {
        phase = .unavailable
        board.humanColors = []
        marks = []
        tone = .wrong
        message = "Couldn't reach the tablebase, and Stockfish isn't ready yet. Try again in a moment."
    }

    // MARK: Hints

    private func showHint(_ uci: String) {
        guard let squares = Notation.squares(of: uci) else { return }
        if hintLevel == 0 { hintsUsed += 1 }
        hintLevel = min(hintLevel + 1, 2)
        tone = .hint
        let from = SquareMark(square: squares.from.notation, color: .yellow)
        if hintLevel == 1 {
            marks = [from]
            let kind = board.piece(at: squares.from)?.kind.word ?? "pieces"
            message = "Look at your \(kind)."
        } else {
            marks = [from, SquareMark(square: squares.to.notation, color: .yellow)]
            let san = Notation.san(of: uci, fen: board.fen) ?? uci
            message = "\(san) keeps the \(study.goal.rawValue)."
        }
    }

    // MARK: Words

    private func goodLine() -> String {
        let lines = study.goal == .win
            ? ["Good. Still winning.", "That keeps the win.", "Still winning. Keep going."]
            : ["Good. The draw holds.", "Still holding.", "That holds too."]
        return lines[(movesMade - 1) % lines.count]
    }

    private func slipLine(_ san: String, result: Int) -> String {
        let what: String
        switch (study.goal, result) {
        case (.win, 0): what = "lets the win slip to a draw."
        case (.win, _): what = "even loses."
        case (.draw, _): what = "loses."
        }
        return "\(san) \(what) \(study.tip)"
    }

    /// "1 move", "12 moves".
    static func moves(_ count: Int) -> String {
        count == 1 ? "1 move" : "\(count) moves"
    }

    private static func drawLine(_ san: String, _ reason: Board.State.DrawReason) -> String {
        switch reason {
        case .stalemate: return "\(san) is stalemate, and the win is gone."
        case .repetition: return "\(san) repeats the position a third time: a draw."
        case .insufficientMaterial: return "\(san) leaves too little to mate with."
        case .fiftyMoves, .agreement: return "\(san) lets it end in a draw."
        }
    }

    private func closingLine(_ finish: Finish) -> String {
        switch finish {
        case .mate:
            let mate = "Checkmate in \(Self.moves(movesMade))"
            guard let perfectMate else { return "\(mate)." }
            return movesMade <= perfectMate ? "\(mate): perfect play!" : "\(mate). Perfect play needs \(perfectMate)."
        case .promotion:
            return "A new queen, and the win is safe. Well played."
        case .bareKing:
            return "Only their king is left, and the win is safe. Well played."
        case .held:
            return "Held! \(Self.moves(movesMade)) against perfect play."
        case .noPawns:
            return "No pawns left to win with. Held!"
        case .drawn(let reason):
            return "Draw by \(reason.displayName). Held!"
        }
    }
}
