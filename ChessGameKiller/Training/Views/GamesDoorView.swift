import SwiftUI

/// Behind the "Your games" door: what Coach Leo sees in the player's own games, what they
/// are good at and what to work on (each a tap from practice), the positions from those
/// games still to fix, and the games themselves to rewind.
struct GamesDoorView: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(GameVault.self) private var vault
    @State private var report: CoachReport?
    @State private var dna: ChessDNA?
    @State private var session: SessionPlan?
    @State private var rewinding: SavedGame?
    @State private var showingAllGames = false

    /// Recent games shown here; the rest are a tap away.
    private static let recentCount = 3

    var body: some View {
        TrainScreen(theme: theme, title: "Chess DNA",
                    intro: "\(Coach.current.title) reads every move of your recent games and finds where the points go.") {
            // The full Chess DNA is Premium's; the top weakness below stays free. So does the
            // card itself, the one Home shows every player: Home's card opens this page, and a
            // free player used to find their style gone here (inspection, 2026-11-14).
            if let dna, dna.gamesRead > 0 {
                if Premium.shared.opens(.coachProfile) {
                    NavigationLink {
                        ChessDNAView(dna: dna, theme: theme)
                    } label: {
                        ChessDNACard(dna: dna, theme: theme)
                    }
                    .buttonStyle(.plain)
                } else {
                    ChessDNACard(dna: dna, theme: theme, opens: false)
                }
            }
            if let report {
                if report.hasEnough {
                    // The top weakness is free; the strengths, the rest of the list and the
                    // whole six-area profile are Premium's.
                    let whole = Premium.shared.opens(.coachProfile)
                    if whole, let dna {
                        strengths(dna)
                    }
                    weakSpots(whole ? report.weakSpots : Array(report.weakSpots.prefix(1)))
                    if whole {
                        CoachReportCard(report: report, theme: theme)
                    } else {
                        PremiumLimitCard(feature: .coachProfile, accent: theme.trainingAccent)
                    }
                } else if (dna?.gamesRead ?? 0) == 0 || !Premium.shared.opens(.coachProfile) {
                    waitingCard(gamesRead: report.gamesRead)
                }
            }
            TrainSectionTitle(text: "Games you play online")
            ImportGamesRow(theme: theme)
            if !store.openMistakes.isEmpty {
                TrainSectionTitle(text: "From your games")
                fixRow
            }
            if !vault.games.isEmpty {
                TrainSectionTitle(text: "Recent games")
                recentGames
            }
        }
        .task(id: readKey) {
            let games = vault.games
            let stats = puzzles.themeStats
            let played = puzzles.progress.played
            let profile = await Task.detached(priority: .userInitiated) {
                ChessDNA.make(games: games, puzzleStats: stats, puzzlesPlayed: played)
            }.value
            dna = profile
            report = profile.report
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

    /// Changes when there is something new to read: a game saved, or a game against a person
    /// that has just been graded (that happens a little after it ends, sometimes with this page open).
    private var readKey: String {
        let read: Int = vault.games.filter { $0.graded == true }.count
        return "\(vault.games.count) \(read)"
    }

    // MARK: Good at, and to work on

    /// What the player is good at, with proof. Until something stands out, one line says so.
    @ViewBuilder
    private func strengths(_ dna: ChessDNA) -> some View {
        DNAListTitle(text: "You are good at", note: Self.basis(dna.report),
                     tint: TrainingColor.green.color(on: theme))
        if dna.strengths.isEmpty {
            Text("Nothing stands out yet. A few more games and \(Coach.current.name) will have proof.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trainingCard(theme)
        } else {
            DNAStrengthList(strengths: dna.strengths, theme: theme) { strength in
                session = strength.theme.flatMap { puzzlePlan(PuzzleTheme.named($0)) }
            }
        }
    }

    /// What to work on, the biggest gap first. A free player sees the first one.
    @ViewBuilder
    private func weakSpots(_ spots: [CoachReport.Leak]) -> some View {
        if !spots.isEmpty {
            DNAListTitle(text: spots.count == 1 ? "Work on this first" : "Work on these",
                         note: spots.count == 1 ? nil : "biggest gap first",
                         tint: TrainingColor.orange.color(on: theme))
            DNAWeakSpotList(spots: spots, theme: theme) { spot in
                SessionPlan.ownPositions(for: spot, in: store.openMistakes).count
            } practice: { spot in
                session = SessionPlan.practice(spot, mistakes: store.openMistakes, more: practicePlan(for: spot))
            }
            Text("Practice starts with your own positions from your games, then puzzles of the same kind.")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// "from your last 20 games".
    private static func basis(_ report: CoachReport) -> String {
        report.gamesRead == 1 ? "from your last game" : "from your last \(report.gamesRead) games"
    }

    /// Real puzzles on one theme at the player's level.
    private func puzzlePlan(_ theme: PuzzleTheme) -> SessionPlan? {
        guard let library = puzzles.library, !library.puzzles.isEmpty else { return nil }
        var builder = PuzzleSessionBuilder(library: library, rating: puzzles.progress.rating,
                                           avoid: Set(puzzles.progress.recent),
                                           seed: UInt64.random(in: 1...UInt64.max))
        let plan = builder.practice(theme: theme)
        return plan.isEmpty ? nil : plan
    }

    /// More of the same kind: Coach Leo's drills while the course still has them for the
    /// player, real puzzles on the same idea once they're past it.
    private func practicePlan(for leak: CoachReport.Leak) -> SessionPlan? {
        let pastTheCourse = store.isPastTheCourse(puzzleRating: puzzles.progress.rating,
                                                  puzzlesPlayed: puzzles.progress.played)
        if !pastTheCourse, let id = leak.skill, let skill = store.library?.skill(id),
           let plan = store.practicePlan(for: skill) {
            return plan
        }
        if let plan = puzzlePlan(PuzzleSessionBuilder.theme(for: leak)) { return plan }
        return leak.skill.flatMap { store.library?.skill($0) }.flatMap { store.practicePlan(for: $0) }
    }

    private func waitingCard(gamesRead: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachAvatar(theme: theme, size: 40)
            Text(gamesRead == 0 ? "Play a game and I'll read it" : "A couple more games")
                .font(.display(.title3, weight: .semibold))
            Text(gamesRead == 0
                 ? "Play any rival. I'll look at every move you make and show you where your points go, and how to win them back."
                 : "I've read \(gamesRead == 1 ? "one game" : "\(gamesRead) games") so far. After a few longer ones I can tell you what's really costing you.")
                .font(.app(.subheadline))
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
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.trainingAccent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.app(.caption, weight: .bold))
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

    private var rival: Rival? { Rival.of(saved: game) }

    var body: some View {
        HStack(spacing: 12) {
            portrait
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(game.opponentShown)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(game.result.title)
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(game.result == .win ? theme.trainingAccent : Color.secondary)
                }
                Text(detail)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if game.leftToRewrite > 0 {
                Text("\(game.leftToRewrite) to fix")
                    .font(.app(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.app(.caption, weight: .bold))
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
            RivalCoin(rival: rival, size: 34)
        } else {
            Image(systemName: game.isImported ? "globe" : "person.2.fill")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .accessibilityHidden(true)
        }
    }
}

/// Coach Leo's report on the player's games: six areas, each a bar that shows where the
/// player sits next to real players, with a mark for the typical one.
struct CoachReportCard: View {
    let report: CoachReport
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("WHAT \(Coach.current.name.uppercased()) SEES")
                    .font(.app(.caption, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Text(report.gamesRead == 1 ? "Your last game" : "Your last \(report.gamesRead) games")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(report.scores) { score in
                    row(score)
                }
            }
            if report.isCompared {
                DNATypicalLegend()
            } else {
                // Too few games to say where the player sits: the bars wait, and say for what.
                Text("\(Coach.current.name) puts you next to real players after \(CoachReport.gamesToCompare) games. \(report.gamesLeftToCompare) to go.")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .trainingCard(theme)
    }

    private func row(_ score: CoachReport.Score) -> some View {
        let isLeak = report.leak?.area == score.area
        let standing = score.standing
        let tint = standing?.tint(on: theme) ?? theme.trainingAccent
        // Words in the bar's color once the player is clearly on one side of most players.
        let stands = standing?.isAhead == true || standing?.isBehind == true
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: score.area.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(score.area.title)
                    .font(.app(.subheadline, weight: isLeak ? .bold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(score.verdict)
                    .font(.app(.caption, weight: stands ? .bold : .medium))
                    .foregroundStyle(stands ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            DNAStandingBar(place: standing?.place, tint: tint)
                .opacity(standing == nil ? 0.35 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score.area.title): \(score.verdict)\(isLeak ? ", work on this first" : "")")
    }
}
