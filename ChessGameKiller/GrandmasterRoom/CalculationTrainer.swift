import ChessKit
import SwiftUI

/// Calculation: the board stays still while a few moves are read out. The
/// player plays them in their head and finds the winning move at the end.
/// Blindfold hides the pieces too, after a few seconds to memorize them.
@MainActor
@Observable
final class CalcRunner {
    enum Phase: Equatable { case memorize, solving, right, wrong }

    let depth: Int
    let blindfold: Bool
    private(set) var puzzle: LichessPuzzle?
    private(set) var phase: Phase = .solving
    private(set) var from: Square?
    private(set) var solved = 0
    private(set) var tried = 0
    private(set) var streak = 0
    private let library: PuzzleLibrary
    private let rating: Int
    private var seen: Set<String> = []

    init(library: PuzzleLibrary, depth: Int, blindfold: Bool, rating: Int) {
        self.library = library
        self.depth = depth
        self.blindfold = blindfold
        self.rating = rating
    }

    /// The moves read out: the opponent's, then the line up to the player's last move to find.
    var spoken: [String] {
        guard let puzzle else { return [] }
        return Array(puzzle.moves.prefix(depth * 2 + 1))
    }

    var answer: String? {
        guard let puzzle, puzzle.moves.count > depth * 2 + 1 else { return nil }
        return puzzle.moves[depth * 2 + 1]
    }

    /// The side the player finds a move for.
    var player: Piece.Color {
        puzzle?.fen.split(separator: " ").dropFirst().first == "b" ? .white : .black
    }

    var lineText: String {
        guard let puzzle else { return "" }
        let blackFirst = puzzle.fen.split(separator: " ").dropFirst().first == "b"
        return Notation.numbered(Notation.sanLine(of: spoken, fen: puzzle.fen, limit: spoken.count), blackFirst: blackFirst)
    }

    /// The position the player has to picture, for after they answer.
    var finalFEN: String? {
        guard let puzzle else { return nil }
        return TrainingChess.fen(after: spoken, from: puzzle.fen)
    }

    /// What the board shows: the start, or nothing in blindfold once memorized.
    var draft: PositionDraft {
        guard let puzzle else { return .empty }
        switch phase {
        case .right, .wrong:
            return finalFEN.flatMap { PositionDraft(fen: $0) } ?? .empty
        case .solving where blindfold:
            return .empty
        default:
            return PositionDraft(fen: puzzle.fen) ?? .empty
        }
    }

    var hints: [MoveHint] {
        guard phase == .right || phase == .wrong, let answer, let squares = Notation.squares(of: answer) else { return [] }
        let san = finalFEN.flatMap { Notation.san(of: answer, fen: $0) } ?? answer
        return [MoveHint(rank: 0, from: squares.from, to: squares.to, san: san, uci: answer, evaluation: .centipawns(0))]
    }

    var answerSAN: String { hints.first?.san ?? "" }

    func next() {
        from = nil
        let needed = depth + 1
        var generator = SystemRandomNumberGenerator()
        for window in [150, 300, 600, 3000] {
            let pool = library.puzzles.filter {
                $0.length >= needed && abs($0.rating - rating) <= window && !seen.contains($0.id)
            }
            if let pick = pool.randomElement(using: &generator) {
                puzzle = pick
                seen.insert(pick.id)
                break
            }
        }
        phase = blindfold ? .memorize : .solving
    }

    func memorized() {
        guard phase == .memorize else { return }
        phase = .solving
    }

    func tap(_ square: Square) {
        guard phase == .solving, let answer else { return }
        guard let picked = from else {
            from = square
            return
        }
        if picked == square {
            from = nil
            return
        }
        tried += 1
        let guess = picked.notation + square.notation
        if answer.hasPrefix(guess) || isOtherMate(guess) {
            solved += 1
            streak += 1
            phase = .right
            SoundPlayer.shared.play(.win)
        } else {
            streak = 0
            phase = .wrong
        }
        from = nil
    }

    /// A different move that also mates at once is just as right.
    private func isOtherMate(_ guess: String) -> Bool {
        guard let fen = finalFEN, var board = TrainingChess.board(after: [], from: fen) else { return false }
        let move = TrainingChess.legalMoves(in: board).first { $0.hasPrefix(guess) }
        guard let move, TrainingChess.play(move, on: &board) != nil else { return false }
        return TrainingChess.isCheckmate(board)
    }

    func giveUp() {
        guard phase == .solving || phase == .memorize else { return }
        tried += 1
        streak = 0
        phase = .wrong
    }
}

struct CalculationView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("calc.depth") private var depth = 1
    @AppStorage("calc.blindfold") private var blindfold = false
    /// The longest run of right answers, kept for the Calculation door.
    @AppStorage(Self.bestStreakKey) private var bestStreak = 0
    @State private var runner: CalcRunner?

    static let bestStreakKey = "calc.bestStreak"

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.52))
            VStack(spacing: 12) {
                RoomHeader(title: "Calculation", subtitle: "See the moves in your head") { dismiss() }
                // Scrolls only when it must, so the buttons are never cut off on a small phone.
                ScrollView {
                    VStack(spacing: 12) {
                        settingsRow.padding(.horizontal, 16)
                        if let runner, runner.puzzle != nil {
                            Text(runner.lineText)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .trainingCard(theme, cornerRadius: 16)
                                .padding(.horizontal, 16)
                            PositionBoard(draft: runner.draft, theme: theme, flipped: runner.player == .black,
                                          hints: runner.hints) { square in
                                runner.tap(square)
                            }
                            .frame(width: side, height: side)
                            TurnBadge(theme: theme, side: runner.player,
                                      text: runner.from.map { "From \($0.notation). Now tap where it goes." },
                                      showing: runner.from != nil)
                                .padding(.top, -6)
                            RoomMessage(text: message(runner), tone: tone(runner), theme: theme)
                                .padding(.horizontal, 16)
                            buttons(runner).padding(.horizontal, 16)
                        } else if puzzles.library == nil {
                            ProgressView("Loading puzzles…").padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .animation(.snappy, value: runner?.phase)
        .task {
            await puzzles.load()
            restart()
        }
        .onChange(of: depth) { _, _ in restart() }
        .onChange(of: blindfold) { _, _ in restart() }
        .onChange(of: runner?.solved) { _, solved in
            guard let runner, solved != nil, runner.phase == .right else { return }
            bestStreak = max(bestStreak, runner.streak)
            training?.recordPractice(xp: 4 + 2 * runner.depth)
        }
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            Picker("Moves ahead", selection: $depth) {
                Text("Short").tag(1)
                Text("Medium").tag(2)
                Text("Long").tag(3)
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $blindfold) {
                Label("Blindfold", systemImage: "eye.slash.fill")
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
            }
            .toggleStyle(.button)
        }
    }

    private func message(_ runner: CalcRunner) -> String {
        switch runner.phase {
        case .memorize: return "Blindfold. Memorize the position, then the pieces disappear."
        case .solving:
            let side = runner.player == .white ? "White" : "Black"
            return "Play the moves above in your head. Then find \(side)'s winning move: tap its piece's square, then where it goes."
        case .right:
            let record = runner.streak >= bestStreak && runner.streak > 1 ? " A new best!" : ""
            return "Yes, \(runner.answerSAN)! That's the position you saw in your head. Streak \(runner.streak).\(record)"
        case .wrong: return "The move was \(runner.answerSAN). Here's the position you were picturing."
        }
    }

    private func tone(_ runner: CalcRunner) -> DrillRunner.Tone {
        switch runner.phase {
        case .right: return .success
        case .wrong: return .wrong
        default: return .coach
        }
    }

    @ViewBuilder
    private func buttons(_ runner: CalcRunner) -> some View {
        switch runner.phase {
        case .memorize:
            Button("I've got it") { withAnimation(.snappy) { runner.memorized() } }
                .buttonStyle(TrainingButtonStyle(theme: theme))
        case .solving:
            Button("Show me") { withAnimation(.snappy) { runner.giveUp() } }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
        case .right, .wrong:
            HStack {
                Text("\(runner.solved) of \(runner.tried)")
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Next") { withAnimation(.snappy) { runner.next() } }
                    .buttonStyle(TrainingButtonStyle(theme: theme))
            }
        }
    }

    private func restart() {
        guard let library = puzzles.library else { return }
        let made = CalcRunner(library: library, depth: depth, blindfold: blindfold,
                              rating: max(900, puzzles.progress.rating - 200 * (depth - 1)))
        made.next()
        runner = made
    }
}
