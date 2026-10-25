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
    /// The learner talked it through with Leo. Like a hint, it makes a solve one with help.
    private(set) var talkedThrough = false
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
    /// One wrong move ends it and shows the answer, as in Puzzle Rush.
    @ObservationIgnored var strict = false
    /// Hears right and wrong answers, for the coach's spoken reactions ("Nice move", "Try again").
    /// Nil when the drill plays no sound, and in the level check, which is a test.
    @ObservationIgnored var reactions: Reacting?

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
            var text = Self.prompt(for: drill, skill: skill, role: item.role)
            if drill.type == .safe {
                // Name the move now, from the position it's played in, so the
                // question never shows its placeholder while the setup move animates.
                let after = drill.setup.flatMap { TrainingChess.fen(after: [$0], from: drill.fen) } ?? drill.fen
                let san = drill.move.flatMap { Notation.san(of: $0, fen: after) } ?? drill.move ?? "this move"
                text = text.replacingOccurrences(of: "{move}", with: san)
            }
            prompt = text
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
        reactions = playsSounds ? (CoachReactions.shared as Reacting) : nil
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
        react(right ? .nice : .missed)
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
            react(mistakes == 0 ? .nice : .afterHelp)
        } else {
            mistakes += 1
            tone = .wrong
            message = option.why ?? pick(lines?.wrong, or: "Not that one. Try another.")
            if mistakes == 1 { react(.tryAgain) }
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
            var attackers: [Square] = []
            for attacker in squares.flatMap({ threats(to: $0) }) where !attackers.contains(attacker) {
                attackers.append(attacker)
            }
            marks = marks.filter { $0.color != .yellow } + attackers.map { SquareMark(square: $0.notation, color: .yellow) }
            if attackers.count == 1, let piece = game.piece(at: attackers[0]) {
                message = "Look at every square their \(BoardGeometry.name(piece.kind)) on \(attackers[0].notation) can reach."
            } else {
                message = "Look at what their pieces can reach now."
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
            arrows = threatArrows()
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
            if phase == .solving {
                // Given up mid-playout: say so, rather than leaving the question up.
                tone = .hint
                message = "No problem. We'll come back to this one."
            }
            game.humanColors = []
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
        // Back to the intro right away, so the stuck buttons go and "Move on" can't
        // record the drill while the board resets.
        phase = .intro
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
            react(.keepGoing)
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
            tone = .coach
            message = "Hmm, let me check that one with Stockfish…"
            let fen = played.fenBefore
            pending = Task { [weak self] in
                guard let self else { return }
                let fine = await self.isAlmostAsGood(uci, fen: fen)
                guard !Task.isCancelled else { return }
                if fine {
                    self.solved(note: "That works too!")
                } else {
                    self.wrong(played)
                }
            }
        } else {
            wrong(played)
        }
    }

    private func isAlmostAsGood(_ uci: String, fen: String) async -> Bool {
        guard let engine else { return false }
        let lines = await engine.analyze(fen: fen, depth: 12, lines: 4, maxTimeMs: 1500)
        guard let top = lines.first, let line = lines.first(where: { $0.firstMove == uci }) else { return false }
        return top.evaluation.winningChances - line.evaluation.winningChances < 0.06
    }

    private func solved(note: String? = nil) {
        game.humanColors = []
        tone = .success
        // A miss counts for more than a hint: the second miss hands out a hint on its own.
        let outcome: Outcome = mistakes > 0 ? .afterMistake : (usedHint || talkedThrough ? .withHint : .firstTry)
        let praise = outcome == .firstTry ? pick(lines?.correct, or: "Yes!") : pick(lines?.correctAfterHint, or: "There it is.")
        message = [note, praise].compactMap { $0 }.joined(separator: " ")
        phase = .done(outcome)
        // Every move of a longer puzzle right the first time deserves more than "nice".
        react(outcome == .firstTry ? (solution.count >= 3 ? .brilliant : .nice) : .afterHelp)
    }

    private func wrong(_ played: PlayedMove) {
        mistakes += 1
        tone = .wrong
        message = pick(lines?.wrong, or: "Not quite. Have another look.")
        if Self.givesPieceAway(played) {
            react(.blunder)
        } else if strict || mistakes >= 3 {
            react(.missed)
        } else if mistakes == 1 {
            react(.tryAgain)
        }
        phase = .waiting
        game.humanColors = []
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.game.undo()
            if self.strict || self.mistakes >= 3 {
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

    // MARK: Talk it through

    /// Talk it through is on offer: a find-the-move drill on the learner's turn, outside Rush and
    /// Cycles, which give no help.
    var canTalkItThrough: Bool {
        guard phase == .solving, kind == .move, !strict else { return false }
        return game.sideToMove == learner && game.pendingPromotion == nil && !game.isGameOver
    }

    /// The other side's last move in engine notation: the one that set the drill up, or their reply.
    var lastMoveUCI: String? {
        game.lastPlayed?.uci ?? game.lastMove.map { $0.from.notation + $0.to.notation }
    }

    /// The learner's words went to Leo: from now on a solve counts as one with help.
    func talkedItThrough() {
        talkedThrough = true
    }

    /// Plays the move the learner settled on with Leo, judged like one made on the board.
    @discardableResult
    func playLearnerMove(_ uci: String) -> Bool {
        guard phase == .solving, kind == .move, game.sideToMove == learner else { return false }
        let movesBefore = game.moveCount
        guard game.playEngineMove(uci), game.moveCount != movesBefore, let played = game.lastPlayed else { return false }
        sound(for: played)
        marks = []
        judge(played)
        return true
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
                arrows = threatArrows()
                phase = .done(mistakes > 0 ? .afterMistake : (usedHint ? .withHint : .firstTry))
                react(mistakes == 0 && !usedHint ? .nice : .afterHelp)
            }
        } else {
            mistakes += 1
            tone = .wrong
            if mistakes == 1 { react(.tryAgain) }
            message = game.piece(at: square)?.color == learner
                ? "That one's safe. Look at what their pieces can reach now."
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

    /// Their pieces that attack an answer square: the piece that just moved when
    /// it does, otherwise everything of theirs that reaches it (a discovered
    /// attack), or the moved piece anyway when nothing does.
    private func threats(to square: String) -> [Square] {
        let geometry = BoardGeometry(position: game.board.position)
        let attackers = geometry.attackers(of: Square(square), by: learner.opposite)
        let moved = setup.flatMap { Notation.squares(of: $0)?.to }
        if let moved, attackers.contains(moved) { return [moved] }
        if !attackers.isEmpty { return attackers.sorted { $0.rawValue < $1.rawValue } }
        return moved.map { [$0] } ?? []
    }

    /// A red arrow from each attacker to the piece of ours it hits.
    private func threatArrows() -> [BoardArrow] {
        squares.flatMap { square in
            threats(to: square).map { BoardArrow(from: $0.notation, to: square, color: .red, dashed: nil) }
        }
    }

    // MARK: Playouts

    private func playoutMoved() {
        movesMade += 1
        if game.winner == learner {
            tone = .success
            message = pick(lines?.correct, or: "Checkmate!") + (movesMade == 1 ? " Checkmate in 1 move." : " Checkmate in \(movesMade) moves.")
            phase = .done(mistakes == 0 ? .firstTry : .afterMistake)
            react(mistakes == 0 ? .brilliant : .afterHelp)
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
        react(.missed)
        game.humanColors = []
        phase = .stuck
    }

    /// The defending king's move: the engine's, or one that keeps the king central and free.
    private func defenderMove(fen: String) async -> String? {
        if let engine, let move = await engine.chooseMove(fen: fen, skill: 20, depth: nil, thinkTimeMs: 250) {
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

    private func react(_ moment: ReactionMoment) {
        reactions?.react(moment, strict: strict)
    }

    /// A move that just gives a piece away: a knight or more lands where they can take it for
    /// nothing (or with something cheaper), and it didn't capture anything as good on the way.
    static func givesPieceAway(_ played: PlayedMove) -> Bool {
        guard let squares = Notation.squares(of: played.uci), let before = BoardGeometry(fen: played.fenBefore)
        else { return false }
        let after = before.applying(uci: played.uci)
        guard let moved = after.piece(at: squares.to), BoardGeometry.value(moved.kind) >= 3 else { return false }
        let taken = before.piece(at: squares.to).map { BoardGeometry.value($0.kind) } ?? 0
        guard taken < BoardGeometry.value(moved.kind) else { return false }
        return after.isHanging(squares.to)
    }

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
