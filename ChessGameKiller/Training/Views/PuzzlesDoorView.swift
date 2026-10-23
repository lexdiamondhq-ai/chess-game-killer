import SwiftUI

/// Behind the Puzzles door: rated puzzles at the player's level up top, then the other
/// ways to play them (Rush, Cycles, Review), each with one line on why it helps.
struct PuzzlesDoorView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(TrainingStore.self) private var training
    @State private var cover: Cover?

    enum Cover: String, Identifiable {
        case rated, rush, cycles, review
        var id: String { rawValue }
    }

    var body: some View {
        TrainScreen(theme: theme, title: "Puzzles",
                    intro: "Positions from real games on Lichess, each with one winning idea to find.") {
            ratedCard
            TrainSectionTitle(text: "More ways to play")
            Button { cover = .rush } label: {
                TrainRow(symbol: "timer", title: "Puzzle Rush",
                         detail: "Three minutes, three strikes. They get harder as you go.",
                         value: puzzles.progress.rushBest > 0 ? "Best \(puzzles.progress.rushBest)" : nil, theme: theme)
            }
            .buttonStyle(.plain)
            Button { cover = .cycles } label: {
                TrainRow(symbol: "arrow.triangle.2.circlepath", title: "Cycles",
                         detail: "The Woodpecker method: the same puzzles, faster every round, until the patterns are instant.",
                         value: puzzles.cycleStatus, theme: theme)
            }
            .buttonStyle(.plain)
            Button { cover = .review } label: {
                TrainRow(symbol: "clock.arrow.circlepath", title: "Review",
                         detail: "Puzzles you missed come back just before you'd forget them.",
                         value: puzzles.reviewsDue == 0 ? "All caught up" : nil,
                         badge: puzzles.reviewsDue, theme: theme)
            }
            .buttonStyle(.plain)
            Text("Puzzles come from the Lichess database, free for everyone.")
                .font(.system(.footnote, design: .themed))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .fullScreenCover(item: $cover) { cover in
            switch cover {
            case .rated:
                PuzzlesView(theme: theme).environment(puzzles).environment(training)
            case .rush:
                PuzzlesView(theme: theme, startMode: .rush).environment(puzzles).environment(training)
            case .cycles:
                PuzzleCyclesView(theme: theme).environment(puzzles)
            case .review:
                PuzzleReviewView(theme: theme).environment(puzzles)
            }
        }
    }

    /// Rated puzzles: the rating, the streak, the theme in use, and Play.
    private var ratedCard: some View {
        let progress = puzzles.progress
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RATED")
                        .font(.system(.caption, design: .themed).weight(.bold))
                        .tracking(1)
                        .foregroundStyle(theme.trainingAccent)
                    Text("\(progress.rating)")
                        .font(.system(size: 44, weight: .bold, design: .themed).monospacedDigit())
                    Text(progress.played == 0 ? "Your puzzle rating moves with every puzzle."
                         : "Best \(progress.highestRating) · \(progress.solved) of \(progress.played) solved")
                        .font(.system(.footnote, design: .themed))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if progress.streak > 1 {
                    TrainingChip(text: "\(progress.streak) in a row", symbol: "flame.fill", color: theme.trainingAccent)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: puzzles.theme.symbol)
                    .foregroundStyle(theme.trainingAccent)
                Text(puzzles.theme.id.isEmpty ? "Every theme, picked to your level" : "Theme: \(puzzles.theme.name)")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
            }
            Button {
                cover = .rated
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
        .accessibilityElement(children: .contain)
    }
}
