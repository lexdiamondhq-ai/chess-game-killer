import ChessKit
import Foundation
import Observation

/// Blunder Shield: a position and two moves. One is safe, the other loses something.
/// Pick the safe one before the gold ring runs out. Ten positions make a round; every safe
/// pick in a row grows the shield.
///
/// Positions come from the player's own game mistakes first (the move they played against
/// the engine's), then from the Lichess pack: a puzzle starts with the opponent's blunder,
/// so that move is the bad one and Stockfish names a safe one beside it.
struct ShieldPosition: Equatable, Identifiable {
    enum Source: Equatable {
        /// A mistake from one of the player's own games.
        case yours
        /// A puzzle from the Lichess pack.
        case lichess
    }

    let id: String
    /// The position, with the side choosing to move.
    let fen: String
    /// The move that keeps everything, in engine notation.
    let safe: String
    /// The move that loses something, in engine notation.
    let blunder: String
    let source: Source

    /// The side choosing, at the bottom of the board.
    var mover: Piece.Color { TrainingChess.sideToMove(fen) ?? .white }

    /// A saved game mistake, when both moves are legal and differ.
    init?(mistake: GameMistake) {
        guard !mistake.played.isEmpty, mistake.played != mistake.best,
              Notation.san(of: mistake.best, fen: mistake.fen) != nil,
              Notation.san(of: mistake.played, fen: mistake.fen) != nil else { return nil }
        id = "mistake-\(mistake.id)"
        fen = mistake.fen
        safe = mistake.best
        blunder = mistake.played
        source = .yours
    }

    /// A Lichess puzzle's opening blunder beside the engine's move there, when the engine's move
    /// is another move and holds the position (not already lost before the blunder).
    init?(puzzle: LichessPuzzle, engineLine: EngineLine?) {
        guard let blunder = puzzle.moves.first, let line = engineLine, let safe = line.firstMove,
              safe.prefix(4) != blunder.prefix(4), Self.holds(line.evaluation),
              Notation.san(of: safe, fen: puzzle.fen) != nil,
              Notation.san(of: blunder, fen: puzzle.fen) != nil else { return nil }
        id = "lichess-\(puzzle.id)"
        fen = puzzle.fen
        self.safe = safe
        self.blunder = blunder
        source = .lichess
    }

    init(id: String, fen: String, safe: String, blunder: String, source: Source) {
        self.id = id
        self.fen = fen
        self.safe = safe
        self.blunder = blunder
        self.source = source
    }

    /// How far behind the side to move may be with the safe move and still call it safe:
    /// a pawn and a half.
    static let worstSafe = -150

    static func holds(_ evaluation: Evaluation) -> Bool {
        switch evaluation {
        case .centipawns(let cp): return cp >= worstSafe
        case .mate(let n): return n > 0
        }
    }
}

/// One of the two cards: the move as people read it, and a few words on what it does.
struct ShieldOption: Equatable, Identifiable {
    let uci: String
    /// Standard notation, like "Nxe5".
    let san: String
    /// Like "knight takes" or "castles".
    let words: String
    let isSafe: Bool

    var id: String { uci }

    init?(uci: String, fen: String, isSafe: Bool) {
        guard let san = Notation.san(of: uci, fen: fen) else { return nil }
        self.uci = uci
        self.san = san
        self.isSafe = isSafe
        words = Self.words(for: uci, fen: fen)
    }

    /// A few plain words for a move: "pawn takes", "queen gives check", "castles".
    static func words(for uci: String, fen: String) -> String {
        guard let position = Position(fen: fen), let squares = Notation.squares(of: uci),
              let piece = position.piece(at: squares.from) else { return "" }
        var board = Board(position: position)
        guard let move = TrainingChess.play(uci, on: &board) else { return "" }
        if case .castle = move.result { return "castles" }
        let name = Self.name(of: piece.kind)
        if TrainingChess.promotionKind(of: uci) != nil || (piece.kind == .pawn && (squares.to.rankIndex == 0 || squares.to.rankIndex == 7)) {
            return "pawn promotes"
        }
        let takes = TrainingChess.isCapture(move)
        let check = TrainingChess.givesCheck(move)
        switch (takes, check) {
        case (true, true): return "\(name) takes with check"
        case (true, false): return "\(name) takes"
        case (false, true): return "\(name) gives check"
        case (false, false): return "\(name) moves"
        }
    }

    private static func name(of kind: Piece.Kind) -> String {
        switch kind {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }
}

/// How one position went.
enum ShieldOutcome: Equatable {
    case safe
    case blundered
    case timedOut

    var isSafe: Bool { self == .safe }
}

/// A round of ten: what each position came to, and the longest run of safe picks in it.
struct ShieldRound: Equatable {
    static let length = 10

    private(set) var outcomes: [ShieldOutcome] = []
    private(set) var longestRun = 0
    private var run = 0

    var safe: Int { outcomes.filter(\.isSafe).count }
    var isFinished: Bool { outcomes.count >= Self.length }

    mutating func add(_ outcome: ShieldOutcome) {
        guard !isFinished else { return }
        outcomes.append(outcome)
        run = outcome.isSafe ? run + 1 : 0
        longestRun = max(longestRun, run)
    }

    /// Leo's line on the round.
    var summary: String {
        switch safe {
        case Self.length: return "Ten out of ten. Not one piece given away. That is a wall."
        case 8...: return "Strong. You spotted almost every trap. Look once more at the ones that got through."
        case 5...: return "Good work. The traps that got you are worth a second look: a quick check before every move stops them."
        default: return "Traps are sneaky. Before each move ask: what can they take after this? It gets easier fast."
        }
    }
}

/// A Blunder Shield session: the positions in turn, the countdown, the shield (safe picks in
/// a row, carried from round to round) and the best shield ever, which is saved.
@MainActor
@Observable
final class BlunderShieldSession {
    enum Stage: Equatable {
        /// Finding the next position.
        case loading
        /// The two cards are up and the ring is running.
        case choosing
        /// The pick is in: the safe move in green, the other in red.
        case revealed
        /// The round is over and its score is up.
        case summary
        /// There was nothing to show.
        case empty
    }

    /// Seconds to pick in.
    static let defaultLimit: TimeInterval = 10

    private(set) var stage: Stage = .loading
    private(set) var position: ShieldPosition?
    private(set) var game: GameModel?
    /// The two cards, in the order shown.
    private(set) var options: [ShieldOption] = []
    /// The card picked, or nil when time ran out.
    private(set) var picked: ShieldOption?
    private(set) var outcome: ShieldOutcome?
    private(set) var round = ShieldRound()
    /// Safe picks in a row.
    private(set) var shield = 0
    /// When the ring started on this position.
    private(set) var startedAt = Date()
    /// When the pick came, so the ring stops where it was.
    private(set) var pickedAt: Date?
    /// Whether this round set a new best shield.
    private(set) var newBest = false

    let limit: TimeInterval
    private let engine: ChessEngine?
    private let puzzles: PuzzleStore?
    private let sounds: SoundPlaying?
    @ObservationIgnored private var mistakes: [GameMistake]
    private let library: PuzzleLibrary?
    @ObservationIgnored private var ready: [ShieldPosition] = []
    /// Mistakes and puzzles already put up or turned down this session.
    @ObservationIgnored private var usedMistakes: Set<String> = []
    @ObservationIgnored private var usedPuzzles: Set<String> = []
    @ObservationIgnored private var filler: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var dry = false
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    private let rating: Int
    /// How many positions to keep found ahead of the one on the board.
    static let lookAhead = 2

    /// A session over the player's open mistakes, then the puzzles near `rating`. The engine
    /// names the safe move in a puzzle; without one only the player's own mistakes are used.
    init(mistakes: [GameMistake], library: PuzzleLibrary?, rating: Int, engine: ChessEngine?,
         store: PuzzleStore?, sounds: SoundPlaying?, limit: TimeInterval = BlunderShieldSession.defaultLimit) {
        var shuffled = mistakes.filter { !$0.fixed }
        shuffled.shuffle()
        self.mistakes = shuffled
        self.library = library
        // Spotting a trap is easier than finding the win, so the puzzles sit a little below the
        // player's puzzle rating.
        self.rating = max(600, rating - 200)
        self.engine = engine
        puzzles = store
        self.sounds = sounds
        self.limit = limit
    }

    /// The best shield ever, when results are being saved.
    var best: Int { max(puzzles?.progress.shieldBest ?? 0, shield) }

    /// The position on the board, from 1.
    var number: Int { min(ShieldRound.length, round.outcomes.count + (stage == .revealed ? 0 : 1)) }

    /// After the pick: the safe move in green and the one that loses in red.
    var arrows: [BoardArrow] {
        guard stage == .revealed, let position else { return [] }
        return [(position.blunder, TrainingColor.red), (position.safe, TrainingColor.green)].compactMap { uci, color in
            Notation.squares(of: uci).map { BoardArrow(from: $0.from.notation, to: $0.to.notation, color: color, dashed: nil) }
        }
    }

    /// Leo's word on the pick.
    var verdict: String {
        guard let outcome, let safe = options.first(where: \.isSafe),
              let blunder = options.first(where: { !$0.isSafe }) else { return "" }
        let yours = position?.source == .yours
        switch outcome {
        case .safe:
            return yours ? "Shielded. In your game you played \(blunder.san). This time you saw the trap."
                         : "Shielded. \(safe.san) keeps everything. \(blunder.san) walks into a trap, shown in red."
        case .blundered:
            return yours ? "That's the move you played in your game, and it cost you. \(safe.san) was safe."
                         : "\(blunder.san) loses something: see the red arrow. \(safe.san) was the safe move."
        case .timedOut:
            return "Time's up. \(safe.san) was safe; \(blunder.san) walks into a trap."
        }
    }

    func start() {
        guard stage == .loading, position == nil else { return }
        fill()
    }

    func cancel() {
        filler?.cancel()
        filler = nil
        clock?.cancel()
        clock = nil
    }

    // MARK: Picking

    /// The player taps a card.
    func pick(_ option: ShieldOption) {
        guard stage == .choosing else { return }
        reveal(option)
    }

    /// The next position, or the round's score once ten are done.
    func next() {
        guard stage == .revealed else { return }
        if round.isFinished {
            finishRound()
            return
        }
        present()
    }

    /// A fresh round of ten. The shield carries on.
    func newRound() {
        guard stage == .summary else { return }
        round = ShieldRound()
        newBest = false
        present()
    }

    private func reveal(_ option: ShieldOption?) {
        clock?.cancel()
        clock = nil
        picked = option
        pickedAt = Date()
        let result: ShieldOutcome = option.map { $0.isSafe ? ShieldOutcome.safe : ShieldOutcome.blundered } ?? ShieldOutcome.timedOut
        outcome = result
        round.add(result)
        shield = result.isSafe ? shield + 1 : 0
        if let puzzles, shield > puzzles.progress.shieldBest {
            newBest = true
            puzzles.recordShield(shield)
        }
        sounds?.play(result.isSafe ? .move : .capture)
        stage = .revealed
    }

    private func finishRound() {
        clock?.cancel()
        stage = .summary
    }

    // MARK: Positions

    /// Puts the next found position up, or waits for one.
    private func present() {
        guard let next = ready.first else {
            if dry && filler == nil {
                stage = position == nil ? .empty : .summary
            } else {
                stage = .loading
                fill()
            }
            return
        }
        ready.removeFirst()
        show(next)
        fill()
    }

    private func show(_ next: ShieldPosition) {
        guard let start = Position(fen: next.fen),
              let safe = ShieldOption(uci: next.safe, fen: next.fen, isSafe: true),
              let blunder = ShieldOption(uci: next.blunder, fen: next.fen, isSafe: false) else { return }
        position = next
        let model = GameModel(position: start)
        model.humanColors = []
        game = model
        options = Bool.random(using: &generator) ? [safe, blunder] : [blunder, safe]
        picked = nil
        pickedAt = nil
        outcome = nil
        startedAt = Date()
        stage = .choosing
        runClock()
    }

    private func runClock() {
        clock?.cancel()
        let limit = limit
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, !Task.isCancelled, self.stage == .choosing else { return }
            self.reveal(nil)
        }
    }

    /// Finds positions until a couple are waiting, putting one up if the board is waiting.
    private func fill() {
        guard filler == nil, !dry else { return }
        filler = Task { [weak self] in
            await self?.findAhead()
        }
    }

    private func findAhead() async {
        defer { filler = nil }
        while ready.count < Self.lookAhead, !Task.isCancelled {
            guard let found = await find() else {
                dry = true
                break
            }
            ready.append(found)
            if stage == .loading { present() }
        }
        if stage == .loading, ready.isEmpty, !Task.isCancelled {
            filler = nil
            present()
        }
    }

    /// The next position: the player's own mistakes first, then a puzzle the engine checks.
    private func find() async -> ShieldPosition? {
        while let mistake = mistakes.popLast() {
            guard usedMistakes.insert(mistake.id).inserted else { continue }
            if let made = ShieldPosition(mistake: mistake) { return made }
        }
        guard let engine, let library, !library.puzzles.isEmpty else { return nil }
        for _ in 0..<8 {
            let avoid = usedPuzzles.union(puzzles?.progress.recent ?? [])
            guard let puzzle = library.pick(near: rating, theme: .all, avoid: avoid, using: &generator),
                  usedPuzzles.insert(puzzle.id).inserted else { return nil }
            let lines = await engine.analyze(fen: puzzle.fen, depth: 14, lines: 1, maxTimeMs: 600)
            if Task.isCancelled { return nil }
            if let made = ShieldPosition(puzzle: puzzle, engineLine: lines.first) { return made }
        }
        return nil
    }
}
