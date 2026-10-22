import ChessKit
import SwiftUI

/// Everything the home screen can open. The game screen owns the sheets and covers;
/// the home only asks for them.
struct HomeActions {
    var play: () -> Void = {}
    var resume: () -> Void = {}
    var analyze: () -> Void = {}
    var train: () -> Void = {}
    var puzzles: () -> Void = {}
    var rewind: () -> Void = {}
    var openGame: (SavedGame) -> Void = { _ in }
    var army: () -> Void = {}
    var settings: () -> Void = {}
}

/// The home screen: the 3D board as a hero picture at the top, a card with the week's
/// games over its foot, then a page of cards, one for every part of the app. As the page
/// scrolls the board lifts away slower than the cards, darkens and sinks into the black;
/// the top buttons fade with it, and a dark veil gathers under the status bar.
struct HomeView: View {
    let match: MatchController
    let theme: BoardTheme
    let actions: HomeActions

    @Environment(GameVault.self) private var vault
    @Environment(ArmyStore.self) private var army
    @Environment(TrainingStore.self) private var training
    @Environment(PuzzleStore.self) private var puzzles

    /// How far the page has scrolled; negative while pulled down past the top.
    @State private var offset: CGFloat = 0

    private static let space = "home-scroll"

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let heroHeight = min(max(geo.size.width * 1.2, 440), 620) + safeTop * 0.3
            ZStack(alignment: .top) {
                HomePalette.background.ignoresSafeArea()
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.frame(in: .named(Self.space)).minY
                            } action: { minY in
                                offset = -minY
                            }
                        HomeHero(look: theme.sculptedLook ?? .gilded, pieces: heroPieces,
                                 height: heroHeight, offset: offset)
                        content
                            .padding(.top, -112)
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: Self.space)
                .ignoresSafeArea(edges: .top)

                topBar
                    .padding(.top, safeTop + 4)
                    .opacity(Double(1 - min(max(offset / 90, 0), 1)))
                    .offset(y: -min(max(offset, 0), 90) * 0.35)
                    .allowsHitTesting(offset < 60)

                statusVeil(height: safeTop + 28)
                    .opacity(Double(min(max((offset - heroHeight * 0.45) / 120, 0), 1)))
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                HomeTabBar(actions: actions)
                    .padding(.horizontal, 20)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom > 0 ? 0 : 12, 0))
            }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(HomePalette.amber)
    }

    /// The pieces the hero shows: the game being played, or the start of one.
    private var heroPieces: [Piece] {
        match.game.pieces.map(\.piece)
    }

    // MARK: Page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeWeekCard(games: vault.games, streak: training.streak)
                .padding(.horizontal, HomePalette.gutter)

            if gameInProgress {
                sectionTitle("Your game")
                HomeResumeCard(match: match, action: actions.resume)
                    .padding(.horizontal, HomePalette.gutter)
            }

            sectionTitle("Play now")
            HomeRivalCard(rival: nextRival.rival, record: record(against: nextRival),
                          grudge: army.grudge(against: nextRival) != nil, action: actions.play)
                .padding(.horizontal, HomePalette.gutter)

            sectionTitle("Sharpen up")
            VStack(spacing: 12) {
                HomeCoachCard(minutes: training.todaysMinutes, focus: training.todaysFocus?.title,
                              streak: training.streak, trainedToday: training.trainedToday, action: actions.train)
                HomeRowCard(symbol: "puzzlepiece.extension.fill", title: "Puzzles",
                            detail: "Rating \(puzzles.progress.rating.formatted()) · \(puzzles.progress.streak) solved in a row",
                            action: actions.puzzles)
                HomeRowCard(symbol: "camera.viewfinder", title: "Analyze a position",
                            detail: "Snap a real board or set one up, see the best move",
                            action: actions.analyze)
            }
            .padding(.horizontal, HomePalette.gutter)

            sectionTitle("Your army")
            HomeArmyCard(army: army, theme: theme, action: actions.army)
                .padding(.horizontal, HomePalette.gutter)

            sectionTitle("Rewind", trailing: vault.games.isEmpty ? nil : "View all", trailingAction: actions.rewind)
            HomeRewindStrip(games: Array(vault.games.prefix(8)), open: actions.openGame, openAll: actions.rewind)

            Color.clear.frame(height: 128)
        }
    }

    private func sectionTitle(_ title: String, trailing: String? = nil, trailingAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(HomePalette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing, let trailingAction {
                Button(trailing, action: trailingAction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.amber)
            }
        }
        .padding(.horizontal, HomePalette.gutter + 2)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    // MARK: Top

    /// Your army on the left; puzzle rating and Settings on the right, in frosted pills.
    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: actions.army) {
                HStack(spacing: 8) {
                    PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 26)
                        .frame(width: 34, height: 34)
                        .background(HomePalette.amberDeep.opacity(0.7), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your army")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HomePalette.text.opacity(0.7))
                        Text(armyRankLine)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(HomePalette.text)
                    }
                    .padding(.trailing, 6)
                }
                .padding(4)
                .homeGlass(Capsule())
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("Your army, \(armyRankLine)")

            Spacer(minLength: 0)

            Button(action: actions.puzzles) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HomePalette.amber)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Puzzle rating")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HomePalette.text.opacity(0.7))
                        Text(puzzles.progress.rating.formatted())
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(HomePalette.text)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .homeGlass(Capsule())
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("Puzzle rating \(puzzles.progress.rating)")

            Button(action: actions.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HomePalette.text)
                    .frame(width: 42, height: 42)
                    .homeGlass(Circle())
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, HomePalette.gutter)
    }

    /// A dark veil under the status bar once the cards scroll beneath it.
    private func statusVeil(height: CGFloat) -> some View {
        LinearGradient(stops: [
            .init(color: HomePalette.background, location: 0),
            .init(color: HomePalette.background.opacity(0.92), location: 0.55),
            .init(color: HomePalette.background.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    // MARK: Reading

    private var gameInProgress: Bool {
        match.hasStarted && !match.isOver && match.game.moveCount > 0
    }

    /// The rival the player picked last time.
    private var nextRival: MatchController.Level {
        NewGameSheet.savedSetup().level
    }

    private func record(against level: MatchController.Level) -> (wins: Int, losses: Int, draws: Int) {
        let games = vault.games.filter { $0.level == level.rawValue }
        return (games.filter { $0.result == .win }.count,
                games.filter { $0.result == .loss }.count,
                games.filter { $0.result == .draw }.count)
    }

    private var armyRankLine: String {
        let best = ArmySlot.allCases.map { army.record(for: $0).rank }.max() ?? .recruit
        return army.gamesPlayed == 0 ? "16 recruits" : "Best: \(best.title)"
    }
}

// MARK: - The week

/// Over the foot of the hero: games played each of the last seven days, today in amber.
struct HomeWeekCard: View {
    let games: [SavedGame]
    let streak: Int
    var now: Date = .now

    private var days: [(letter: String, count: Int, isToday: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let count = games.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            let letter = String(day.formatted(.dateTime.weekday(.narrow)))
            return (letter, count, back == 0)
        }
    }

    var body: some View {
        let days = days
        let total = days.map(\.count).reduce(0, +)
        let peak = max(days.map(\.count).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("THIS WEEK")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(HomePalette.amber)
                }
                .foregroundStyle(HomePalette.text)
                Spacer()
                Text(streak > 0 ? "\(streak)-day streak" : "Goal 1 a day")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomePalette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(total)")
                    .font(.system(size: 34, weight: .heavy).monospacedDigit())
                    .foregroundStyle(HomePalette.text)
                Text(total == 1 ? "game" : "games")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HomePalette.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 8) {
                        Text("\(day.count)")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(day.isToday ? HomePalette.amber : HomePalette.text.opacity(day.count > 0 ? 0.9 : 0.4))
                        Rectangle()
                            .fill(HomePalette.tertiary.opacity(0.5))
                            .frame(height: 1)
                            .mask(HStack(spacing: 3) { ForEach(0..<8, id: \.self) { _ in Rectangle() } })
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(day.isToday ? HomePalette.amber : HomePalette.amberDeep)
                            .frame(height: 14 + 30 * CGFloat(day.count) / CGFloat(peak))
                            .shadow(color: day.isToday ? HomePalette.amber.opacity(0.45) : .clear, radius: 8)
                        Text(day.letter)
                            .font(.system(size: 13, weight: day.isToday ? .heavy : .medium))
                            .foregroundStyle(day.isToday ? HomePalette.text : HomePalette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 108)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [HomePalette.card.opacity(0.55), HomePalette.card.opacity(0.96)],
                                             startPoint: .top, endPoint: .bottom))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), HomePalette.stroke],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week, \(total) games played. \(streak > 0 ? "\(streak) day training streak." : "")")
    }
}

// MARK: - Play

/// The rival you play next, its portrait filling the card like a poster.
struct HomeRivalCard: View {
    let rival: Rival
    let record: (wins: Int, losses: Int, draws: Int)
    let grudge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Image(rival.portraitName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 236)
                    .offset(x: 70)
                    .clipped()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.88), location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .clear, location: 0.8),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text(rival.name)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Rival \(rival.strength) of 5 · \(rival.elo)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                    Text("YOUR RECORD")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(recordLine)
                        .font(.system(size: 40, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Play \(rival.name)")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(HomePalette.amber)
                    .padding(.top, 4)
                }
                .padding(20)

                if grudge {
                    HStack(spacing: 6) {
                        Circle().fill(.white).frame(width: 7, height: 7)
                        Text("GRUDGE")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(HomePalette.live, in: Capsule())
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 236)
            .clipShape(RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Play \(rival.name), rival \(rival.strength) of 5, about \(rival.elo). Your record \(recordLine)")
    }

    private var recordLine: String {
        if record.wins + record.losses + record.draws == 0 { return "First match" }
        return record.draws > 0 ? "\(record.wins)–\(record.losses)–\(record.draws)" : "\(record.wins)–\(record.losses)"
    }
}

/// A game left half-played: who against, how far, and whose move.
struct HomeResumeCard: View {
    let match: MatchController
    let action: () -> Void

    var body: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HomeIconBadge(symbol: "hourglass")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponent)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(HomePalette.text)
                        Text("Move \(match.game.moveCount / 2 + 1) · \(match.game.isHumanTurn ? "Your move" : "Their move")")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HomePalette.secondary)
                    }
                }
                HomeOutlineButton(title: "Continue", action: action)
            }
        }
    }

    private var opponent: String {
        match.setup.opponent == .computer ? "Against \(match.setup.level.rival.name)" : "Against a friend"
    }
}

// MARK: - Sharpen up

/// Today's session with Coach Leo, the way the reference's "Me vs Me" card reads.
struct HomeCoachCard: View {
    let minutes: Int
    let focus: String?
    let streak: Int
    let trainedToday: Bool
    let action: () -> Void

    var body: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HomeIconBadge(symbol: "graduationcap.fill")
                    Text("Today with Coach Leo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(HomePalette.text)
                    Spacer(minLength: 0)
                    if trainedToday {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(HomePalette.amber)
                            .accessibilityLabel("Done today")
                    }
                }
                Text(body(for: focus))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HomePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HomeOutlineButton(title: trainedToday ? "Train some more" : "Start today's session", action: action)
            }
        }
    }

    private func body(for focus: String?) -> String {
        let lead = "\(minutes) minutes" + (focus.map { " on \($0.lowercased())" } ?? "") + ": a lesson, then puzzles from your own games."
        if streak > 0 { return lead + " Keep your \(streak)-day streak alive." }
        return lead + " Start a streak today."
    }
}

/// A slim card that opens one thing: an icon, a title, a line under it and a chevron.
struct HomeRowCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HomeIconBadge(symbol: symbol, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HomePalette.text)
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomePalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HomePalette.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomePalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(HomePalette.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(HomePressStyle())
    }
}

// MARK: - Army

/// The five pieces with the most experience, standing in a row with their names and ranks.
struct HomeArmyCard: View {
    let army: ArmyStore
    let theme: BoardTheme
    let action: () -> Void

    private struct Leader: Identifiable {
        let slot: ArmySlot
        let record: PieceRecord
        var id: ArmySlot { slot }
    }

    /// The five with the most experience; before any game, a queen-led line-up.
    private var leaders: [Leader] {
        let ranked = ArmySlot.allCases.map { Leader(slot: $0, record: army.record(for: $0)) }
            .sorted { $0.record.xp > $1.record.xp }
        if let top = ranked.first, top.record.xp > 0 { return Array(ranked.prefix(5)) }
        return [ArmySlot.queen, .king, .kingsKnight, .queensBishop, .kingsRook]
            .map { Leader(slot: $0, record: army.record(for: $0)) }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(leaders) { leader in
                        VStack(spacing: 6) {
                            PieceImage(piece: Piece(leader.slot.kind, color: .white, square: leader.slot.square(for: .white)),
                                       theme: theme, size: 48)
                                .frame(height: 56, alignment: .bottom)
                                .shadow(color: leader.record.rank == .legend ? HomePalette.amber.opacity(0.6) : .clear, radius: 10)
                            Text(leader.record.name ?? leader.slot.kind.word.capitalized)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(HomePalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(leader.record.rank.title.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(leader.record.rank >= .veteran ? HomePalette.amber : HomePalette.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(army.gamesPlayed == 0
                     ? "Every piece remembers. Win with them and they earn names, scars and a golden glow."
                     : "\(army.gamesPlayed) games together. Tap to see every piece's story.")
                    .font(.system(size: 15))
                    .foregroundStyle(HomePalette.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                    .fill(HomePalette.card)
                    .overlay(alignment: .top) {
                        RadialGradient(colors: [HomePalette.amber.opacity(0.13), .clear], center: .top,
                                       startRadius: 0, endRadius: 220)
                            .clipShape(RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                    .strokeBorder(HomePalette.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Your army")
    }
}

// MARK: - Rewind

/// Recent games as small posters in a sideways row, like the reference's challenge cards.
struct HomeRewindStrip: View {
    let games: [SavedGame]
    let open: (SavedGame) -> Void
    let openAll: () -> Void

    var body: some View {
        if games.isEmpty {
            HomeRowCard(symbol: "backward.fill", title: "Rewind",
                        detail: "Finished games land here to replay and rewrite", action: openAll)
                .padding(.horizontal, HomePalette.gutter)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(games) { game in
                        Button { open(game) } label: { poster(game) }
                            .buttonStyle(HomePressStyle())
                    }
                }
                .padding(.horizontal, HomePalette.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func poster(_ game: SavedGame) -> some View {
        let level = game.level.flatMap(MatchController.Level.init(rawValue:))
        return ZStack(alignment: .bottomLeading) {
            if let level {
                Image(level.rival.portraitName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 176)
                    .clipped()
            } else {
                HomePalette.cardRaised
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.result.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(game.result == .win ? HomePalette.amber : .white.opacity(0.7))
                Text(game.accuracy.map { "\($0)%" } ?? "\(game.moveCount) moves")
                    .font(.system(size: 26, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                Text("vs \(game.opponent)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(game.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
        }
        .frame(width: 150, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tab bar

/// The floating glass bar at the foot of the page. Home is lit; the rest open their screens.
struct HomeTabBar: View {
    let actions: HomeActions

    var body: some View {
        HStack(spacing: 0) {
            item("Home", "house.fill", lit: true) {}
            item("Train", "graduationcap.fill") { actions.train() }
            playButton
            item("Puzzles", "puzzlepiece.extension.fill") { actions.puzzles() }
            item("Analyze", "camera.viewfinder") { actions.analyze() }
        }
        .padding(6)
        .homeGlass(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var playButton: some View {
        Button(action: actions.play) {
            VStack(spacing: 2) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(HomePalette.amber, in: Capsule())
                    .shadow(color: HomePalette.amber.opacity(0.45), radius: 10)
                Text("Play")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HomePalette.text)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Play a new game")
    }

    private func item(_ title: String, _ symbol: String, lit: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 26)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(lit ? HomePalette.amber : HomePalette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                if lit {
                    Capsule().fill(Color.white.opacity(0.1))
                }
            }
        }
        .buttonStyle(HomePressStyle())
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
