import ChessKit
import Foundation
import Observation
import UIKit

/// One trip through the analyzer: a picture (maybe), the position being
/// fixed up in the editor, and Stockfish's view of it.
@MainActor
@Observable
final class ScanSession {
    enum Step: Hashable {
        case editor
        case analysis
    }

    var path: [Step] = []
    var draft = PositionDraft.standard
    private(set) var photo: UIImage?
    private(set) var isReading = false
    /// Shown above the editor: what the reader made of the photo, or why it couldn't.
    private(set) var readingNote: String?
    private(set) var readingFailed = false

    private let reader: BoardReader
    private var readTask: Task<Void, Never>?
    /// Which read is current, so one that was replaced can't report into the next.
    private var readID = 0

    init(reader: BoardReader) {
        self.reader = reader
    }

    // MARK: Starting points

    func setUpByHand() {
        reset()
        draft = .standard
        path = [.editor]
    }

    func analyze(fen: String) {
        reset()
        draft = PositionDraft(fen: fen) ?? .standard
        path = [.analysis]
    }

    /// Opens the editor straight away and fills it in once the picture is read.
    func read(_ image: UIImage) {
        reset()
        photo = image
        draft = .empty
        isReading = true
        path = [.editor]
        readID += 1
        let id = readID
        readTask = Task { [weak self, reader] in
            do {
                let reading = try await reader.read(image)
                self?.finishReading(reading, id: id)
            } catch {
                self?.failReading(error, id: id)
            }
        }
    }

    /// For a picture that couldn't even be opened: the editor, with the failure explained.
    func failToLoadPhoto() {
        reset()
        draft = .empty
        readingFailed = true
        readingNote = "I couldn't open that photo. Try another one, or set up the pieces by hand."
        path = [.editor]
    }

    // MARK: Reading

    /// Gives up on a slow read and leaves the editor to fill in by hand, with the photo still there to copy from.
    func stopReading() {
        guard isReading else { return }
        readTask?.cancel()
        readTask = nil
        readID += 1
        isReading = false
        readingFailed = false
        readingNote = "Stopped. Set up the pieces by hand (tap the photo to see it), or go back and pick another."
    }

    private func finishReading(_ reading: BoardReading, id: Int) {
        guard isReading, id == readID else { return }
        isReading = false
        draft = reading.draft
        readingFailed = false
        var notes = ["Check the pieces, fix any that are wrong, then tap Analyze."]
        if !reading.sureOfTurn { notes.append("Set whose turn it is.") }
        if reading.confidence == .low { notes.insert("The picture was hard to read.", at: 0) }
        readingNote = notes.joined(separator: " ")
    }

    private func failReading(_ error: Error, id: Int) {
        guard isReading, id == readID else { return }
        isReading = false
        readingFailed = true
        readingNote = (error as? LocalizedError)?.errorDescription ?? BoardReaderError.failed.errorDescription
    }

    private func reset() {
        readTask?.cancel()
        readTask = nil
        photo = nil
        isReading = false
        readingNote = nil
        readingFailed = false
    }
}

/// Stockfish's verdict on a position, and a board to explore from it: move any piece (or
/// play the engine's best) and the analysis follows; step back and forward through the moves,
/// or play out the whole best line one move at a time.
@MainActor
@Observable
final class AnalysisModel {
    /// One move made on the analysis board.
    struct Step: Equatable, Identifiable {
        let uci: String
        let san: String
        /// The move came from the engine's line rather than the person's finger.
        let fromLine: Bool
        let id: Int
    }

    /// Where the analysis started: the photo, the set-up board or the game.
    let start: PositionDraft
    /// The position on the board now: the start with the moves up to `cursor` played.
    private(set) var draft: PositionDraft
    /// Every move made from the start, including ones stepped back past.
    private(set) var steps: [Step] = []
    /// How many of `steps` are on the board.
    private(set) var cursor = 0
    /// The piece picked up, and where it can go.
    private(set) var selected: Square?
    private(set) var targets: Set<Square> = []
    /// The squares of the last move, for a tint.
    private(set) var lastMove: (from: Square, to: Square)?
    private(set) var lines: [EngineLine] = []
    private(set) var hints: [MoveHint] = []
    private(set) var depth = 0
    private(set) var isThinking = false
    private(set) var failed = false
    /// The best line is playing itself out on the board.
    private(set) var isPlayingLine = false

    private let engine: ChessEngine?
    private let sounds: SoundPlaying?
    /// What Stockfish said about each position already looked at, so stepping back is instant.
    private var cache: [String: (lines: [EngineLine], depth: Int)] = [:]
    /// Counts analyses, so one overtaken by a newer position can't report into it.
    private var generation = 0
    private var analysisTask: Task<Void, Never>?
    private var lineTask: Task<Void, Never>?
    private var nextStepID = 0

    /// How many moves of the best line "Play the line" plays out.
    static let lineLength = 8
    /// The pause between moves while the line plays.
    private let lineBeat: Duration

    init(draft: PositionDraft, engine: ChessEngine?, sounds: SoundPlaying? = nil,
         lineBeat: Duration = .milliseconds(850)) {
        self.start = draft
        self.draft = draft
        self.engine = engine
        self.sounds = sounds
        self.lineBeat = lineBeat
    }

    /// The ending, when the side to move has no moves left.
    var ending: String? {
        guard draft.isFinished else { return nil }
        return draft.isInCheck(draft.sideToMove) ? "Checkmate" : "Stalemate"
    }

    /// The score from White's side, so plus is always good for White.
    var evaluationForWhite: Evaluation? {
        guard let first = lines.first else { return nil }
        return draft.sideToMove == .white ? first.evaluation : first.evaluation.flipped
    }

    var canGoBack: Bool { cursor > 0 }
    /// A move ahead to step to: one already made, or the engine's best.
    var canGoForward: Bool { cursor < steps.count || (ending == nil && lines.first?.firstMove != nil) }
    /// The best line has moves beyond the first to play out.
    var canPlayLine: Bool { ending == nil && (lines.first?.moves.count ?? 0) > 1 }
    /// The moves on the board, as the person reads them.
    var playedSteps: ArraySlice<Step> { steps.prefix(cursor) }

    // MARK: Thinking

    /// Looks quickly, then deeper, updating as each pass finishes.
    func run() async {
        guard ending == nil, lines.isEmpty, !isThinking else { return }
        await analyzeCurrent()
    }

    private func analyzeCurrent() async {
        generation += 1
        let id = generation
        failed = false
        guard ending == nil else {
            isThinking = false
            return
        }
        // Nothing Stockfish can look at: say so instead of thinking forever.
        guard let engine, draft.isValid else {
            isThinking = false
            failed = true
            return
        }
        let fen = draft.fen
        if let known = cache[fen] {
            show(known.lines, depth: known.depth, fen: fen)
            if known.depth >= 18 {
                isThinking = false
                return
            }
        } else {
            lines = []
            hints = []
            depth = 0
        }
        isThinking = true
        for depth in [10, 18] {
            // Capped so the deep pass can't run away on a slow phone.
            let found = await engine.analyze(fen: fen, depth: depth, lines: 2, maxTimeMs: depth == 10 ? 1500 : 8000)
            if Task.isCancelled || id != generation { return }
            guard !found.isEmpty else { continue }
            cache[fen] = (found, depth)
            show(found, depth: depth, fen: fen)
        }
        isThinking = false
        failed = lines.isEmpty
    }

    private func show(_ found: [EngineLine], depth: Int, fen: String) {
        lines = found
        self.depth = depth
        hints = found.prefix(2).enumerated().compactMap { index, line in
            guard
                let uci = line.firstMove,
                let squares = Notation.squares(of: uci),
                let san = Notation.san(of: uci, fen: fen)
            else { return nil }
            return MoveHint(rank: index, from: squares.from, to: squares.to, san: san, uci: uci, evaluation: line.evaluation)
        }
    }

    /// The board changed: look again, a beat later, so stepping quickly doesn't queue searches.
    private func reanalyze() {
        analysisTask?.cancel()
        generation += 1
        let fen = draft.fen
        if let known = cache[fen] {
            show(known.lines, depth: known.depth, fen: fen)
            if known.depth >= 18 {
                isThinking = false
                return
            }
        } else {
            lines = []
            hints = []
            depth = 0
        }
        isThinking = ending == nil
        failed = false
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await self?.analyzeCurrent()
        }
    }

    // MARK: Moving

    /// A tap on the board: picks up a piece of the side to move, or moves the one picked up.
    func tap(_ square: Square) {
        stopLine()
        if let from = selected, targets.contains(square) {
            let promotes = draft[from]?.kind == .pawn && (square.rankIndex == 0 || square.rankIndex == 7)
            play(from.notation + square.notation + (promotes ? "q" : ""), fromLine: false)
            return
        }
        guard let token = draft[square], token.color == draft.sideToMove, square != selected,
              let position = draft.position else {
            selected = nil
            targets = []
            return
        }
        let board = Board(position: position)
        let moves = Set(board.legalMoves(forPieceAt: square))
        selected = moves.isEmpty ? nil : square
        targets = moves
    }

    /// Plays a move from the position on the board. Moves stepped back past give way to it,
    /// unless it is the very move that came next.
    @discardableResult
    func play(_ uci: String, fromLine: Bool) -> Bool {
        if cursor < steps.count, steps[cursor].uci == uci {
            go(to: cursor + 1, sound: true)
            return true
        }
        let fen = draft.fen
        guard let position = Position(fen: fen) else { return false }
        var board = Board(position: position)
        guard let move = TrainingChess.play(uci, on: &board) else { return false }
        steps.removeSubrange(cursor...)
        steps.append(Step(uci: uci, san: move.san, fromLine: fromLine, id: nextStepID))
        nextStepID += 1
        cursor += 1
        land(on: board.position.fen, uci: uci, move: move)
        return true
    }

    /// One move back.
    func back() {
        stopLine()
        guard cursor > 0 else { return }
        go(to: cursor - 1)
    }

    /// One move ahead: the next one made, or else the engine's best.
    func forward() {
        stopLine()
        if cursor < steps.count {
            go(to: cursor + 1, sound: true)
        } else if let best = lines.first?.firstMove {
            play(best, fromLine: true)
        }
    }

    /// Back to where the analysis started.
    func rewind() {
        stopLine()
        go(to: 0)
    }

    /// Jumps to just after the move at `index` (0 the first), or to the start with -1.
    func jump(to index: Int) {
        stopLine()
        go(to: max(0, min(index + 1, steps.count)), sound: true)
    }

    /// Plays the best line out on the board, a move every beat; tapping anything stops it.
    func playLine() {
        guard let line = lines.first, line.moves.count > 0, ending == nil else { return }
        stopLine()
        let moves = Array(line.moves.prefix(Self.lineLength))
        let beat = lineBeat
        isPlayingLine = true
        lineTask = Task { [weak self] in
            for (index, uci) in moves.enumerated() {
                if index > 0 { try? await Task.sleep(for: beat) }
                guard !Task.isCancelled, let self, self.isPlayingLine else { return }
                guard self.play(uci, fromLine: true) else { break }
            }
            guard !Task.isCancelled else { return }
            self?.isPlayingLine = false
        }
    }

    func stopLine() {
        lineTask?.cancel()
        lineTask = nil
        isPlayingLine = false
    }

    private func go(to index: Int, sound: Bool = false) {
        let moves = steps.prefix(index).map(\.uci)
        guard let board = TrainingChess.board(after: moves, from: start.fen) else { return }
        cursor = index
        if sound, let uci = moves.last, var replay = TrainingChess.board(after: Array(moves.dropLast()), from: start.fen),
           let move = TrainingChess.play(uci, on: &replay) {
            land(on: board.position.fen, uci: uci, move: move)
            return
        }
        lastMove = moves.last.flatMap(Notation.squares(of:))
        settle(on: board.position.fen)
    }

    /// A move has landed: the board, its sound, and a fresh look.
    private func land(on fen: String, uci: String, move: Move) {
        lastMove = Notation.squares(of: uci)
        if let sounds {
            if TrainingChess.isCapture(move) {
                sounds.play(.capture)
            } else if TrainingChess.givesCheck(move) {
                sounds.play(.check)
            } else if case .castle = move.result {
                sounds.play(.castle)
            } else {
                sounds.play(.move)
            }
        }
        settle(on: fen)
    }

    private func settle(on fen: String) {
        draft = PositionDraft(fen: fen) ?? draft
        selected = nil
        targets = []
        reanalyze()
    }

    // MARK: Reading

    /// A line in standard notation with move numbers, like "1. Nf3 Nc6 2. d4", numbered from
    /// the position on the board.
    func readable(_ line: EngineLine) -> String {
        let number = TrainingChess.moveNumber(draft.fen)
        return Notation.numbered(Notation.sanLine(of: line.moves, fen: draft.fen), blackFirst: draft.sideToMove == .black,
                                 from: number)
    }

    /// The moves made on the board, numbered from the start: "12. Qxd7+ Kxd7 13. Rd1+".
    var movesMade: [(label: String, index: Int)] {
        var number = TrainingChess.moveNumber(start.fen)
        var white = start.sideToMove == .white
        var made: [(label: String, index: Int)] = []
        for (index, step) in steps.enumerated() {
            let label: String
            if white {
                label = "\(number). \(step.san)"
            } else if index == 0 {
                label = "\(number)... \(step.san)"
            } else {
                label = step.san
            }
            made.append((label, index))
            if !white { number += 1 }
            white.toggle()
        }
        return made
    }

    /// Who is better and by how much, in plain words.
    func verdict(white: String, black: String) -> String {
        guard let evaluation = evaluationForWhite else { return "" }
        switch evaluation {
        case .mate(let moves):
            if moves == 0 { return "Checkmate" }
            let side = moves > 0 ? white : black
            return "\(side) mates in \(abs(moves))"
        case .centipawns(let cp):
            let side = cp > 0 ? white : black
            switch abs(cp) {
            case ..<30: return "About equal"
            case ..<100: return "\(side) is slightly better"
            case ..<300: return "\(side) is better"
            default: return "\(side) is winning"
            }
        }
    }
}
