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

/// Stockfish's verdict on one position: the two best moves and how they go on.
@MainActor
@Observable
final class AnalysisModel {
    let draft: PositionDraft
    private(set) var lines: [EngineLine] = []
    private(set) var hints: [MoveHint] = []
    private(set) var depth = 0
    private(set) var isThinking = false
    private(set) var failed = false

    private let engine: ChessEngine?

    init(draft: PositionDraft, engine: ChessEngine?) {
        self.draft = draft
        self.engine = engine
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

    /// Looks quickly, then deeper, updating as each pass finishes.
    func run() async {
        guard ending == nil, lines.isEmpty, !isThinking else { return }
        // Nothing Stockfish can look at: say so instead of thinking forever.
        guard let engine, draft.isValid else {
            failed = true
            return
        }
        let fen = draft.fen
        isThinking = true
        for depth in [10, 18] {
            // Capped so the deep pass can't run away on a slow phone.
            let found = await engine.analyze(fen: fen, depth: depth, lines: 2, maxTimeMs: depth == 10 ? 1500 : 8000)
            if Task.isCancelled { break }
            guard !found.isEmpty else { continue }
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
        isThinking = false
        failed = lines.isEmpty && !Task.isCancelled
    }

    /// A line in standard notation with move numbers, like "1. Nf3 Nc6 2. d4".
    func readable(_ line: EngineLine) -> String {
        Notation.numbered(Notation.sanLine(of: line.moves, fen: draft.fen), blackFirst: draft.sideToMove == .black)
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
