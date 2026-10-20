import ChessKit
import SwiftUI

/// Perfect Endgames: the player keeps the result (win or draw) against an
/// opponent who never makes a mistake, both judged by the Lichess tablebase.
@MainActor
@Observable
final class EndgameRunner {
    enum Phase: Equatable { case loading, playing, thinking, won, held, failed, offline }

    let study: EndgameStudy
    let player: Piece.Color
    private(set) var board: GameModel
    private(set) var phase: Phase = .loading
    private(set) var message: String
    private(set) var tone: DrillRunner.Tone = .coach
    private(set) var arrows: [BoardArrow] = []
    /// What the player must keep: +1 win, 0 draw.
    private(set) var goal = 1
    /// Mate in this many moves with perfect play, when the tablebase knows it.
    private(set) var bestMate: Int?
    private(set) var movesMade = 0
    private(set) var slips = 0
    /// For a draw: how many good moves in a row hold it.
    static let holdMoves = 12
    private var current: TablebaseResult?
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(study: EndgameStudy) {
        self.study = study
        player = study.player
        let model = GameModel(position: Position(fen: study.fen) ?? .standard)
        model.humanColors = []
        board = model
        message = study.idea
    }

    var goalText: String {
        let side = player == .white ? "White" : "Black"
        return goal > 0 ? "\(side) to play and win" : "\(side) to play and draw"
    }

    func start() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Tablebase.probe(self.board.fen)
                self.current = result
                self.goal = max(0, result.value)
                self.bestMate = result.dtm.map { (abs($0) + 1) / 2 }
                self.phase = .playing
                self.board.humanColors = [self.player]
            } catch {
                self.phase = .offline
                self.tone = .wrong
                self.message = "Perfect Endgames ask the Lichess tablebase about every move, so they need an internet connection."
            }
        }
    }

    func restart() {
        pending?.cancel()
        board = GameModel(position: Position(fen: study.fen) ?? .standard)
        board.humanColors = []
        movesMade = 0
        slips = 0
        arrows = []
        tone = .coach
        message = study.idea
        phase = .loading
        start()
    }

    func cancel() { pending?.cancel() }

    func tap(_ square: Square) {
        guard phase == .playing else { return }
        let before = board.moveCount
        board.tap(square)
        if board.pendingPromotion != nil { board.promote(to: .queen) }
        if board.moveCount != before, let played = board.lastPlayed {
            judge(played)
        }
    }

    /// Shows the tablebase's best move as an arrow.
    func hint() {
        guard phase == .playing, let best = current?.moves.first, let squares = Notation.squares(of: best.uci) else { return }
        arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: true)]
        tone = .hint
        message = "The tablebase likes \(best.san)."
    }

    private func judge(_ played: PlayedMove) {
        arrows = []
        board.humanColors = []
        let value = current?.value(of: played.uci) ?? goal
        if value < goal {
            slips += 1
            tone = .wrong
            let lost = goal > 0 ? (value == 0 ? "lets the win slip to a draw" : "even loses") : "loses"
            message = "\(played.san) \(lost). Try another move."
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                self.board.undo()
                self.board.humanColors = [self.player]
            }
            return
        }
        movesMade += 1
        if checkFinished() { return }
        if goal == 0, movesMade >= Self.holdMoves {
            succeed(held: true)
            return
        }
        phase = .thinking
        tone = .success
        message = goal > 0 ? "Good. Still winning." : "Good. The draw holds."
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let after = try await Tablebase.probe(self.board.fen)
                guard !Task.isCancelled, let reply = after.moves.first else { return }
                try? await Task.sleep(for: .milliseconds(350))
                self.board.playEngineMove(reply.uci)
                SoundPlayer.shared.play(.move)
                if self.checkFinished() { return }
                self.current = try await Tablebase.probe(self.board.fen)
                if let dtm = self.current?.dtm, self.goal > 0 {
                    self.message = "Mate in \((abs(dtm) + 1) / 2) with perfect play."
                    self.tone = .coach
                }
                self.phase = .playing
                self.board.humanColors = [self.player]
            } catch {
                self.phase = .offline
                self.tone = .wrong
                self.message = "Lost the connection to the tablebase. Check your internet and try again."
            }
        }
    }

    /// Mate, stalemate or a dead draw ends it. True when it's over.
    private func checkFinished() -> Bool {
        guard board.isGameOver else { return false }
        if let winner = board.winner {
            if winner == player { succeed(held: false) } else { fail() }
        } else if goal == 0 {
            succeed(held: true)
        } else {
            fail()
        }
        return true
    }

    private func succeed(held: Bool) {
        phase = held ? .held : .won
        board.humanColors = []
        tone = .success
        SoundPlayer.shared.play(.win)
        if held {
            message = "Held! You defended perfectly against perfect play."
        } else if let bestMate {
            message = "Checkmate in \(movesMade) moves. Perfect play needs \(bestMate)."
        } else {
            message = "Won in \(movesMade) moves."
        }
    }

    private func fail() {
        phase = .failed
        board.humanColors = []
        tone = .wrong
        message = goal > 0 ? "That ended in a draw. Try again: no stalemates!" : "That one got away. Try again."
    }
}

struct EndgameView: View {
    let study: EndgameStudy
    let theme: BoardTheme
    @State private var runner: EndgameRunner?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.58))
            VStack(spacing: 12) {
                RoomHeader(title: study.title, subtitle: runner?.goalText) { dismiss() }
                if let runner {
                    HStack {
                        Label("\(runner.movesMade) moves", systemImage: "figure.walk")
                        Spacer()
                        if let best = runner.bestMate, runner.goal > 0 {
                            Text("Perfect: mate in \(best)")
                        } else if runner.goal == 0 {
                            Text("Hold \(EndgameRunner.holdMoves) moves")
                        }
                    }
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    TrainingBoardView(game: runner.board, theme: theme, flipped: runner.player == .black,
                                      arrows: runner.arrows,
                                      onTap: runner.phase == .playing ? { (square: Square) in runner.tap(square) } : nil)
                        .frame(width: side, height: side)
                        .overlay {
                            if runner.phase == .loading || runner.phase == .thinking {
                                ProgressView().controlSize(.large).opacity(runner.phase == .loading ? 1 : 0.6)
                            }
                        }
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        switch runner.phase {
                        case .playing:
                            Button {
                                runner.hint()
                            } label: {
                                Label("Hint", systemImage: "lightbulb.fill")
                            }
                            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false,
                                                             tint: TrainingColor.yellow.color(on: theme)))
                            Button {
                                runner.restart()
                            } label: {
                                Label("Restart", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                        case .won, .held, .failed, .offline:
                            Button {
                                runner.restart()
                            } label: {
                                Label("Play again", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(TrainingButtonStyle(theme: theme))
                        case .loading, .thinking:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .animation(.snappy, value: runner?.phase)
        .onAppear {
            guard runner == nil else { return }
            let made = EndgameRunner(study: study)
            runner = made
            made.start()
        }
        .onDisappear { runner?.cancel() }
    }
}
