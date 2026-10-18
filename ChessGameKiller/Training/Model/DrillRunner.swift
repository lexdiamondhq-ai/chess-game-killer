import ChessKit
import Foundation
import Observation

/// Runs one practice item: shows the position (and the opponent's move that
/// sets it up), takes the learner's answer, and grades it kindly.
@MainActor
@Observable
final class DrillRunner {
    enum Phase: Equatable {
        /// Showing the position before it's the learner's turn.
        case intro
        case solving
        /// The opponent is replying, or the engine is checking a move.
        case waiting
        /// A playout that ran out of moves or ended in a draw: try again or move on.
        case stuck
        case done(Outcome)
    }

    enum Tone: Equatable {
        case coach, success, wrong, hint
    }

    let item: SessionItem
    let kind: Drill.Kind
    /// The learner's side, at the bottom of the board.
    let learner: Piece.Color
    private(set) var game: GameModel
    private(set) var phase: Phase = .intro
    private(set) var message: String
    private(set) var tone: Tone = .coach
    private(set) var arrows: [BoardArrow] = []
    private(set) var marks: [SquareMark] = []
    private(set) var labels: [SquareLabel] = []
    private(set) var usedHint = false
    private(set) var mistakes = 0
    /// Choice answers tried so far.
    private(set) var tried: Set<Int> = []
    /// Moves made in a playout.
    private(set) var movesMade = 0

    let prompt: String
    let options: [ChoiceOption]
    /// The two answers of a yes-or-no drill, like "Safe" and "Not safe".
    let answerLabels: (yes: String, no: String)
    let moveLimit: Int

    private let startFEN: String
    private let setup: String?
    private let solution: [String]
    private let alternatives: [[String]]
    private let squares: [String]
    private let candidate: String?
    private let expectedAnswer: Bool?
    private let reply: String?
    private let explain: String?
    private let lines: CoachLines?
    private let engine: ChessEngine?
    private let sounds: SoundPlaying?
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var found: Set<String> = []
    @ObservationIgnored private var pending: Task<Void, Never>?

    init?(item: SessionItem, library: TrainingLibrary?, engine: ChessEngine?, playsSounds: Bool = true) {
        let fen: String
        let setupMove: String?
        switch item.content {
        case .drill(let drill):
            let skill = library?.skill(drill.skill)
            fen = drill.fen
            kind = drill.type
            setupMove = drill.setup
            solution = drill.solution ?? []
            alternatives = drill.alts ?? []
            squares = drill.squares ?? []
            candidate = drill.move
            expectedAnswer = drill.answer
            reply = drill.reply
            explain = drill.explain
            options = drill.options ?? []
            answerLabels = (skill?.yes ?? "Safe", skill?.no ?? "Not safe")
            moveLimit = drill.limit ?? max(1, (drill.mate ?? 6) + 6)
            prompt = Self.prompt(for: drill, skill: skill, role: item.role)
        case .mistake(let mistake):
            let played = Notation.san(of: mistake.played, fen: mistake.fen) ?? mistake.played
            fen = mistake.fen
            kind = .move
            setupMove = nil
            solution = [mistake.best]
            alternatives = []
            squares = []
            candidate = nil
            expectedAnswer = nil
            reply = nil
            explain = nil
            options = []
            answerLabels = ("Yes", "No")
            moveLimit = 1
            prompt = "From your game. You played \(played) here. Find a better move."
        }
        guard let position = Position(fen: fen) else { return nil }

        self.item = item
        self.engine = engine
        sounds = playsSounds ? (SoundPlayer.shared as SoundPlaying) : nil
        lines = library?.course.lines
        startFEN = position.fen
        setup = setupMove
        learner = setupMove == nil ? position.sideToMove : position.sideToMove.opposite
        message = prompt
        let model = GameModel(position: position)
        model.humanColors = []
        game = model
    }

    private static func prompt(for drill: Drill, skill: Skill?, role: SessionItem.Role) -> String {
        if let prompt = drill.prompt { return prompt }
        // Mixed items don't say which pattern to look for, like a real game.
        if role == .mixed, drill.type == .move { return "Your move. What's the best move here?" }
        if let mate = drill.mate, drill.type == .move {
            return mate == 1 ? "Checkmate in one move." : "Checkmate in \(mate) moves."
        }
        var text = skill?.prompt ?? "Find the best move."
        if drill.type == .playout {
            text = text.replacingOccurrences(of: "{limit}", with: "\(drill.limit ?? 10)")
        }
        return text
    }

    var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    var outcome: Outcome? {
        if case .done(let outcome) = phase { return outcome }
        return nil
    }

    /// Whether the board takes taps right now.
    var acceptsTaps: Bool {
        phase == .solving && (kind == .move || kind == .tap || kind == .playout)
    }

    // MARK: Starting

    func begin() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            if let setup = self.setup {
                self.playMove(setup)
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            self.startSolving()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func startSolving() {
        phase = .solving
        switch kind {
        case .move, .playout:
            game.humanColors = [learner]
        case .safe:
            if let candidate, let squares = Notation.squares(of: candidate) {
                arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .blue, dashed: true)]
                let san = Notation.san(of: candidate, fen: game.fen) ?? candidate
                message = prompt.replacingOccurrences(of: "{move}", with: san)
            }
        case .tap, .choice:
            break
        }
    }

    // MARK: Answers

    func tap(_ square: Square) {
        guard phase == .solving else { return }
        switch kind {
        case .move, .playout:
            tapToMove(square)
        case .tap:
            tapToFind(square)
        case .safe, .choice:
            break
        }
    }

    /// The answer to a yes-or-no drill.
    func answer(_ yes: Bool) {
        guard phase == .solving, kind == .safe, let expectedAnswer else { return }
        let right = yes == expectedAnswer
        tone = right ? .success : .wrong
        let opener = right ? pick(lines?.correct, or: "Exactly.") : "Not this time."
        message = [opener, explain].compactMap { $0 }.joined(separator: " ")
        phase = .waiting
        // Show what happens: the move, then their reply if it punishes it.
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            if let candidate = self.candidate {
                self.arrows = []
                self.playMove(candidate)
            }
            if let reply = self.reply {
                try? await Task.sleep(for: .milliseconds(750))
                if let squares = Notation.squares(of: reply) {
                    self.arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .red, dashed: nil)]
                }
                try? await Task.sleep(for: .milliseconds(350))
                self.playMove(reply)
            }
            self.phase = .done(right ? .firstTry : .missed)
        }
    }

    func choose(_ index: Int) {
        guard phase == .solving, kind == .choice, options.indices.contains(index), !tried.contains(index) else { return }
        tried.insert(index)
        let option = options[index]
        if let move = option.move, let squares = Notation.squares(of: move) {
            arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation,
                                 color: option.correct ? .green : .red, dashed: nil)]
        }
        if option.correct {
            tone = .success
            message = option.why ?? pick(lines?.correct, or: "Exactly.")
            phase = .done(mistakes == 0 ? .firstTry : .afterMistake)
        } else {
            mistakes += 1
            tone = .wrong
            message = option.why ?? pick(lines?.wrong, or: "Not that one. Try another.")
        }
    }

    func hint() {
        guard phase == .solving else { return }
        usedHint = true
        tone = .hint
        switch kind {
        case .move:
            guard solution.indices.contains(index), let squares = Notation.squares(of: solution[index]),
                  let piece = game.piece(at: squares.from) else { return }
            marks = [SquareMark(square: squares.from.notation, color: .yellow)]
            message = "Try your \(BoardGeometry.name(piece.kind)) on \(squares.from.notation)."
        case .tap:
            if let setup, let squares = Notation.squares(of: setup) {
                marks = [SquareMark(square: squares.to.notation, color: .yellow)]
                message = "Look at every square the piece on \(squares.to.notation) can reach."
            }
        case .safe:
            if let candidate, let squares = Notation.squares(of: candidate) {
                marks = [SquareMark(square: squares.to.notation, color: .yellow)]
                message = "Count on \(squares.to.notation): what of theirs can capture there, and what of yours defends it?"
            }
        case .choice:
            message = "Think about which move follows the rules from the lesson."
        case .playout:
            message = "Shrink the box: take squares away from their king, and bring your king closer. Don't check for the sake of it."
        }
    }

    /// Gives up and shows the answer.
    func reveal() {
        guard phase == .solving || phase == .stuck else { return }
        switch kind {
        case .move:
            showLine()
        case .tap:
            marks = squares.map { SquareMark(square: $0, color: .green) }
            if let setup, let from = Notation.squares(of: setup)?.to {
                arrows = squares.map { BoardArrow(from: from.notation, to: $0, color: .red, dashed: nil) }
            }
            tone = .hint
            message = explain ?? "These were the pieces under attack."
            phase = .done(.missed)
        case .choice:
            if let index = options.firstIndex(where: \.correct) {
                let option = options[index]
                if let move = option.move, let squares = Notation.squares(of: move) {
                    arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: nil)]
                }
                tone = .hint
                message = option.why ?? "This was the one."
            }
            phase = .done(.missed)
        case .safe, .playout:
            phase = .done(.missed)
        }
    }

    /// Starts a playout over from its first position.
    func restart() {
        guard kind == .playout, let position = Position(fen: startFEN) else { return }
        pending?.cancel()
        game = GameModel(position: position)
        game.humanColors = []
        movesMade = 0
        arrows = []
        marks = []
        tone = .coach
        message = prompt
        begin()
    }

    // MARK: Moves

    private func tapToMove(_ square: Square) {
        let movesBefore = game.moveCount
        let selectedBefore = game.selected
        game.tap(square)
        if game.pendingPromotion != nil {
            let expected = solution.indices.contains(index) ? solution[index] : nil
            game.promote(to: expected.flatMap(TrainingChess.promotionKind(of:)) ?? .queen)
        }
        if game.moveCount != movesBefore, let played = game.lastPlayed {
            sound(for: played)
            marks = []
            if kind == .playout {
                playoutMoved()
            } else {
                judge(played)
            }
        } else if game.selected != nil, game.selected != selectedBefore {
            sounds?.play(.select)
        }
    }

    private func judge(_ played: PlayedMove) {
        let uci = played.uci
        let expected = solution.indices.contains(index) ? solution[index] : nil
        let others = alternatives.indices.contains(index / 2) ? alternatives[index / 2] : []
        let mated = game.winner == learner

        if mated || (uci == expected && index + 1 >= solution.count) {
            solved()
        } else if uci == expected {
            let reply = solution[index + 1]
            index += 2
            phase = .waiting
            game.humanColors = []
            tone = .success
            message = pick(lines?.keepGoing, or: "Good. Keep going.")
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard let self, !Task.isCancelled else { return }
                self.playMove(reply)
                if self.index >= self.solution.count {
                    self.solved()
                } else {
                    self.phase = .solving
                    self.game.humanColors = [self.learner]
                }
            }
        } else if others.contains(uci) {
            solved(note: "That works too!")
        } else if case .mistake = item.content, engine != nil {
            // Games have more than one good move. Ask the engine before saying no.
            phase = .waiting
            game.humanColors = []
            let fen = played.fenBefore
            pending = Task { [weak self] in
                guard let self else { return }
                let fine = await self.isAlmostAsGood(uci, fen: fen)
                guard !Task.isCancelled else { return }
                if fine {
                    self.solved(note: "That works too!")
                } else {
                    self.wrong()
                }
            }
        } else {
            wrong()
        }
    }

    private func isAlmostAsGood(_ uci: String, fen: String) async -> Bool {
        guard let engine else { return false }
        let lines = await engine.analyze(fen: fen, depth: 12, lines: 4)
        guard let top = lines.first, let line = lines.first(where: { $0.firstMove == uci }) else { return false }
        return top.evaluation.winningChances - line.evaluation.winningChances < 0.06
    }

    private func solved(note: String? = nil) {
        game.humanColors = []
        tone = .success
        let outcome: Outcome = usedHint ? .withHint : (mistakes == 0 ? .firstTry : .afterMistake)
        let praise = outcome == .firstTry ? pick(lines?.correct, or: "Yes!") : pick(lines?.correctAfterHint, or: "There it is.")
        message = [note, praise].compactMap { $0 }.joined(separator: " ")
        phase = .done(outcome)
    }

    private func wrong() {
        mistakes += 1
        tone = .wrong
        message = pick(lines?.wrong, or: "Not quite. Have another look.")
        phase = .waiting
        game.humanColors = []
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.game.undo()
            if self.mistakes >= 3 {
                self.showLine()
                return
            }
            self.phase = .solving
            self.game.humanColors = [self.learner]
            if self.mistakes == 2 {
                self.hint()
            }
        }
    }

    /// Plays the rest of the answer with arrows, as a missed drill.
    private func showLine() {
        let remaining = solution.indices.contains(index) ? Array(solution[index...]) : []
        phase = .waiting
        game.humanColors = []
        tone = .hint
        message = "Here's the idea."
        pending = Task { [weak self] in
            guard let self else { return }
            for (offset, uci) in remaining.enumerated() {
                if offset.isMultiple(of: 2), let squares = Notation.squares(of: uci) {
                    self.arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: nil)]
                }
                try? await Task.sleep(for: .milliseconds(offset == 0 ? 700 : 900))
                guard !Task.isCancelled else { return }
                self.playMove(uci)
            }
            self.phase = .done(.missed)
        }
    }

    // MARK: Tap the squares

    private func tapToFind(_ square: Square) {
        let name = square.notation
        let answers = Set(squares)
        if answers.contains(name) {
            guard found.insert(name).inserted else { return }
            marks.append(SquareMark(square: name, color: .green))
            sounds?.play(.select)
            if found.isSuperset(of: answers) {
                tone = .success
                let opener = mistakes == 0 ? pick(lines?.correct, or: "Yes!") : pick(lines?.correctAfterHint, or: "There it is.")
                message = [opener, explain].compactMap { $0 }.joined(separator: " ")
                if let setup, let from = Notation.squares(of: setup)?.to {
                    arrows = squares.map { BoardArrow(from: from.notation, to: $0, color: .red, dashed: nil) }
                }
                phase = .done(usedHint ? .withHint : (mistakes == 0 ? .firstTry : .afterMistake))
            }
        } else {
            mistakes += 1
            tone = .wrong
            message = game.piece(at: square)?.color == learner
                ? "That one's safe. Look at what their last move can reach."
                : "Tap your piece that's in danger."
            let flash = SquareMark(square: name, color: .red)
            marks.append(flash)
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(650))
                guard let self, let position = self.marks.lastIndex(of: flash) else { return }
                self.marks.remove(at: position)
                if self.mistakes >= 3, self.phase == .solving {
                    self.reveal()
                }
            }
        }
    }

    // MARK: Playouts

    private func playoutMoved() {
        movesMade += 1
        if game.winner == learner {
            tone = .success
            message = pick(lines?.correct, or: "Checkmate!") + (movesMade == 1 ? " Checkmate in 1 move." : " Checkmate in \(movesMade) moves.")
            phase = .done(mistakes == 0 ? .firstTry : .afterMistake)
            return
        }
        if game.isGameOver {
            stuck("Stalemate! Their king had no moves but wasn't in check, so it's a draw. Always leave the king a square until the final blow.")
            return
        }
        if movesMade >= moveLimit {
            stuck("Out of moves this time, but you're close. Try again and keep the box shrinking.")
            return
        }
        phase = .waiting
        game.humanColors = []
        let fen = game.fen
        pending = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let started = clock.now
            let move = await self.defenderMove(fen: fen)
            let elapsed = clock.now - started
            if elapsed < .milliseconds(450) {
                try? await Task.sleep(for: .milliseconds(450) - elapsed)
            }
            guard !Task.isCancelled, let move else { return }
            self.playMove(move)
            if self.game.isGameOver {
                self.stuck("That's a draw, so there's no mate left. Keep your pieces protected and the box shrinking, then try again.")
                return
            }
            self.phase = .solving
            self.game.humanColors = [self.learner]
        }
    }

    private func stuck(_ text: String) {
        mistakes += 1
        tone = .wrong
        message = text
        game.humanColors = []
        phase = .stuck
    }

    /// The defending king's move: the engine's, or one that keeps the king central and free.
    private func defenderMove(fen: String) async -> String? {
        if let engine, let move = await engine.chooseMove(fen: fen, skill: 20, thinkTimeMs: 250) {
            return move
        }
        guard let board = TrainingChess.board(after: [], from: fen) else { return nil }
        let moves = TrainingChess.legalMoves(in: board)
        return moves.max { a, b in freedom(after: a, on: board) < freedom(after: b, on: board) }
    }

    private func freedom(after uci: String, on board: Board) -> Int {
        var copy = board
        guard TrainingChess.play(uci, on: &copy) != nil, let to = Notation.squares(of: uci)?.to else { return -100 }
        let center = 7 - (abs(2 * to.fileIndex - 7) + abs(2 * to.rankIndex - 7)) / 2
        // Their options next move, from the defender's side: more is better for it.
        var fields = copy.position.fen.split(separator: " ").map(String.init)
        guard fields.count >= 4 else { return center }
        fields[1] = fields[1] == "w" ? "b" : "w"
        fields[3] = "-"
        guard let passed = Position(fen: fields.joined(separator: " ")) else { return center }
        return center + TrainingChess.legalMoves(in: Board(position: passed)).count
    }

    // MARK: Helpers

    private func playMove(_ uci: String) {
        guard game.playEngineMove(uci), let played = game.lastPlayed else { return }
        sound(for: played)
    }

    private func sound(for move: PlayedMove) {
        guard let sounds else { return }
        if move.isCapture {
            sounds.play(.capture)
        } else if move.givesCheck {
            sounds.play(.check)
        } else if move.isCastle {
            sounds.play(.castle)
        } else {
            sounds.play(.move)
        }
    }

    private func pick(_ options: [String]?, or fallback: String) -> String {
        options?.randomElement() ?? fallback
    }
}
