import SwiftUI

/// Behind the "Your games" door: what Coach Leo sees in the player's own games, the one
/// thing to work on first, the positions from those games still to fix, and the games
/// themselves to rewind.
struct GamesDoorView: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(GameVault.self) private var vault
    @State private var report: CoachReport?
    @State private var session: SessionPlan?
    @State private var rewinding: SavedGame?
    @State private var showingAllGames = false

    /// Recent games shown here; the rest are a tap away.
    private static let recentCount = 3

    var body: some View {
        TrainScreen(theme: theme, title: "Your games",
                    intro: "\(Coach.current.title) reads every move of your recent games and finds where the points go.") {
            if let report {
                if report.hasEnough {
                    // The top weakness is free; the whole six-area profile is Premium's.
                    if Premium.shared.opens(.coachProfile) {
                        CoachReportCard(report: report, theme: theme)
                    }
                    if let leak = report.leak {
                        leakCard(leak)
                    }
                    if !Premium.shared.opens(.coachProfile) {
                        PremiumLimitCard(feature: .coachProfile, accent: theme.trainingAccent)
                    }
                } else {
                    waitingCard(gamesRead: report.gamesRead)
                }
            }
            if !store.openMistakes.isEmpty {
                TrainSectionTitle(text: "From your games")
                fixRow
            }
            if !vault.games.isEmpty {
                TrainSectionTitle(text: "Recent games")
                recentGames
            }
        }
        .task(id: vault.games.count) {
            let games = vault.games
            report = await Task.detached(priority: .userInitiated) { CoachReport.make(games: games) }.value
            await puzzles.load()
        }
        .fullScreenCover(item: $session) { plan in
            SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(store)
                .environment(puzzles)
        }
        .fullScreenCover(item: $rewinding) { game in
            RewindView(game: game, theme: theme)
                .environment(vault)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showingAllGames) {
            RewindGamesView(theme: theme)
                .environment(vault)
                .environment(store)
        }
    }

    // MARK: The leak

    private func leakCard(_ leak: CoachReport.Leak) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: leak.area.symbol)
                    .font(.system(size: 13, weight: .bold))
                Text("WORK ON THIS FIRST")
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .tracking(1)
            }
            .foregroundStyle(theme.trainingAccent)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text(leak.headline)
                    .font(.system(.title3, design: .themed).weight(.bold))
                Text(leak.detail)
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            leakAction(leak)
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
        .accessibilityElement(children: .contain)
    }

    /// Practice for the leak: Coach Leo's drills while the course still has them for
    /// the player, real puzzles on the same idea once they're past it, and the
    /// Endgames or Calculation door when that's where the work is.
    @ViewBuilder
    private func leakAction(_ leak: CoachReport.Leak) -> some View {
        switch leak.area {
        case .endgames:
            NavigationLink(value: TrainDoor.endgames) {
                Label(leak.action, systemImage: TrainDoor.endgames.symbol)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        case .calculation:
            NavigationLink(value: TrainDoor.calculation) {
                Label(leak.action, systemImage: TrainDoor.calculation.symbol)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        default:
            Button {
                session = practicePlan(for: leak)
            } label: {
                Label(leak.action, systemImage: "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
    }

    private func practicePlan(for leak: CoachReport.Leak) -> SessionPlan? {
        let pastTheCourse = store.isPastTheCourse(puzzleRating: puzzles.progress.rating,
                                                  puzzlesPlayed: puzzles.progress.played)
        if !pastTheCourse, let id = leak.skill, let skill = store.library?.skill(id),
           let plan = store.practicePlan(for: skill) {
            return plan
        }
        if let library = puzzles.library, !library.puzzles.isEmpty {
            var builder = PuzzleSessionBuilder(library: library, rating: puzzles.progress.rating,
                                               avoid: Set(puzzles.progress.recent),
                                               seed: UInt64.random(in: 1...UInt64.max))
            let plan = builder.practice(theme: PuzzleSessionBuilder.theme(for: leak))
            if !plan.isEmpty { return plan }
        }
        return leak.skill.flatMap { store.library?.skill($0) }.flatMap { store.practicePlan(for: $0) }
    }

    private func waitingCard(gamesRead: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachAvatar(theme: theme, size: 40)
            Text(gamesRead == 0 ? "Play a game and I'll read it" : "A couple more games")
                .font(.system(.title3, design: .themed).weight(.bold))
            Text(gamesRead == 0
                 ? "Play any rival. I'll look at every move you make and show you where your points go, and how to win them back."
                 : "I've read \(gamesRead == 1 ? "one game" : "\(gamesRead) games") so far. After a few longer ones I can tell you what's really costing you.")
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme)
        .accessibilityElement(children: .combine)
    }

    // MARK: Mistakes to fix

    private var fixRow: some View {
        let open = store.openMistakes.count
        let due = store.dueMistakeCount
        return Button {
            session = store.mistakesPlan()
        } label: {
            TrainRow(symbol: "arrow.uturn.backward", title: "Fix your mistakes",
                     detail: "Positions from your games where a better move was there. Solve one cleanly on three different days and it's fixed for good.",
                     value: due == 0 ? "\(open) saved" : nil, badge: due, theme: theme)
        }
        .buttonStyle(.plain)
        .accessibilityHint(due > 0 ? "\(due) due today" : "\(open) saved")
    }

    // MARK: Games

    private var recentGames: some View {
        VStack(spacing: 0) {
            ForEach(vault.games.prefix(Self.recentCount)) { game in
                Button {
                    rewinding = game
                } label: {
                    RecentGameRow(game: game, theme: theme)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.4).padding(.leading, 62)
            }
            Button {
                showingAllGames = true
            } label: {
                HStack {
                    Text(vault.games.count > Self.recentCount ? "All \(vault.games.count) games" : "Open Rewind")
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .foregroundStyle(theme.trainingAccent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .trainingCard(theme)
    }
}

/// One game in a short list: the rival, the result, the accuracy and what's left to fix.
struct RecentGameRow: View {
    let game: SavedGame
    let theme: BoardTheme

    private var rival: Rival? { game.level.flatMap(MatchController.Level.init(rawValue:))?.rival }

    var body: some View {
        HStack(spacing: 12) {
            portrait
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(game.opponent)
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(game.result.title)
                        .font(.system(.caption, design: .themed).weight(.bold))
                        .foregroundStyle(game.result == .win ? theme.trainingAccent : Color.secondary)
                }
                Text(detail)
                    .font(.system(.caption, design: .themed))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if game.leftToRewrite > 0 {
                Text("\(game.leftToRewrite) to fix")
                    .font(.system(.caption, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Rewinds the game")
    }

    private var detail: String {
        var parts = ["\(game.moveCount) moves", game.date.formatted(.relative(presentation: .named))]
        if let accuracy = game.accuracy { parts.insert("\(accuracy)% accuracy", at: 0) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var portrait: some View {
        if let rival {
            Image(rival.portraitName)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.2.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .accessibilityHidden(true)
        }
    }
}

/// Coach Leo's report on the player's games: six areas, each with a bar and a word.
struct CoachReportCard: View {
    let report: CoachReport
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("WHAT LEO SEES")
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Text(report.gamesRead == 1 ? "Your last game" : "Your last \(report.gamesRead) games")
                    .font(.system(.footnote, design: .themed))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(report.scores) { score in
                    row(score)
                }
            }
        }
        .padding(18)
        .trainingCard(theme)
    }

    private func row(_ score: CoachReport.Score) -> some View {
        let isLeak = report.leak?.area == score.area
        return HStack(spacing: 10) {
            Image(systemName: score.area.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.trainingAccent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(score.area.title)
                .font(.system(.subheadline, design: .themed).weight(isLeak ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .leading)
            ProgressView(value: score.value ?? 0)
                .tint(theme.trainingAccent)
                .opacity(score.value == nil ? 0.35 : 1)
                .accessibilityHidden(true)
            Text(score.verdict)
                .font(.system(.caption, design: .themed).weight(isLeak ? .bold : .medium))
                .foregroundStyle(isLeak ? AnyShapeStyle(theme.trainingAccent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 78, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score.area.title): \(score.verdict)\(isLeak ? ", work on this first" : "")")
    }
}
