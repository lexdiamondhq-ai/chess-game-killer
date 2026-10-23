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
                         detail: "Sit in a grandmaster's chair. Guess every move of a famous classic or a recent top game and get scored against the master.",
                         value: "\(GrandmasterContent.shared.games.count + GrandmasterContent.shared.masterGames.count) games",
                         theme: theme)
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

/// The games to play through as the master: hand-picked classics, and recent top games
/// from the Lichess broadcasts that can be searched by player, event or opening.
struct GuessTheMoveList: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var training
    @State private var game: ClassicGame?
    @State private var shelf: Shelf = .classics
    @State private var query = ""
    /// Bumped when a game closes, so its new best shows at once.
    @State private var finished = 0

    enum Shelf: String, CaseIterable, Identifiable {
        case classics = "Classics"
        case masters = "Master games"
        var id: String { rawValue }
    }

    private var content: GrandmasterContent { .shared }

    private var shown: [ClassicGame] {
        let games = shelf == .classics ? content.games : content.masterGames
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return games }
        return games.filter { game in
            let text = [game.white, game.black, game.event, game.opening ?? "", String(game.year)].joined(separator: " ")
            return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        TrainScreen(theme: theme, title: "Guess the Move",
                    intro: "Pick a game. Guess each of the winner's moves; the closer your guess, the more points.") {
            if !content.masterGames.isEmpty {
                Picker("Games", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if shelf == .masters {
                    Text("\(content.masterGames.count) recent classical games between players rated 2500 and up, from top tournaments.")
                        .font(.system(.footnote, design: .themed))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            let games = shown
            if games.isEmpty {
                Text("No game matches \u{201C}\(query)\u{201D}.")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                GuessGameRows(games: games, theme: theme) { self.game = $0 }
                    .id(finished)
            }
        }
        .searchable(text: $query, prompt: "Player, event or opening")
        .fullScreenCover(item: $game, onDismiss: { finished += 1 }) { game in
            GuessTheMoveView(game: game, theme: theme)
                .environment(training)
        }
    }
}

/// Games to guess, one row each: the players, where and when, and the best score so far.
struct GuessGameRows: View {
    let games: [ClassicGame]
    let theme: BoardTheme
    let onPick: (ClassicGame) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                Button {
                    onPick(game)
                } label: {
                    GuessGameRow(game: game)
                }
                .buttonStyle(.plain)
                if index < games.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 16)
                }
            }
        }
        .trainingCard(theme)
    }
}

private struct GuessGameRow: View {
    let game: ClassicGame

    private var detail: String {
        let side = "as \(game.hero == .white ? "White" : "Black")"
        if let opening = game.opening {
            return "\(opening.split(separator: ":").first ?? "") · \(side)"
        }
        return "\(game.playedAt) · \(side)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if game.isMasterGame {
                    Text(game.playedAt)
                        .font(.system(.caption, design: .themed))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
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
}
