import SwiftUI

/// Behind the Calculation door: seeing moves in your head, seeing the whole board at a
/// glance, and thinking like the masters.
struct CalculationDoorView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(TrainingStore.self) private var training
    @Environment(ThinkStore.self) private var think
    @AppStorage(CalculationView.bestStreakKey) private var calculationBest = 0
    @State private var cover: Cover?

    /// The board vision drills' bests, shared with their screens.
    private var vision: VisionStore { .live() }

    enum Cover: String, Identifiable {
        case blindfold, candidates, coordinates, scan
        var id: String { rawValue }
    }

    var body: some View {
        TrainScreen(theme: theme, title: "Calculation",
                    intro: "Strong players see further and miss less. These train exactly that.") {
            TrainSectionTitle(text: "In your head")
            Button { cover = .candidates } label: {
                TrainRow(symbol: "list.number", title: "Candidate moves",
                         detail: "Name your best two or three moves before you choose. \(Coach.current.name) shows what you missed.",
                         value: think.progress.rounds > 0 ? "Best \(think.progress.bestRound)" : nil, theme: theme)
            }
            .buttonStyle(.plain)
            Button { cover = .blindfold } label: {
                TrainRow(symbol: "eye.slash.fill", title: "See ahead",
                         detail: "The moves are read out but the pieces stay still. Play them in your head, then find the winner. Blindfold hides the pieces too.",
                         value: calculationBest > 1 ? "Best \(calculationBest)" : nil, theme: theme)
            }
            .buttonStyle(.plain)

            TrainSectionTitle(text: "Board vision")
            Button { cover = .scan } label: {
                TrainRow(symbol: "viewfinder", title: "Board scan",
                         detail: "Find every check, capture and threat. The Traffic Light, until it's automatic.",
                         value: vision.scanStatus, theme: theme)
            }
            .buttonStyle(.plain)
            Button { cover = .coordinates } label: {
                TrainRow(symbol: "square.grid.3x3.topleft.filled", title: "Coordinates",
                         detail: "Know every square at a glance. Thirty seconds, as many as you can.",
                         value: vision.coordinatesStatus, theme: theme)
            }
            .buttonStyle(.plain)

            TrainSectionTitle(text: "Like a grandmaster")
            NavigationLink {
                GuessTheMoveList(theme: theme)
            } label: {
                TrainRow(symbol: "person.fill.questionmark", title: "Guess the Move",
                         detail: "Sit in a grandmaster's chair. Guess every move of a famous game and get scored against the master.",
                         value: "\(GrandmasterContent.shared.games.count) games", theme: theme)
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $cover) { cover in
            switch cover {
            case .blindfold:
                CalculationView(theme: theme).environment(puzzles).environment(training)
            case .candidates:
                CandidateMovesView(theme: theme).environment(puzzles).environment(think)
            case .coordinates:
                CoordinatesView(theme: theme)
            case .scan:
                BoardScanView(theme: theme).environment(puzzles)
            }
        }
    }
}

/// The famous games to play through as the master.
struct GuessTheMoveList: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var training
    @State private var game: ClassicGame?
    /// Bumped when a game closes, so its new best shows at once.
    @State private var finished = 0

    var body: some View {
        TrainScreen(theme: theme, title: "Guess the Move",
                    intro: "Pick a game and a side. Guess each of the master's moves; the closer your guess, the more points.") {
            VStack(spacing: 0) {
                ForEach(Array(GrandmasterContent.shared.games.enumerated()), id: \.element.id) { index, game in
                    Button {
                        self.game = game
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text("\(game.event) \(String(game.year)) · as \(game.hero == .white ? "White" : "Black")")
                                    .font(.system(.caption, design: .themed))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if let best = GuessRunner.best(for: game.id) {
                                Text("Best \(best)%")
                                    .font(.system(.caption, design: .themed).weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < GrandmasterContent.shared.games.count - 1 {
                        Divider().opacity(0.4).padding(.leading, 16)
                    }
                }
            }
            .trainingCard(theme)
            .id(finished)
        }
        .fullScreenCover(item: $game, onDismiss: { finished += 1 }) { game in
            GuessTheMoveView(game: game, theme: theme)
                .environment(training)
        }
    }
}
