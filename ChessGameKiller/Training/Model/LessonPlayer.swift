import ChessKit
import Foundation
import Observation

/// Plays a lesson like a video: the coach talks, pieces move, arrows and
/// glowing squares come and go, and every so often it's the learner's turn.
@MainActor
@Observable
final class LessonPlayer {
    enum Phase: Equatable {
        case playing
        case paused
        /// Waiting for the learner to do the step's task.
        case task
        case finished
    }

    enum Tone: Equatable {
        case coach, success, wrong, hint
    }

    let lesson: Lesson
    private(set) var game: GameModel
    private(set) var stepIndex = 0
    private(set) var phase: Phase = .paused
    private(set) var caption = ""
    private(set) var tone: Tone = .coach
    private(set) var arrows: [BoardArrow] = []
    private(set) var marks: [SquareMark] = []
    private(set) var labels: [SquareLabel] = []
    /// Whether the current step's task is done.
    private(set) var solved = false
    /// Choice answers tried in the current step.
    private(set) var tried: Set<Int> = []
    /// Wrong tries on the current task. The hint shows after two.
    private(set) var misses = 0

    private let starts: [String]
    private let voice: CoachVoice
    private let sounds: SoundPlaying?
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var found: Set<String> = []
    /// Where the learner is in a move task's solution.
    @ObservationIgnored private var solutionIndex = 0

    var steps: [LessonStep] { lesson.steps }
    var step: LessonStep { lesson.steps[stepIndex] }
    /// The task the learner is on, or just finished.
    var task: LessonTask? { phase == .task ? step.task : nil }
    var isFlipped: Bool { lesson.orientation == .black }

    /// Nil when the lesson's positions or moves don't add up.
    init?(lesson: Lesson, voice: CoachVoice? = nil, playsSounds: Bool = true) {
        guard let starts = Self.startPositions(of: lesson), let first = starts.first,
              let position = Position(fen: first) else { return nil }
        self.lesson = lesson
        self.starts = starts
        self.voice = voice ?? .shared
        sounds = playsSounds ? (SoundPlayer.shared as SoundPlaying) : nil
        game = GameModel(position: position)
        game.humanColors = []
        caption = lesson.steps.first?.say ?? ""
    }

    /// The position at the start of each step, worked out once so any step can be replayed.
    static func startPositions(of lesson: Lesson) -> [String]? {
        var starts: [String] = []
        var current: String?
        for step in lesson.steps {
            if let fen = step.fen {
                guard let normalized = TrainingChess.normalized(fen) else { return nil }
                current = normalized
            }
            guard let start = current else { return nil }
            starts.append(start)
            var moves = step.moves ?? []
            if let task = step.task, task.type == .move {
                moves += task.solution ?? []
            }
            guard let end = TrainingChess.fen(after: moves, from: start) else { return nil }
            current = end
        }
        return starts.isEmpty ? nil : starts
    }

    // MARK: Controls

    func start() {
        voice.beginLesson()
        play(from: 0)
    }

    /// Stops everything. Call when the lesson closes.
    func close() {
        run?.cancel()
        run = nil
        voice.endLesson()
    }

    func togglePause() {
        switch phase {
        case .playing:
            run?.cancel()
            voice.stop()
            phase = .paused
        case .paused:
            play(from: stepIndex)
        case .task, .finished:
            break
        }
    }

    func back() { play(from: max(0, stepIndex - 1)) }

    func replay() { play(from: stepIndex) }

    func skip() {
        if stepIndex + 1 < steps.count {
            play(from: stepIndex + 1)
        } else {
            finish()
        }
    }

    func restart() { play(from: 0) }

    // MARK: The learner's turn

    func tap(_ square: Square) {
        guard phase == .task, !solved, let task = step.task else { return }
        switch task.type {
        case .move: tapToMove(square, task: task)
        case .tap: tapToFind(square, task: task)
        case .choice: break
        }
    }

    func choose(_ index: Int) {
        guard phase == .task, !solved, let task = step.task, let options = task.options,
              options.indices.contains(index), !tried.contains(index) else { return }
        tried.insert(index)
        let option = options[index]
        if let move = option.move, let squares = Notation.squares(of: move) {
            arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation,
                                 color: option.correct ? .green : .red, dashed: nil)]
        }
        if option.correct {
            succeed(task, adding: option.why)
        } else {
            miss(task, saying: option.why)
        }
    }

    /// The task's hint, when the learner asks for it.
    func showHint() {
        guard phase == .task, !solved, let task = step.task, let hint = task.hint else { return }
        tone = .hint
        caption = hint
        if task.type == .move, let solution = task.solution, solution.indices.contains(solutionIndex),
           let squares = Notation.squares(of: solution[solutionIndex]) {
            let mark = SquareMark(square: squares.from.notation, color: .yellow)
            if !marks.contains(mark) { marks.append(mark) }
        }
        Task { [weak self] in await self?.voice.say(hint) }
    }

    /// Shows the answer, then carries on.
    func showAnswer() {
        guard phase == .task, !solved, let task = step.task else { return }
        switch task.type {
        case .move:
            let solution = task.solution ?? []
            guard solutionIndex < solution.count else { return succeed(task) }
            let remaining = Array(solution[solutionIndex...])
            solved = true
            game.humanColors = []
            tone = .hint
            run?.cancel()
            // Cancelling may have stopped a wrong move being taken back, or their
            // reply being played. Put the board where the answer starts from.
            if let expected = TrainingChess.fen(after: (step.moves ?? []) + Array(solution.prefix(solutionIndex)), from: starts[stepIndex]),
               TrainingChess.key(game.fen) != TrainingChess.key(expected), let position = Position(fen: expected) {
                game = GameModel(position: position)
                game.humanColors = []
            }
            run = Task { [weak self] in
                guard let self else { return }
                for (offset, uci) in remaining.enumerated() {
                    if offset.isMultiple(of: 2), let squares = Notation.squares(of: uci) {
                        self.arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: nil)]
                    }
                    try? await Task.sleep(for: .milliseconds(offset == 0 ? 700 : 900))
                    guard !Task.isCancelled else { return }
                    self.playMove(uci)
                }
                self.solved = false
                self.succeed(task)
            }
        case .tap:
            marks = (task.squares ?? []).map { SquareMark(square: $0, color: .green) }
            succeed(task)
        case .choice:
            if let index = task.options?.firstIndex(where: \.correct) {
                choose(index)
            }
        }
    }

    // MARK: Playing steps

    private func play(from index: Int) {
        run?.cancel()
        voice.stop()
        run = Task { [weak self] in
            await self?.perform(from: index)
        }
    }

    private func perform(from index: Int) async {
        var current = index
        while current < steps.count {
            await show(step: current)
            if Task.isCancelled || phase == .task { return }
            current += 1
        }
        finish()
    }

    private func show(step index: Int) async {
        stepIndex = index
        let step = steps[index]
        phase = .playing
        solved = false
        tried = []
        misses = 0
        found = []
        solutionIndex = 0
        tone = .coach
        if TrainingChess.key(game.fen) != TrainingChess.key(starts[index]), let position = Position(fen: starts[index]) {
            game = GameModel(position: position)
        }
        game.humanColors = []
        arrows = step.arrows ?? []
        marks = step.marks ?? []
        labels = step.labels ?? []
        caption = step.say ?? step.task?.prompt ?? ""

        // A task step with nothing else to say reads its prompt out instead.
        let line = step.say ?? step.task?.prompt ?? ""
        async let talking: Void = voice.say(line)
        await animate(step.moves ?? [])
        await talking
        guard !Task.isCancelled else { return }

        if let pause = step.pause, pause > 0 {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
        }

        if let task = step.task {
            phase = .task
            tone = .coach
            caption = task.prompt
            if task.type == .move {
                game.humanColors = [game.sideToMove]
            }
            if step.say != nil {
                await voice.say(task.prompt)
            }
        } else {
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    private func animate(_ moves: [String]) async {
        guard !moves.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(600))
        for (offset, uci) in moves.enumerated() {
            if offset > 0 {
                try? await Task.sleep(for: .milliseconds(850))
            }
            guard !Task.isCancelled else { return }
            playMove(uci)
        }
    }

    private func finish() {
        run?.cancel()
        voice.stop()
        game.humanColors = []
        phase = .finished
    }

    // MARK: Tasks

    private func tapToMove(_ square: Square, task: LessonTask) {
        let movesBefore = game.moveCount
        let selectedBefore = game.selected
        game.tap(square)
        if game.pendingPromotion != nil {
            let expected = (task.solution ?? []).indices.contains(solutionIndex) ? task.solution?[solutionIndex] : nil
            game.promote(to: expected.flatMap(TrainingChess.promotionKind(of:)) ?? .queen)
        }
        if game.moveCount != movesBefore, let played = game.lastPlayed {
            sound(for: played)
            judge(played.uci, task: task)
        } else if game.selected != nil, game.selected != selectedBefore {
            sounds?.play(.select)
        }
    }

    private func judge(_ uci: String, task: LessonTask) {
        let solution = task.solution ?? []
        let expected = solutionIndex < solution.count ? solution[solutionIndex] : nil
        let learnerMove = solutionIndex / 2
        let others = (task.accept ?? []).indices.contains(learnerMove) ? (task.accept ?? [])[learnerMove] : []
        let mated = (task.mate ?? false) && game.winner != nil

        if uci == expected, !mated, solutionIndex + 1 < solution.count {
            // Right so far: their reply, then the learner again.
            let reply = solution[solutionIndex + 1]
            solutionIndex += 2
            game.humanColors = []
            tone = .success
            run?.cancel()
            run = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard let self, !Task.isCancelled else { return }
                self.playMove(reply)
                if self.solutionIndex >= solution.count {
                    self.succeed(task)
                } else {
                    self.tone = .coach
                    self.game.humanColors = [self.game.sideToMove]
                }
            }
        } else if uci == expected || others.contains(uci) || mated {
            succeed(task)
        } else {
            miss(task, saying: task.feedback?[uci])
            game.humanColors = []
            run?.cancel()
            run = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                self.game.undo()
                self.game.humanColors = [self.game.sideToMove]
            }
        }
    }

    private func tapToFind(_ square: Square, task: LessonTask) {
        let name = square.notation
        let answers = Set(task.squares ?? [])
        if answers.contains(name) {
            guard found.insert(name).inserted else { return }
            marks.append(SquareMark(square: name, color: .green))
            sounds?.play(.select)
            if found.isSuperset(of: answers) {
                succeed(task)
            }
        } else {
            let flash = SquareMark(square: name, color: .red)
            marks.append(flash)
            miss(task, saying: task.feedback?[name])
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, let index = self.marks.lastIndex(of: flash) else { return }
                self.marks.remove(at: index)
            }
        }
    }

    private func succeed(_ task: LessonTask, adding why: String? = nil) {
        guard !solved else { return }
        solved = true
        game.humanColors = []
        tone = .success
        let line = [task.success, why].compactMap { $0 }.joined(separator: " ")
        caption = line
        run?.cancel()
        run = Task { [weak self] in
            guard let self else { return }
            await self.voice.say(line)
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            if self.stepIndex + 1 < self.steps.count {
                await self.perform(from: self.stepIndex + 1)
            } else {
                self.finish()
            }
        }
    }

    private func miss(_ task: LessonTask, saying feedback: String?) {
        misses += 1
        var line = feedback ?? task.wrong ?? "Not quite. Have another look."
        tone = .wrong
        if misses >= 2, let hint = task.hint {
            line = hint
            tone = .hint
            if task.type == .move, let solution = task.solution, solution.indices.contains(solutionIndex),
               let squares = Notation.squares(of: solution[solutionIndex]) {
                let mark = SquareMark(square: squares.from.notation, color: .yellow)
                if !marks.contains(mark) { marks.append(mark) }
            }
        }
        caption = line
        Task { [weak self] in await self?.voice.say(line) }
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
}
