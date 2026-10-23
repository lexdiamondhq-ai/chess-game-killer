import ChessKit
import SwiftUI

/// Find my level: ten puzzles in about two minutes, harder after a solve and
/// easier after a miss, then an estimated rating with a friendly name for it,
/// so a strong player can skip the basics.
struct LevelCheckView: View {
    let theme: BoardTheme
    /// Called with the estimate when the player taps "Start training" (or closes the
    /// result), and with nil when they skip or leave before the end. The presenter
    /// closes the screen.
    let onFinish: (Int?) -> Void
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(ThinkStore.self) private var store: ThinkStore?
    @State private var runner: LevelCheckRunner?

    /// The level check. Needs `.environment(puzzleStore)`; with
    /// `.environment(thinkStore)` as well, the estimate is saved there too.
    init(theme: BoardTheme, onFinish: @escaping (Int?) -> Void) {
        self.theme = theme
        self.onFinish = onFinish
    }

    /// The check with a runner already made, for tests and previews.
    init(theme: BoardTheme, runner: LevelCheckRunner, onFinish: @escaping (Int?) -> Void) {
        self.theme = theme
        self.onFinish = onFinish
        _runner = State(initialValue: runner)
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.52))
            VStack(spacing: 10) {
                RoomHeader(title: "Find my level", subtitle: subtitle) { close() }
                switch runner?.phase ?? .intro {
                case .intro:
                    intro
                case .solving, .answered:
                    if let runner { puzzle(runner, boardSide: side) }
                case .finished:
                    if let runner { result(runner) }
                }
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy, value: runner?.phase)
        .task {
            await puzzles.load()
            if runner == nil, let library = puzzles.library, !library.puzzles.isEmpty {
                runner = LevelCheckRunner(puzzles: library.puzzles)
            }
        }
        .onChange(of: runner?.phase) { _, phase in
            if phase == .finished, let runner { store?.recordLevel(runner.rating) }
        }
        .onDisappear { runner?.cancel() }
    }

    private var subtitle: String {
        guard let runner else { return "Ten puzzles, about two minutes" }
        switch runner.phase {
        case .intro: return "Ten puzzles, about two minutes"
        case .solving, .answered: return "Puzzle \(runner.number) of \(LevelEstimator.questions)"
        case .finished: return "Your result"
        }
    }

    private func close() {
        runner?.cancel()
        onFinish(runner?.phase == .finished ? runner?.rating : nil)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "scope")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(theme.trainingAccent)
                        .frame(width: 64, height: 64)
                        .background(theme.trainingAccent.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: theme.glows ? theme.trainingAccent.opacity(0.6) : .clear, radius: 12)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Find your level")
                            .font(.system(.title2, design: .themed).weight(.bold))
                        Text("A quick check so Leo starts you in the right place, and you skip what you already know.")
                            .font(.system(.subheadline, design: .themed))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        point("clock", "Ten puzzles, about two minutes")
                        point("arrow.up.arrow.down", "Harder after a solve, easier after a miss")
                        point("hand.raised", "No hints, one try each")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainingCard(theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { runner?.start() }
                } label: {
                    Text("Start")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .disabled(runner == nil)
                .opacity(runner == nil ? 0.45 : 1)
                Button {
                    onFinish(nil)
                } label: {
                    Text("Skip")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.body, design: .themed).weight(.semibold))
                .foregroundStyle(theme.trainingAccent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .themed).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Puzzles

    private func puzzle(_ runner: LevelCheckRunner, boardSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    LevelProgressBar(answered: runner.estimator.answers.count, theme: theme)
                        .padding(.horizontal, 16)
                    if let drill = runner.drill {
                        TrainingBoardView(
                            game: drill.game,
                            theme: theme,
                            flipped: drill.learner == .black,
                            onTap: runner.phase == .solving && drill.acceptsTaps
                                ? { (square: Square) in runner.tap(square) } : nil
                        )
                        .frame(width: boardSide, height: boardSide)
                        .id(ObjectIdentifier(drill))
                        .transition(.opacity)
                        TurnBadge(theme: theme, side: drill.learner,
                                  showing: runner.phase == .solving && drill.phase == .solving)
                            .padding(.top, -10)
                    }
                    RoomMessage(text: message(runner), tone: tone(runner), theme: theme)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button {
                withAnimation(.snappy) { runner.pass() }
            } label: {
                Text("Pass")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            .disabled(runner.phase != .solving)
            .opacity(runner.phase == .solving ? 1 : 0.45)
            .accessibilityHint("Counts this puzzle as missed and moves on")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func message(_ runner: LevelCheckRunner) -> String {
        switch runner.phase {
        case .answered(let solved):
            return solved ? "Solved." : "Not this one. On to the next."
        default:
            guard let drill = runner.drill else { return "" }
            if drill.phase == .solving, drill.game.moveCount > 1 { return "Good. Keep going." }
            return "Find the best move for \(drill.learner == .white ? "White" : "Black")."
        }
    }

    private func tone(_ runner: LevelCheckRunner) -> DrillRunner.Tone {
        switch runner.phase {
        case .answered(let solved): return solved ? .success : .wrong
        default: return .coach
        }
    }

    // MARK: Result

    private func result(_ runner: LevelCheckRunner) -> some View {
        let band = runner.band
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Text("Your level")
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(runner.rating)")
                            .font(.system(.largeTitle, design: .themed).weight(.bold).monospacedDigit())
                            .foregroundStyle(theme.trainingAccent)
                        Text(band.name)
                            .font(.system(.title3, design: .themed).weight(.semibold))
                        LevelBandScale(band: band, theme: theme)
                            .padding(.top, 4)
                        Text(band.advice)
                            .font(.system(.subheadline, design: .themed))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .trainingCard(theme)
                    .accessibilityElement(children: .combine)
                    Text("You solved \(runner.solved) of \(runner.estimator.answers.count). Puzzle ratings run from about 400 to 2900.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button {
                onFinish(runner.rating)
            } label: {
                Text("Start training")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Ten quiet marks that fill as the puzzles are answered. Right and wrong look the same.
private struct LevelProgressBar: View {
    let answered: Int
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<LevelEstimator.questions, id: \.self) { index in
                Capsule()
                    .fill(index < answered ? theme.trainingAccent : Color.secondary.opacity(index == answered ? 0.45 : 0.2))
                    .frame(height: 4)
            }
        }
        .animation(.snappy, value: answered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(answered) of \(LevelEstimator.questions) puzzles done")
    }
}

/// The five bands from Beginner to Expert, with the player's lit.
private struct LevelBandScale: View {
    let band: LevelBand
    let theme: BoardTheme

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(LevelBand.allCases) { item in
                    Capsule()
                        .fill(item == band ? theme.trainingAccent
                              : Color.secondary.opacity(item.rawValue < band.rawValue ? 0.45 : 0.2))
                        .frame(height: 6)
                }
            }
            HStack {
                Text(LevelBand.beginner.name)
                Spacer()
                Text(LevelBand.expert.name)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 280)
        .accessibilityHidden(true)
    }
}
