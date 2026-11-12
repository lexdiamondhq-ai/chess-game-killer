import ChessKit
import Foundation
import Observation
import UIKit

/// One trip through the analyzer: a picture (maybe), the position being
/// fixed up in the editor, and Stockfish's view of it.
///
/// A photo goes straight from being read to its analysis, with no stop in the editor
/// (Alex, 2026-11-06: "Skip the board read and adding pieces and go straight to analyze").
/// The analysis can open the editor to fix a piece, and the editor's Analyze comes back.
///
/// The app keeps one session, so closing Analyze and opening it again finds the same board,
/// with the moves played on it (Alex, 2026-11-08: "my previous game should be on there still").
@MainActor
@Observable
final class ScanSession {
    enum Step: Hashable {
        /// The photo, while the reader checks every square.
        case reading
        case editor
        case analysis
    }

    var path: [Step] = []
    /// The position in the editor.
    var draft = PositionDraft.standard
    /// The position the analysis looks at. A new analysis starts each time `analysisRun` changes.
    private(set) var analyzed = PositionDraft.standard
    private(set) var analysisRun = 0
    /// The analysis board for `analyzed`, kept here so it outlives the sheet.
    private(set) var analysis: AnalysisModel?
    private(set) var photo: UIImage?
    private(set) var isReading = false
    /// Shown above the editor: what the reader made of the photo, or why it couldn't.
    private(set) var readingNote: String?
    private(set) var readingFailed = false
    /// Shown with the photo's analysis when the reader wasn't sure of something: what to check.
    private(set) var photoDoubts: String?
    /// The part of `photoDoubts` about the pieces, which still stands once the turn is settled.
    private var piecesDoubt: String?

    private let reader: BoardReader
    private let engine: ChessEngine?
    private let sounds: SoundPlaying?
    private var readTask: Task<Void, Never>?
    /// Which read is current, so one that was replaced can't report into the next.
    private var readID = 0

    init(reader: BoardReader, engine: ChessEngine? = nil, sounds: SoundPlaying? = nil) {
        self.reader = reader
        self.engine = engine
        self.sounds = sounds
    }

    /// When the line to the reader was last opened, so it isn't knocked on again and again.
    private var lastWarmUp: Date?

    /// Gets the reader ready while the person picks or takes a photo.
    func warmUpReader(now: Date = .now) {
        if let lastWarmUp, now.timeIntervalSince(lastWarmUp) < 20 { return }
        lastWarmUp = now
        reader.warmUp()
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
        startAnalysis(of: draft)
        path = [.analysis]
    }

    /// Shows the picture while it's read, then its analysis. A read that fails, or finds pieces
    /// that can't be analyzed yet, opens the editor instead, with the photo there to copy from.
    ///
    /// `answered` runs once the reader has looked at the picture (a position, or no board in it):
    /// that is when a scan is counted. A read lost to the connection or a busy server never
    /// reaches it, so it doesn't cost one of a free player's few scans (audit, 2026-11-12).
    func read(_ image: UIImage, answered: (@MainActor () -> Void)? = nil) {
        reset()
        photo = image
        draft = .empty
        isReading = true
        path = [.reading]
        readID += 1
        let id = readID
        readTask = Task { [weak self, reader] in
            do {
                let reading = try await reader.read(image)
                answered?()
                self?.finishReading(reading, id: id)
            } catch {
                if (error as? BoardReaderError) == .noBoard { answered?() }
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

    // MARK: Editing and analyzing

    /// From the analysis: its board's pieces in the editor, to fix and analyze again.
    func editPieces(_ position: PositionDraft) {
        draft = position
        readingFailed = false
        readingNote = photo == nil ? nil : "Fix any piece I got wrong, then tap Analyze."
        path.append(.editor)
    }

    /// The editor's Analyze: the position as it is now. An editor opened from an analysis
    /// goes back to it, which starts over on the new position; otherwise the analysis opens.
    func analyzeDraft() {
        startAnalysis(of: draft)
        // The person has looked the pieces over.
        photoDoubts = nil
        piecesDoubt = nil
        if Array(path.suffix(2)) == [.analysis, .editor] {
            path.removeLast()
        } else {
            path.append(.analysis)
        }
    }

    /// From the analysis: the same pieces with the other side to move, analyzed from the start.
    /// The reader's guess at whose move it was has been answered.
    func switchTurn(of position: PositionDraft) {
        var switched = position
        switched.sideToMove = switched.sideToMove == .white ? .black : .white
        draft = switched
        photoDoubts = piecesDoubt
        startAnalysis(of: switched)
    }

    private func startAnalysis(of position: PositionDraft) {
        analyzed = position
        analysisRun += 1
        analysis = AnalysisModel(draft: position, engine: engine, sounds: sounds)
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
        if path.last == .reading { path = [.editor] }
    }

    /// Leaving the photo while it's read, back to the start: the read is dropped.
    func leaveReading() {
        guard isReading else { return }
        readTask?.cancel()
        readTask = nil
        readID += 1
        isReading = false
        // Analyze closed mid-read: it opens on its first screen next time, not a stalled read.
        if path.last == .reading { path.removeLast() }
    }

    private func finishReading(_ reading: BoardReading, id: Int) {
        guard isReading, id == readID else { return }
        isReading = false
        draft = reading.draft
        readingFailed = false
        let hardToRead = reading.confidence == .low ? "The picture was hard to read, so check the pieces." : nil
        guard reading.draft.isValid else {
            // What's wrong shows under the editor's board.
            readingNote = [hardToRead, "Fix what's marked below, then tap Analyze."].compactMap { $0 }.joined(separator: " ")
            if path.last == .reading { path = [.editor] }
            return
        }
        let side = reading.draft.sideToMove == .white ? "White" : "Black"
        let turn = reading.sureOfTurn ? nil : "I guessed it's \(side)'s move."
        piecesDoubt = hardToRead
        let doubts = [hardToRead, turn].compactMap { $0 }
        photoDoubts = doubts.isEmpty ? nil : doubts.joined(separator: " ")
        startAnalysis(of: reading.draft)
        if path.last == .reading { path = [.analysis] }
    }

    private func failReading(_ error: Error, id: Int) {
        guard isReading, id == readID else { return }
        isReading = false
        readingFailed = true
        readingNote = (error as? LocalizedError)?.errorDescription ?? BoardReaderError.failed.errorDescription
        if path.last == .reading { path = [.editor] }
    }

    private func reset() {
        readTask?.cancel()
        readTask = nil
        photo = nil
        isReading = false
        readingNote = nil
        readingFailed = false
        photoDoubts = nil
        piecesDoubt = nil
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
    /// The person tapped one of their pieces that can't move because their king is in check:
    /// the board says so under it (Alex, 2026-11-11: "You can't move any other pieces").
    private(set) var showsCheckNote = false
    /// The squares of the last move, for a tint.
    private(set) var lastMove: (from: Square, to: Square)?
    /// A pawn moved to the last rank by the person, waiting for them to choose its piece.
    private(set) var promoting: (from: Square, to: Square, color: Piece.Color)?
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

    /// The king of the side to move, while it is in check, for a red glow under it.
    var kingInCheck: Square? {
        let color = draft.sideToMove
        guard draft.isInCheck(color) else { return nil }
        return draft.pieces.first { $0.kind == .king && $0.color == color }?.square
    }

    /// Neither side has enough left to checkmate: kings alone, or a king and one bishop or
    /// knight against a bare king. The game is a draw.
    var isDeadDraw: Bool {
        let others = draft.pieces.filter { $0.kind != .king }
        return others.isEmpty || (others.count == 1 && [.bishop, .knight].contains(others[0].kind))
    }

    /// What happened, for the line under the board: checkmate, stalemate, a dead draw, or check
    /// (Alex, 2026-11-11: "It also needs to say what happened on the bottom").
    var statusNote: String? {
        let mover = draft.sideToMove == .white ? "White" : "Black"
        let winner = draft.sideToMove == .white ? "Black" : "White"
        if ending == "Checkmate" { return "Checkmate. \(winner) wins." }
        if ending == "Stalemate" { return "Stalemate. \(mover) has no moves, so it's a draw." }
        if isDeadDraw { return "Draw. Nobody has enough pieces left to checkmate." }
        // The piece tapped has no way to end the check; another piece (or the king) may.
        if showsCheckNote { return "Your king is in check. This piece can't save it." }
        if kingInCheck != nil { return "Check! \(mover)'s king is under attack." }
        return nil
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
    /// Opened again (Analyze closed and reopened), it carries on from what it had found.
    func run() async {
        guard ending == nil, lines.isEmpty || depth < Self.fullDepth else { return }
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
            if known.depth >= Self.fullDepth {
                isThinking = false
                return
            }
        } else {
            lines = []
            hints = []
            depth = 0
        }
        isThinking = true
        // One search that reports as it deepens: the arrows show as soon as the first depths are
        // in, a fraction of a second, and firm up as it looks further. Capped so it can't run
        // away on a slow phone, and so it settles quickly (Alex, 2026-11-11: was 6 s).
        let found = await engine.analyze(fen: fen, depth: Self.fullDepth, lines: 2, maxTimeMs: Self.maxThinkMs) { [weak self] found, depth in
            Task { @MainActor in self?.progress(found, depth: depth, fen: fen, id: id) }
        }
        guard id == generation else { return }
        // The sheet closed mid-search: stop, so opening it again can look afresh.
        if Task.isCancelled {
            isThinking = false
            return
        }
        if !found.isEmpty {
            cache[fen] = (found, Self.fullDepth)
            show(found, depth: Self.fullDepth, fen: fen)
        }
        isThinking = false
        failed = lines.isEmpty
    }

    /// How deep the analysis looks before it counts as done.
    static let fullDepth = 18

    /// The longest one position is thought about. The best move rarely changes after this.
    static let maxThinkMs = 3000

    /// The first depth worth showing: shallower, the best move still jumps about.
    static let firstDepth = 8

    /// The lines so far, while the search is still deepening. Too shallow, shallower than shown
    /// already, or for a position since left, they are dropped.
    private func progress(_ found: [EngineLine], depth: Int, fen: String, id: Int) {
        guard id == generation, isThinking, depth >= Self.firstDepth, depth > self.depth, depth < Self.fullDepth,
              !found.isEmpty,
              cache[fen].map({ $0.depth < depth }) ?? true else { return }
        cache[fen] = (found, depth)
        show(found, depth: depth, fen: fen)
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
            if known.depth >= Self.fullDepth {
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
        promoting = nil
        showsCheckNote = false
        if let from = selected, targets.contains(square) {
            if draft[from]?.kind == .pawn, square.rankIndex == 0 || square.rankIndex == 7 {
                // The person chooses what the pawn becomes; the picker shows over the board.
                promoting = (from, square, draft.sideToMove)
                selected = nil
                targets = []
                return
            }
            play(from.notation + square.notation, fromLine: false)
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
        // A piece stuck because the king is in check: say why, instead of doing nothing.
        showsCheckNote = moves.isEmpty && kingInCheck != nil
    }

    /// Finishes the person's promotion with the piece they chose.
    func promote(to kind: Piece.Kind) {
        guard let promotion = promoting else { return }
        promoting = nil
        play(promotion.from.notation + promotion.to.notation + kind.rawValue.lowercased(), fromLine: false)
    }

    /// A change of mind: the pawn stays where it was.
    func cancelPromotion() {
        promoting = nil
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
        promoting = nil
        selected = nil
        targets = []
        showsCheckNote = false
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
