import ChessKit
import Foundation
import Observation

/// How deep Rewind goes when it shows what could have been.
enum ReviewLevel: String, CaseIterable, Identifiable {
    case coach, club, grandmaster

    var id: Self { self }

    var title: String {
        switch self {
        case .coach: return "Coach"
        case .club: return "Club"
        case .grandmaster: return "Grandmaster"
        }
    }

    var blurb: String {
        switch self {
        case .coach: return "A few moves ahead, in plain words."
        case .club: return "Six moves ahead, with their best tries."
        case .grandmaster: return "Ten moves deep, every branch, with the numbers."
        }
    }

    /// Moves (both sides) the line runs to.
    var depth: Int {
        switch self {
        case .coach: return 4
        case .club: return 6
        case .grandmaster: return 10
        }
    }

    /// Other moves shown at a step, besides the line's own.
    var branches: Int {
        switch self {
        case .coach: return 0
        case .club: return 2
        case .grandmaster: return 3
        }
    }

    var showsNumbers: Bool { self == .grandmaster }

    /// Club shows the opponent's tries only; Grandmaster shows both sides'.
    func showsBranches(playerToMove: Bool) -> Bool {
        switch self {
        case .coach: return false
        case .club: return !playerToMove
        case .grandmaster: return true
        }
    }

    static let storageKey = "rewind.level"
}

/// One move of a line being explored.
struct LineStep: Equatable, Identifiable {
    let index: Int
    let uci: String
    let san: String
    let fenBefore: String
    let fenAfter: String
    let byWhite: Bool

    var id: Int { index }

    /// "6. Nxf7" or "6... Kxf7".
    var numbered: String {
        let number = TrainingChess.moveNumber(fenBefore)
        return byWhite ? "\(number). \(san)" : "\(number)... \(san)"
    }
}

/// Another move at a step of the line, with where the engine thinks it leads.
struct LineBranch: Equatable, Identifiable {
    let moves: [String]
    let san: String
    /// The player's winning chances after it, -1 to 1.
    let forPlayer: Double
    let evaluation: Evaluation
    let note: String

    var id: String { moves.first ?? san }
}

/// The better line from a moment of a game, to walk through move by move:
/// step to any move, try the other side's best answers, or play your own
/// move and let Stockfish answer.
@MainActor
@Observable
final class LineExplorer {
    let root: String
    let player: Piece.Color
    private(set) var level: ReviewLevel
    private(set) var steps: [LineStep] = []
    /// How many of the steps are on the board. 0 is the moment itself.
    private(set) var cursor = 0
    /// Other moves from the position on the board, best first.
    private(set) var branches: [LineBranch] = []
    /// The position on the board, from the player's side.
    private(set) var evaluation: Evaluation?
    private(set) var isThinking = false
    /// A square picked to move from, when the player tries a move of their own.
    private(set) var selected: Square?
    /// Set when the player has left the engine's line with a move of their own.
    private(set) var ownMoveAt: Int?

    @ObservationIgnored private let engine: ChessEngine?
    @ObservationIgnored private var cache: [String: [EngineLine]] = [:]
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(root: String, line: [String], player: Piece.Color, level: ReviewLevel, engine: ChessEngine?) {
        self.root = root
        self.player = player
        self.level = level
        self.engine = engine
        steps = Self.steps(for: line, from: root, startingAt: 0, limit: level.depth)
    }

    // MARK: Reading

    var fen: String { cursor == 0 ? root : steps[cursor - 1].fenAfter }
    var current: LineStep? { cursor > 0 ? steps[cursor - 1] : nil }
    var next: LineStep? { cursor < steps.count ? steps[cursor] : nil }
    var atEnd: Bool { cursor >= steps.count }

    var playerToMove: Bool { TrainingChess.sideToMove(fen) == player }

    /// Squares where a piece of the line has moved to, for drawing them as ghosts.
    var ghostSquares: Set<Square> {
        var squares: Set<Square> = []
        for step in steps.prefix(cursor) {
            guard let move = Notation.squares(of: step.uci) else { continue }
            squares.remove(move.from)
            squares.insert(move.to)
        }
        return squares
    }

    /// What Leo says about the move just shown.
    var sentence: String {
        guard let current else {
            return next.map { "Watch \(LineNarrator.owner($0.byWhite, player: player)) \($0.san)." } ?? ""
        }
        return LineNarrator.describe(current, player: player)
    }

    // MARK: Moving through it

    func go(to cursor: Int) {
        let target = max(0, min(steps.count, cursor))
        guard target != self.cursor else { return }
        self.cursor = target
        selected = nil
        refresh()
    }

    func stepForward() { go(to: cursor + 1) }
    func stepBack() { go(to: cursor - 1) }

    func setLevel(_ level: ReviewLevel) {
        guard level != self.level else { return }
        self.level = level
        if steps.count > level.depth, ownMoveAt == nil {
            steps = Array(steps.prefix(level.depth))
            cursor = min(cursor, steps.count)
        }
        refresh()
    }

    /// Follows another move from here: the line becomes that move and what the engine expects after it.
    func follow(_ branch: LineBranch) {
        let kept = Array(steps.prefix(cursor))
        steps = kept + Self.steps(for: branch.moves, from: fen, startingAt: cursor, limit: level.depth - cursor)
        cursor = min(steps.count, cursor + 1)
        selected = nil
        refresh()
    }

    /// A tap on the board: pick a piece of the side to move, then where it goes.
    func tap(_ square: Square) {
        guard let position = Position(fen: fen) else { return }
        let piece = position.piece(at: square)
        if let from = selected {
            if from == square { selected = nil; return }
            if piece?.color == position.sideToMove { selected = square; return }
            let uci = from.notation + square.notation + (Self.isPromotion(from: from, to: square, in: position) ? "q" : "")
            selected = nil
            play(uci)
        } else if piece?.color == position.sideToMove {
            selected = square
        }
    }

    /// Plays a move of the player's own from the position on the board; the engine carries on from there.
    func play(_ uci: String) {
        let made = Self.steps(for: [uci], from: fen, startingAt: cursor, limit: 1)
        guard let step = made.first else { return }
        steps = Array(steps.prefix(cursor)) + [step]
        ownMoveAt = cursor
        cursor += 1
        branches = []
        refresh()
    }

    func cancel() {
        work?.cancel()
        generation += 1
        isThinking = false
    }

    // MARK: The engine

    /// Looks again at the position on the board: its score and the other moves from it.
    /// Then runs the line on to the level's depth, so there is always more to see.
    func refresh() {
        cancel()
        let gen = generation
        let fen = self.fen
        let wanted = level.branches
        let showsBranches = level.showsBranches(playerToMove: playerToMove)
        guard let engine else {
            branches = []
            return
        }
        isThinking = true
        work = Task { [weak self] in
            let lines = await self?.lines(for: fen, count: max(1, wanted + 1), engine: engine) ?? []
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            if let top = lines.first {
                let mover = TrainingChess.sideToMove(fen) ?? .white
                self.evaluation = mover == self.player ? top.evaluation : top.evaluation.flipped
            }
            let found = showsBranches ? lines.compactMap { self.branch(from: $0, at: fen) } : []
            self.branches = Array(found.filter { $0.moves.first != self.next?.uci }.prefix(wanted))
            await self.fillToDepth(generation: gen, engine: engine)
            guard !Task.isCancelled, gen == self.generation else { return }
            // The line may have grown into the move a branch named.
            self.branches = Array(found.filter { $0.moves.first != self.next?.uci }.prefix(wanted))
            self.isThinking = false
        }
    }

    private func fillToDepth(generation gen: Int, engine: ChessEngine) async {
        while steps.count < level.depth {
            let from = steps.last?.fenAfter ?? root
            let answer = await self.lines(for: from, count: 1, engine: engine)
            guard !Task.isCancelled, gen == generation, let top = answer.first else { return }
            let before = steps.count
            append(top.moves)
            if steps.count == before { return }
        }
    }

    private func append(_ moves: [String]) {
        let from = steps.last?.fenAfter ?? root
        steps += Self.steps(for: moves, from: from, startingAt: steps.count, limit: level.depth - steps.count)
    }

    private func lines(for fen: String, count: Int, engine: ChessEngine) async -> [EngineLine] {
        if let cached = cache[fen], cached.count >= count { return cached }
        let lines = await engine.analyze(fen: fen, depth: 14, lines: count, maxTimeMs: 1200)
        cache[fen] = lines
        return lines
    }

    private func branch(from line: EngineLine, at fen: String) -> LineBranch? {
        guard let first = line.firstMove, let san = Notation.san(of: first, fen: fen) else { return nil }
        let mover = TrainingChess.sideToMove(fen) ?? .white
        let forPlayer = mover == player ? line.evaluation.winningChances : -line.evaluation.winningChances
        return LineBranch(moves: line.moves, san: san, forPlayer: forPlayer,
                          evaluation: mover == player ? line.evaluation : line.evaluation.flipped,
                          note: LineNarrator.outlook(forPlayer))
    }

    // MARK: Building lines

    /// Moves played out from a position, stopping at the first that doesn't fit.
    static func steps(for moves: [String], from fen: String, startingAt index: Int, limit: Int) -> [LineStep] {
        var result: [LineStep] = []
        var position = fen
        for uci in moves.prefix(max(0, limit)) {
            guard
                let san = Notation.san(of: uci, fen: position),
                let next = TrainingChess.fen(after: [uci], from: position),
                let side = TrainingChess.sideToMove(position)
            else { break }
            result.append(LineStep(index: index + result.count, uci: uci, san: san, fenBefore: position,
                                   fenAfter: next, byWhite: side == .white))
            position = next
        }
        return result
    }

    private static func isPromotion(from: Square, to: Square, in position: Position) -> Bool {
        guard let piece = position.piece(at: from), piece.kind == .pawn else { return false }
        return (piece.color == .white && to.rankIndex == 7) || (piece.color == .black && to.rankIndex == 0)
    }
}

/// Plain words for a move in a line: what it takes, what it hits, whether it checks.
/// Built from the board alone, so it never claims more than the position shows.
enum LineNarrator {
    static func owner(_ byWhite: Bool, player: Piece.Color) -> String {
        (byWhite ? Piece.Color.white : .black) == player ? "your" : "their"
    }

    static func describe(_ step: LineStep, player: Piece.Color) -> String {
        guard
            let move = Notation.squares(of: step.uci),
            let before = BoardGeometry(fen: step.fenBefore),
            let after = BoardGeometry(fen: step.fenAfter),
            let mover = before.piece(at: move.from)
        else { return step.san }
        let whose = owner(step.byWhite, player: player)
        let theirs = whose == "your" ? "their" : "your"
        let piece = BoardGeometry.name(mover.kind)
        let subject = "\(whose.capitalized) \(piece)"

        if step.san.hasSuffix("#") {
            return "\(step.san). Checkmate."
        }
        if step.san.hasPrefix("O-O") {
            return "\(step.san): \(whose) king castles to safety."
        }
        var parts: [String] = []
        if let victim = before.piece(at: move.to), victim.color != mover.color {
            parts.append("takes \(theirs) \(BoardGeometry.name(victim.kind))")
        } else if mover.kind == .pawn, move.from.fileIndex != move.to.fileIndex {
            parts.append("takes a pawn en passant")
        } else {
            parts.append("goes to \(move.to.notation)")
        }
        if step.uci.count == 5 {
            parts.append("and becomes a queen")
        }
        let targets = after.forkTargets(from: move.to)
            .compactMap { after.piece(at: $0) }
            .filter { $0.kind != .king && $0.color != mover.color }
            .sorted { BoardGeometry.value($0.kind) > BoardGeometry.value($1.kind) }
            .map { BoardGeometry.name($0.kind) }
        let check = step.san.contains("+")
        if targets.count >= 2 {
            parts.append("\(check ? "with check, " : "")and hits the \(BoardGeometry.list(Array(targets.prefix(2)))) at once")
        } else if check {
            parts.append(targets.isEmpty ? "with check" : "with check, and the \(targets[0]) is attacked too")
        } else if let target = targets.first {
            parts.append("and attacks the \(target)")
        }
        var text = "\(step.san): \(subject) " + parts.joined(separator: " ") + "."
        if after.isHanging(move.to), mover.kind != .king {
            text += " It can be taken."
        }
        return text
    }

    /// Where a line leaves the player, in words.
    static func outlook(_ forPlayer: Double) -> String {
        switch forPlayer {
        case 0.6...: return "you're winning"
        case 0.25..<0.6: return "you're better"
        case -0.25..<0.25: return "about even"
        case -0.6 ..< -0.25: return "they're better"
        default: return "they're winning"
        }
    }
}
