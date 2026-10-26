import ChessKit
import SwiftUI

/// Guess the Move: play through a famous game from the winner's side. At every
/// move the player guesses what the grandmaster played. A match scores 10;
/// anything else is checked by Stockfish and scores by how close it came.
@MainActor
@Observable
final class GuessRunner {
    enum Phase: Equatable { case watching, guessing, checking, finished }

    let game: ClassicGame
    let hero: Piece.Color
    private(set) var board: GameModel
    private(set) var phase: Phase = .watching
    private(set) var message: String
    private(set) var tone: DrillRunner.Tone = .coach
    private(set) var arrows: [BoardArrow] = []
    private(set) var points = 0
    private(set) var guesses = 0
    private(set) var exact = 0
    private var index = 0
    private let engine: ChessEngine?
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(game: ClassicGame, engine: ChessEngine?) {
        self.game = game
        self.engine = engine
        hero = game.hero
        let model = GameModel()
        model.humanColors = []
        board = model
        message = "You're \(game.heroName). Guess each of their moves."
        previousBest = Self.best(for: game.id)
    }

    var maxPoints: Int { guesses * 10 }
    var percent: Int { maxPoints == 0 ? 0 : Int((Double(points) / Double(maxPoints) * 100).rounded()) }
    var movesLeft: Int { game.moves.count - index }
    /// The best score kept from earlier tries at this game, before this one.
    let previousBest: Int?

    // MARK: Best scores

    private static let bestKey = "guess.best"

    /// The best score, in percent, the player has had at a game.
    static func best(for gameID: String, defaults: UserDefaults = .standard) -> Int? {
        (defaults.dictionary(forKey: bestKey) as? [String: Int])?[gameID]
    }

    static func saveBest(_ percent: Int, for gameID: String, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: bestKey) as? [String: Int] ?? [:]
        guard percent > all[gameID] ?? -1 else { return }
        all[gameID] = percent
        defaults.set(all, forKey: bestKey)
    }

    func start() {
        advance()
    }

    func cancel() { pending?.cancel() }

    func tap(_ square: Square) {
        guard phase == .guessing else { return }
        let before = board.moveCount
        board.tap(square)
        if board.pendingPromotion != nil {
            let expected = game.moves[index]
            board.promote(to: expected.count == 5 ? (TrainingChess.promotionKind(of: expected) ?? .queen) : .queen)
        }
        if board.moveCount != before, let played = board.lastPlayed {
            judge(played)
        }
    }

    /// The opponent's moves play by themselves; then it's the player's turn.
    private func advance() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            while self.index < self.game.moves.count, self.board.sideToMove != self.hero {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                self.board.playEngineMove(self.game.moves[self.index])
                SoundPlayer.shared.play(.move)
                self.index += 1
            }
            if self.index >= self.game.moves.count {
                self.finish()
            } else {
                self.phase = .guessing
                self.board.humanColors = [self.hero]
            }
        }
    }

    private func judge(_ played: PlayedMove) {
        board.humanColors = []
        let gm = game.moves[index]
        guesses += 1
        if played.uci == gm {
            points += 10
            exact += 1
            tone = .success
            message = "\(played.san)! That's exactly what \(game.heroName) played. +10"
            arrows = []
            index += 1
            advance()
            return
        }
        phase = .checking
        tone = .coach
        message = "\(played.san)? Let's see what Stockfish thinks…"
        let fen = played.fenBefore
        let mine = played.uci
        pending = Task { [weak self] in
            guard let self else { return }
            let checked = await self.score(mine, against: gm, fen: fen)
            guard !Task.isCancelled else { return }
            self.board.undo()
            let gmSAN = Notation.san(of: gm, fen: fen) ?? gm
            if let score = checked {
                self.points += score
                switch score {
                case 8...: self.tone = .success; self.message = "Just as strong as the grandmaster's \(gmSAN). +\(score)"
                case 4...: self.tone = .hint; self.message = "Decent. \(self.game.heroName) played \(gmSAN). +\(score)"
                case 1...: self.tone = .hint; self.message = "Playable, but \(gmSAN) was much stronger. +\(score)"
                default: self.tone = .wrong; self.message = "That one hurts. The grandmaster played \(gmSAN)."
                }
            } else {
                // Unchecked guesses don't count either way.
                self.guesses -= 1
                self.tone = .coach
                self.message = "I couldn't check that one, so it doesn't count. \(self.game.heroName) played \(gmSAN)."
            }
            if let squares = Notation.squares(of: gm) {
                self.arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: nil)]
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self.board.playEngineMove(gm)
            SoundPlayer.shared.play(.move)
            self.index += 1
            try? await Task.sleep(for: .milliseconds(500))
            self.arrows = []
            self.advance()
        }
    }

    /// 0 to 9 by how much winning chance the guess gives up compared with the grandmaster's
    /// move. Nil when the engine couldn't check it.
    private func score(_ mine: String, against gm: String, fen: String) async -> Int? {
        guard let engine,
              let afterMine = TrainingChess.fen(after: [mine], from: fen),
              let afterGM = TrainingChess.fen(after: [gm], from: fen) else { return nil }
        let mineLines = await engine.analyze(fen: afterMine, depth: 14, lines: 1, maxTimeMs: 700)
        let gmLines = await engine.analyze(fen: afterGM, depth: 14, lines: 1, maxTimeMs: 700)
        guard let m = mineLines.first?.evaluation.flipped.winningChances,
              let g = gmLines.first?.evaluation.flipped.winningChances else { return nil }
        let loss = g - m
        switch loss {
        case ..<0.03: return 9
        case ..<0.08: return 6
        case ..<0.15: return 4
        case ..<0.3: return 2
        default: return 0
        }
    }

    private func finish() {
        phase = .finished
        board.humanColors = []
        tone = .success
        message = "Game over: \(game.result). You found \(exact) of \(guesses) moves exactly."
        if guesses > 0 {
            Self.saveBest(percent, for: game.id)
        }
    }
}

struct GuessTheMoveView: View {
    let game: ClassicGame
    let theme: BoardTheme
    @State private var runner: GuessRunner?
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.58))
            VStack(spacing: 12) {
                RoomHeader(title: game.title, subtitle: game.playedAt) { dismiss() }
                if let runner {
                    HStack {
                        Label(runner.guesses == 0 ? "—" : "\(runner.points) / \(runner.maxPoints)", systemImage: "star.fill")
                        Spacer()
                        Text(runner.guesses == 0 ? "—" : "\(runner.percent)%")
                        Spacer()
                        Text("\(runner.movesLeft) moves left")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 20)
                    TrainingBoardView(game: runner.board, theme: theme, flipped: runner.hero == .black,
                                      arrows: runner.arrows,
                                      onTap: runner.phase == .guessing ? { (square: Square) in runner.tap(square) } : nil)
                        .frame(width: side, height: side)
                        .boardHeadroom(theme: theme, side: side)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                    if runner.phase == .finished {
                        VStack(spacing: 6) {
                            Text("You scored \(runner.percent)%")
                                .font(.system(.title3, design: .themed).weight(.bold).monospacedDigit())
                                .foregroundStyle(theme.trainingAccent)
                                .multilineTextAlignment(.center)
                            if let best = runner.previousBest {
                                Text(runner.percent > best ? "A new best. Your last best was \(best)%." : "Your best here is \(best)%.")
                                    .font(.system(.subheadline, design: .themed).weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text(game.blurb)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        HStack(spacing: 10) {
                            Button {
                                restart()
                            } label: {
                                Label("Play again", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                            Button("Done") { dismiss() }
                                .buttonStyle(TrainingButtonStyle(theme: theme))
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .animation(.snappy, value: runner?.phase)
        .onAppear {
            guard runner == nil else { return }
            restart()
        }
        .onChange(of: runner?.phase) { _, phase in
            // A finished game counts as a day's training.
            if phase == .finished, let runner, runner.guesses > 0 {
                training?.recordPractice(xp: max(10, runner.percent / 3))
            }
        }
        .onDisappear { runner?.cancel() }
    }

    private func restart() {
        runner?.cancel()
        let made = GuessRunner(game: game, engine: StockfishEngine.shared)
        runner = made
        made.start()
    }
}

// MARK: Shared pieces of the room

/// A close button, a title and a line under it.
struct RoomHeader: View {
    let title: String
    var subtitle: String?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.headline, design: .themed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// Coach Leo's line under the board.
struct RoomMessage: View {
    let text: String
    let tone: DrillRunner.Tone
    let theme: BoardTheme

    var body: some View {
        let tint = tone == .coach ? nil : theme.trainingTone(tone)
        HStack(alignment: .top, spacing: 12) {
            CoachAvatar(theme: theme, size: 36, tint: tint)
            Text(text)
                .font(.system(.subheadline, design: .themed).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(text)
                .transition(.opacity)
        }
        .padding(14)
        .trainingCard(theme, tint: tint, cornerRadius: 18)
        .animation(.easeInOut(duration: 0.2), value: text)
        .accessibilityElement(children: .combine)
    }
}
