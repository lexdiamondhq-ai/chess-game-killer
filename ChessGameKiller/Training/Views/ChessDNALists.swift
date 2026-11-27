import SwiftUI

// MARK: Where you sit

/// A bar that shows where the player sits next to real players: filled up to their place,
/// with a small mark in the middle for the typical player.
struct DNAStandingBar: View {
    /// 0 to 1. Nil until there is enough to judge.
    let place: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 4)
                if let place {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, width * CGFloat(place)), height: 4)
                }
                DNATypicalMark()
                    .offset(x: width / 2 - 1)
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// The typical player's mark on a bar.
struct DNATypicalMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.primary.opacity(0.4))
            .frame(width: 2, height: 10)
    }
}

/// "▏ the typical player", under a set of bars.
struct DNATypicalLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            DNATypicalMark()
            Text("The typical player, from \(RealPlayers.players) real players")
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension RealPlayers.Standing {
    /// Green ahead of most players, orange behind them, the page's accent in between.
    func tint(on theme: BoardTheme) -> Color {
        if isAhead { return TrainingColor.green.color(on: theme) }
        if isBehind { return TrainingColor.orange.color(on: theme) }
        return theme.trainingAccent
    }
}

// MARK: The two lists

/// A list's title with a quiet note at the right: "YOU ARE GOOD AT · from your last 20 games".
struct DNAListTitle: View {
    let text: String
    var note: String?
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.carved(12))
                .tracking(1.4)
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}

/// One line of a list: a small sign, a title, the proof under it, and what to do at the right.
struct DNAListRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A small rounded button at the end of a line: gold when it is the thing to do, an outline
/// when it is one way among others.
struct DNAPillStyle: ButtonStyle {
    let theme: BoardTheme
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.footnote, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(theme.trainingAccent))
            .background {
                if prominent {
                    Capsule().fill(theme.trainingAccent)
                } else {
                    Capsule().strokeBorder(theme.trainingAccent.opacity(0.6), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// What the player is good at, each with its proof. A line with places in their games to
/// show opens them; one with only puzzles behind it starts a run of those.
struct DNAStrengthList: View {
    let strengths: [ChessDNA.Strength]
    let theme: BoardTheme
    /// Starts puzzles on a strength's theme.
    let sharpen: (ChessDNA.Strength) -> Void

    private var tint: Color { TrainingColor.green.color(on: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(strengths.enumerated()), id: \.element.id) { offset, strength in
                row(strength)
                if offset < strengths.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 56)
                }
            }
        }
        .trainingCard(theme)
    }

    @ViewBuilder
    private func row(_ strength: ChessDNA.Strength) -> some View {
        if !strength.sightings.isEmpty {
            NavigationLink {
                DNAProofView(strength: strength, theme: theme)
            } label: {
                DNAListRow(symbol: "checkmark", title: strength.title, detail: strength.detail, tint: tint) {
                    go("See them")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows where in your games")
        } else if strength.theme != nil {
            Button {
                sharpen(strength)
            } label: {
                DNAListRow(symbol: "checkmark", title: strength.title, detail: strength.detail, tint: tint) {
                    go("Sharpen")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts puzzles of this kind")
        } else {
            DNAListRow(symbol: "checkmark", title: strength.title, detail: strength.detail, tint: tint) {
                EmptyView()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func go(_ words: String) -> some View {
        HStack(spacing: 4) {
            Text(words)
                .font(.app(.footnote, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.app(.caption2, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(theme.trainingAccent)
        .fixedSize()
    }
}

/// What to work on, the biggest gap first, each with its own way to practice: the player's
/// own positions of that kind first when there are some.
struct DNAWeakSpotList: View {
    let spots: [CoachReport.Leak]
    let theme: BoardTheme
    /// How many of the player's own positions wait for each.
    let waiting: (CoachReport.Leak) -> Int
    let practice: (CoachReport.Leak) -> Void

    private var tint: Color { TrainingColor.orange.color(on: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(spots.enumerated()), id: \.element.id) { offset, spot in
                DNAListRow(symbol: "exclamationmark", title: spot.headline, detail: spot.proof, tint: tint) {
                    action(spot)
                }
                .accessibilityElement(children: .contain)
                if offset < spots.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 56)
                }
            }
        }
        .trainingCard(theme)
    }

    /// Their own positions when some wait. With none: puzzles or Leo's drills of that kind,
    /// or the Endgames or Calculation room when that is where the work is.
    @ViewBuilder
    private func action(_ spot: CoachReport.Leak) -> some View {
        let own = waiting(spot)
        if own > 0 {
            Button("Practice \(own)") { practice(spot) }
                .buttonStyle(DNAPillStyle(theme: theme))
                .accessibilityLabel("Practice \(spot.headline.lowercased())")
                .accessibilityHint(own == 1 ? "Starts with 1 position from your games"
                                            : "Starts with \(min(own, SessionPlan.ownPositionLimit)) positions from your games")
        } else if spot.area == .endgames {
            NavigationLink(value: TrainDoor.endgames) { Text("Train") }
                .buttonStyle(DNAPillStyle(theme: theme, prominent: false))
                .accessibilityLabel(spot.action)
        } else if spot.area == .calculation {
            NavigationLink(value: TrainDoor.calculation) { Text("Train") }
                .buttonStyle(DNAPillStyle(theme: theme, prominent: false))
                .accessibilityLabel(spot.action)
        } else {
            Button("Practice") { practice(spot) }
                .buttonStyle(DNAPillStyle(theme: theme, prominent: false))
                .accessibilityLabel(spot.action)
        }
    }
}

// MARK: The proof

/// Where a strength showed in the player's games: each place opens that game at that move.
struct DNAProofView: View {
    let strength: ChessDNA.Strength
    let theme: BoardTheme
    @Environment(GameVault.self) private var vault
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @State private var opened: Opened?
    @State private var session: SessionPlan?

    /// A game open at one move.
    private struct Opened: Identifiable {
        let game: SavedGame
        let ply: Int

        var id: String { "\(game.id.uuidString)-\(ply)" }
    }

    /// The places whose game is still kept.
    private var places: [Opened] {
        strength.sightings.compactMap { sighting in
            vault.game(sighting.game).map { Opened(game: $0, ply: sighting.ply) }
        }
    }

    var body: some View {
        TrainScreen(theme: theme, title: strength.title, intro: strength.detail) {
            let shown = places
            if shown.isEmpty {
                Text("These games aren't kept anymore.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainingCard(theme)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { offset, place in
                        Button {
                            opened = place
                        } label: {
                            row(place)
                        }
                        .buttonStyle(.plain)
                        if offset < shown.count - 1 {
                            Divider().opacity(0.4).padding(.leading, 16)
                        }
                    }
                }
                .trainingCard(theme)
            }
            if let id = strength.theme {
                Button {
                    session = puzzlePlan(PuzzleTheme.named(id))
                } label: {
                    Label("Sharpen it", systemImage: "bolt.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: TrainingColor.green.color(on: theme)))
                .padding(.top, 6)
            }
        }
        .task { await puzzles.load() }
        .fullScreenCover(item: $opened) { place in
            // The position before the move, so the next step forward plays it.
            RewindView(game: place.game, theme: theme, startAt: max(0, place.ply - 1))
                .environment(vault)
                .environment(store)
        }
        .fullScreenCover(item: $session) { plan in
            SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(store)
                .environment(puzzles)
        }
    }

    private func row(_ place: Opened) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.game.opponentShown)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(Self.caption(place.game, ply: place.ply))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the game there")
    }

    /// "Move 14 · Win · 3 days ago", or without the move for a whole game.
    static func caption(_ game: SavedGame, ply: Int) -> String {
        var parts = [game.result.title, game.date.formatted(.relative(presentation: .named))]
        if ply > 0 { parts.insert("Move \((ply + 1) / 2)", at: 0) }
        return parts.joined(separator: " · ")
    }

    /// Real puzzles on one theme at the player's level.
    private func puzzlePlan(_ theme: PuzzleTheme) -> SessionPlan? {
        guard let library = puzzles.library, !library.puzzles.isEmpty else { return nil }
        var builder = PuzzleSessionBuilder(library: library, rating: puzzles.progress.rating,
                                           avoid: Set(puzzles.progress.recent), seed: UInt64.random(in: 1...UInt64.max))
        let plan = builder.practice(theme: theme)
        return plan.isEmpty ? nil : plan
    }
}
