import SwiftUI

// MARK: The card on the Your games door

/// Your Chess DNA in brief, at the top of the Your games door: the style, its four bars,
/// the weapon and the leak. Opens the full profile.
struct ChessDNACard: View {
    let dna: ChessDNA
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR CHESS DNA")
                    .font(.app(.caption, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Text(ChessDNAView.basis(dna))
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            DNAStyleHeader(dna: dna, theme: theme, compact: true)
            if dna.hasStyle {
                DNATraitBars(traits: dna.traits, theme: theme, compact: true)
            }
            if dna.weapon != nil || dna.leak != nil {
                HStack(alignment: .top, spacing: 10) {
                    if let weapon = dna.weapon {
                        DNAChip(label: "WEAPON", title: weapon.title, symbol: weapon.symbol,
                                tint: TrainingColor.green.color(on: theme), theme: theme)
                    }
                    if let leak = dna.leak {
                        DNAChip(label: "LEAK", title: leak.headline, symbol: leak.area.symbol,
                                tint: TrainingColor.orange.color(on: theme), theme: theme)
                    }
                }
            }
            HStack {
                Text("See your Chess DNA")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: theme.trainingAccent)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: The full profile

/// Everything the coach has learned about how the player plays: the style and its habits,
/// the weapon to sharpen and the leak to fix (each a tap from practice), whether each area
/// is getting better, what they play in the opening, and the opening to learn next.
struct ChessDNAView: View {
    let dna: ChessDNA
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @State private var session: SessionPlan?

    var body: some View {
        TrainScreen(theme: theme, title: "Your Chess DNA",
                    intro: "\(Coach.current.name) builds this from every game and puzzle you play, and updates it after each one.") {
            styleCard
            if let weapon = dna.weapon {
                weaponCard(weapon)
            }
            if let leak = dna.leak {
                leakCard(leak)
            }
            TrainSectionTitle(text: "Getting better")
            growthCard
            if !dna.openings.isEmpty {
                TrainSectionTitle(text: "Your openings")
                openingsCard
            }
            if !dna.picks.isEmpty {
                TrainSectionTitle(text: "Learn next")
                ForEach(dna.picks) { pick in
                    pickRow(pick)
                }
            }
            Text(Self.footnote(dna))
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
        .task { await puzzles.load() }
        .fullScreenCover(item: $session) { plan in
            SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(store)
                .environment(puzzles)
        }
    }

    // MARK: Words

    /// "12 games · 240 puzzles".
    static func basis(_ dna: ChessDNA) -> String {
        var parts = [dna.gamesRead == 1 ? "1 game" : "\(dna.gamesRead) games"]
        if dna.puzzlesRead > 0 { parts.append(dna.puzzlesRead == 1 ? "1 puzzle" : "\(dna.puzzlesRead) puzzles") }
        return parts.joined(separator: " · ")
    }

    static func footnote(_ dna: ChessDNA) -> String {
        let games = dna.gamesRead == 1 ? "1 game" : "\(dna.gamesRead) games"
        return "Read from \(games) against the rivals and your rated puzzles. Games against friends aren't counted."
    }

    // MARK: Style

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DNAStyleHeader(dna: dna, theme: theme, compact: false)
            if dna.hasStyle {
                DNATraitBars(traits: dna.traits, theme: theme, compact: false)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: theme.trainingAccent)
    }

    // MARK: Weapon and leak

    private func weaponCard(_ weapon: ChessDNA.Weapon) -> some View {
        let tint = TrainingColor.green.color(on: theme)
        return DNAFocusCard(label: "YOUR WEAPON", title: weapon.title, detail: weapon.detail,
                            symbol: weapon.symbol, tint: tint, theme: theme) {
            Button {
                session = puzzlePlan(PuzzleTheme.named(weapon.theme))
            } label: {
                Label("Sharpen it", systemImage: "bolt.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: tint))
        }
    }

    private func leakCard(_ leak: CoachReport.Leak) -> some View {
        let tint = TrainingColor.orange.color(on: theme)
        return DNAFocusCard(label: "WORK ON THIS FIRST", title: leak.headline, detail: leak.detail,
                            symbol: leak.area.symbol, tint: tint, theme: theme) {
            Button {
                session = leakPlan(leak)
            } label: {
                Label(leak.action, systemImage: "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
    }

    /// Real puzzles on one theme at the player's level.
    private func puzzlePlan(_ theme: PuzzleTheme) -> SessionPlan? {
        guard let library = puzzles.library, !library.puzzles.isEmpty else { return nil }
        var builder = PuzzleSessionBuilder(library: library, rating: puzzles.progress.rating,
                                           avoid: Set(puzzles.progress.recent), seed: UInt64.random(in: 1...UInt64.max))
        let plan = builder.practice(theme: theme)
        return plan.isEmpty ? nil : plan
    }

    /// The coach's own drills while the course has them for the player, puzzles after.
    private func leakPlan(_ leak: CoachReport.Leak) -> SessionPlan? {
        let past = store.isPastTheCourse(puzzleRating: puzzles.progress.rating, puzzlesPlayed: puzzles.progress.played)
        let skill = leak.skill.flatMap { store.library?.skill($0) }
        if !past, let skill, let plan = store.practicePlan(for: skill) { return plan }
        if let plan = puzzlePlan(PuzzleSessionBuilder.theme(for: leak)) { return plan }
        return skill.flatMap { store.practicePlan(for: $0) }
    }

    // MARK: Growth

    @ViewBuilder
    private var growthCard: some View {
        if dna.trends.isEmpty && dna.accuracyTrend == nil {
            Text("After \(ChessDNA.minimumTrendWindow * 2) games I can show you what's improving: your newest games against the ones before them.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trainingCard(theme)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let accuracy = dna.accuracyTrend {
                    DNATrendRow(title: "Accuracy", symbol: "scope", before: "\(accuracy.before)%", now: "\(accuracy.now)%",
                                better: accuracy.now > accuracy.before + 1, worse: accuracy.now < accuracy.before - 1,
                                higherIsBetter: true, theme: theme)
                }
                ForEach(dna.trends) { trend in
                    DNATrendRow(title: trend.area.title, symbol: trend.area.symbol,
                                before: ChessDNA.format(trend.before), now: ChessDNA.format(trend.now),
                                better: trend.improved, worse: trend.worse, theme: theme)
                }
                Text("Costly moves a game: your last games against the ones before them.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainingCard(theme)
        }
    }

    // MARK: Openings

    private var openingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(dna.openings.enumerated()), id: \.element.id) { offset, record in
                DNAOpeningRow(record: record, theme: theme)
                if offset < dna.openings.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 16)
                }
            }
        }
        .trainingCard(theme)
    }

    private func pickRow(_ pick: ChessDNA.OpeningPick) -> some View {
        NavigationLink {
            OpeningLineView(line: pick.line, theme: theme)
        } label: {
            TrainRow(symbol: pick.isTheirs ? "checkmark.seal.fill" : "book.closed.fill",
                     title: "\(pick.line.name) · \(pick.playerIsWhite ? "White" : "Black")",
                     detail: pick.reason, theme: theme)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Parts

/// The style's name and portrait, or a note that the coach is still reading.
struct DNAStyleHeader: View {
    let dna: ChessDNA
    let theme: BoardTheme
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let style = dna.style {
                TrainIcon(symbol: style.symbol, theme: theme, size: compact ? 44 : 56)
            } else {
                CoachAvatar(theme: theme, size: compact ? 44 : 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.app(compact ? .title3 : .title2, weight: .bold))
                Text(detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        dna.style?.title ?? "Still reading you"
    }

    private var detail: String {
        if let style = dna.style { return style.portrait }
        let left = max(1, ChessDNA.gamesForStyle - dna.gamesRead)
        let games = left == 1 ? "one more game" : "\(left) more games"
        return "Play \(games) against any rival and \(Coach.current.name) will name your style."
    }
}

/// The four habits as bars, each with its ends named.
struct DNATraitBars: View {
    let traits: [ChessDNA.Trait]
    let theme: BoardTheme
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            ForEach(traits) { trait in
                DNATraitBar(trait: trait, theme: theme, compact: compact)
            }
        }
    }
}

struct DNATraitBar: View {
    let trait: ChessDNA.Trait
    let theme: BoardTheme
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(trait.kind.title)
                    .font(.app(.subheadline, weight: .semibold))
                Spacer()
                Text(trait.word)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(trait.value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.trainingAccent))
            }
            track
            if !compact {
                HStack {
                    Text(trait.kind.ends.low)
                    Spacer()
                    Text(trait.kind.ends.high)
                }
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trait.kind.title): \(trait.word)")
    }

    private var track: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let value: CGFloat = CGFloat(trait.value ?? 0.5)
            let dot: CGFloat = 12
            let x: CGFloat = (width - dot) * value
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 4)
                Capsule()
                    .fill(theme.trainingAccent.opacity(0.55))
                    .frame(width: x + dot / 2, height: 4)
                    .opacity(trait.value == nil ? 0 : 1)
                Circle()
                    .fill(theme.trainingAccent)
                    .frame(width: dot, height: dot)
                    .offset(x: x)
                    .opacity(trait.value == nil ? 0.25 : 1)
            }
            .frame(height: dot)
        }
        .frame(height: 12)
    }
}

/// "WEAPON · Forks", small.
struct DNAChip: View {
    let label: String
    let title: String
    let symbol: String
    let tint: Color
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.app(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.app(.footnote, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.12)))
    }
}

/// A weapon or a leak: what it is, the evidence, and a button to practice.
struct DNAFocusCard<Action: View>: View {
    let label: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let theme: BoardTheme
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.app(.caption, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(tint)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.app(.title3, weight: .bold))
                Text(detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: tint)
        .accessibilityElement(children: .contain)
    }
}

/// One area, then and now.
struct DNATrendRow: View {
    let title: String
    let symbol: String
    let before: String
    let now: String
    let better: Bool
    let worse: Bool
    /// Accuracy goes up when it's better; costly moves go down.
    var higherIsBetter = false
    let theme: BoardTheme

    private var tint: Color {
        if better { return TrainingColor.green.color(on: theme) }
        if worse { return TrainingColor.orange.color(on: theme) }
        return .secondary
    }

    private var arrow: String {
        let up = "arrow.up.right", down = "arrow.down.right"
        if better { return higherIsBetter ? up : down }
        if worse { return higherIsBetter ? down : up }
        return "arrow.right"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.trainingAccent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.app(.subheadline, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(before)
                .font(.app(.subheadline).monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: arrow)
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(now)
                .font(.app(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(before) before, \(now) now\(better ? ", better" : worse ? ", worse" : "")")
    }
}

/// One opening the player plays: the color, the score and the accuracy.
struct DNAOpeningRow: View {
    let record: ChessDNA.OpeningRecord
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(record.playerIsWhite ? Color.white : Color.black)
                .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.family)
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text(caption)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.tally)
                .font(.app(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(record.score >= 0.5 ? AnyShapeStyle(theme.trainingAccent) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts = [record.playerIsWhite ? "As White" : "As Black", record.games == 1 ? "1 game" : "\(record.games) games"]
        if let accuracy = record.accuracy { parts.append("\(accuracy)% accuracy") }
        return parts.joined(separator: " · ")
    }
}

// MARK: After a game

/// The end of a game: one line on what the coach learned about the player from it.
struct LearnedAboutYouRow: View {
    let gameID: UUID
    let theme: BoardTheme
    @Environment(GameVault.self) private var vault: GameVault?
    @Environment(PuzzleStore.self) private var puzzles: PuzzleStore?
    @State private var line: String?

    var body: some View {
        // Always something on screen, so the task runs before there's a line to show.
        VStack(spacing: 0) {
            if let line {
                HStack(alignment: .top, spacing: 12) {
                    CoachAvatar(theme: theme, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Coach.current.name.uppercased()) LEARNED")
                            .font(.app(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(theme.trainingAccent)
                        Text(line)
                            .font(.app(.subheadline, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .trainingCard(theme, cornerRadius: 16)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
                .padding(.top, 10)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: vault?.games.count) { await read() }
    }

    private func read() async {
        guard let vault, let game = vault.game(gameID) else { return }
        let games = vault.games
        let stats = puzzles?.themeStats ?? [:]
        let id = gameID
        let learned = await Task.detached(priority: .utility) { () -> String? in
            let before = ChessDNA.make(games: games.filter { $0.id != id }, puzzleStats: stats)
            let after = ChessDNA.make(games: games, puzzleStats: stats)
            return ChessDNA.learned(before: before, after: after, game: game)
        }.value
        withAnimation(.easeOut(duration: 0.3)) { line = learned }
    }
}
