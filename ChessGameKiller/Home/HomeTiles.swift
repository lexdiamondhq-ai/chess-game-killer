import ChessKit
import SwiftUI

// The tiles under the board window: hello and your numbers, a game with a person, today's
// puzzle and session, the games still going, the ladder and your games. Each one is a single
// tap into one thing, and together they fit on about one screen.

// MARK: - Hello

/// The top of the home: hello (with your name once a challenge has given it), and two chips,
/// your streak and your level. The streak opens Today's Move; the level goes to the ladder.
struct HomeGreeting: View {
    let name: String
    let streak: Int
    let doneToday: Bool
    /// What keeps the streak going, or what it earned: said to VoiceOver with the chip.
    let streakDetail: String
    /// Your rough rating from your games, once there are a few to go on.
    let level: Int?
    let tone: HomeTone
    let openStreak: () -> Void
    let openLevel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            TimelineView(.everyMinute) { context in
                hello(Self.greeting(context.date))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                streakChip
                if let level {
                    levelChip(level)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func hello(_ greeting: String) -> some View {
        if name.isEmpty {
            Text(greeting)
                .font(.app(.title2, weight: .semibold))
                .foregroundStyle(tone.ink)
                .tracking(-0.4)
                .accessibilityAddTraits(.isHeader)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting)
                    .font(.app(.subheadline))
                    .foregroundStyle(tone.ink2)
                Text(name)
                    .font(.app(.title2, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .tracking(-0.4)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var streakChip: some View {
        Button(action: openStreak) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(streak > 0 ? AnyShapeStyle(Self.flame) : AnyShapeStyle(tone.ink3))
                    .symbolEffect(.bounce, value: streak)
                Text("\(streak)")
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(streak > 0 ? tone.metal : tone.ink2)
                    .contentTransition(.numericText(value: Double(streak)))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background { HomeChipFill(tone: tone) }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(streakSpoken)
        .accessibilityValue(streakDetail)
        .accessibilityHint("Opens Today's Move")
    }

    private func levelChip(_ level: Int) -> some View {
        Button(action: openLevel) {
            HStack(spacing: 5) {
                Glyph(name: Glyphs.king, size: 15)
                    .foregroundStyle(tone.metal)
                Text(verbatim: "~\(level)")
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tone.ink)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background { HomeChipFill(tone: tone) }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Your level, about \(level)")
        .accessibilityHint("Shows the ladder of rivals")
    }

    private var streakSpoken: String {
        let days = streak == 1 ? "1-day streak" : "\(streak)-day streak"
        guard streak > 0 else { return "No streak yet" }
        return doneToday ? "\(days), done today" : days
    }

    /// The flame's own warm gold, lighter at its tip.
    static let flame = LinearGradient(colors: [Color(hex: 0xFFD993), Color(hex: 0xD4893D)],
                                      startPoint: .top, endPoint: .bottom)

    /// "Good morning", "Good afternoon" or "Good evening", by the clock.
    static func greeting(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Play a person

/// A game with a person, as Chess.com and Lichess keep them side by side under one Play:
/// Online, rated, with a live dot while players wait; and A friend, sent by link.
struct HomePlayTile: View {
    let tone: HomeTone
    /// Players waiting in the lobby, nil until known.
    let waiting: Int?
    let online: () -> Void
    let friend: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            HomePlayTileFace(glyph: Glyphs.online, title: "Online", line: onlineLine,
                             live: (waiting ?? 0) > 0, tone: tone, label: "Play online",
                             hint: "Rated games with players waiting now. Take one on, or find a game.",
                             inputLabels: ["Play online", "Online", "Find a game"], action: online)
            HomePlayTileFace(glyph: Glyphs.challenge, title: "A friend", line: "Send a link",
                             live: false, tone: tone, label: "Challenge a friend",
                             hint: "Send a game by text or email. They can play in a browser, no app needed.",
                             inputLabels: ["Challenge a friend", "Challenge", "Friend"], action: friend)
        }
        .padding(6)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous), tone: tone)
        .animation(.snappy(duration: 0.3), value: waiting)
    }

    private var onlineLine: String {
        guard let waiting, waiting > 0 else { return "Rated games" }
        return "\(waiting) waiting"
    }
}

/// One half of the Play tile: an icon, a name and one line. The whole face is the button.
struct HomePlayTileFace: View {
    let glyph: String
    let title: String
    let line: String
    let live: Bool
    let tone: HomeTone
    let label: String
    let hint: String
    let inputLabels: [String]
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius - 6, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                HomeIconChip(glyph: glyph, tone: tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    HStack(spacing: 6) {
                        if live {
                            HomeLiveDot(color: tone.live, size: 6)
                        }
                        Text(line)
                            .font(.app(.footnote).monospacedDigit())
                            .foregroundStyle(tone.ink2)
                            .contentTransition(.numericText())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .homePane(shape, tone: tone, weight: .well(lit: false))
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(line)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels(inputLabels)
    }
}

// MARK: - Today

/// Where the daily habit stands: the streak, what's done, and Today's Move.
struct HomeDailyState: Equatable {
    var streak = 0
    var doneToday = false
    /// Today's Move: its number, how hard, whether it was played and found.
    var number = 0
    var difficulty = ""
    var played = false
    var found = false
    /// Rated puzzles solved today, toward the three that make a day.
    var puzzlesToday = 0
    /// "Ghost now carries your 7-day mark.", the day it's earned.
    var mark: String?
    /// "2 more days to your 7-day mark."
    var nextMark: String?
    /// Ask, once, after the first day done, whether to send a reminder.
    var asksReminder = false

    /// The line under the streak: what keeps it, or what it earned.
    var detail: String {
        if doneToday { return mark ?? nextMark ?? "Done for today. See you tomorrow." }
        if puzzlesToday > 0 {
            let left = DailyRules.puzzlesForTheDay - puzzlesToday
            return "\(left) more \(left == 1 ? "puzzle" : "puzzles"), one game or Today's Move keeps it."
        }
        return streak > 0 ? "One game, Today's Move or 3 puzzles keeps it going."
            : "One game, Today's Move or 3 puzzles starts a streak."
    }

    /// Today's Move in a few words: "No. 29 · Tricky", or what became of it.
    var moveLine: String {
        if played { return found ? "Found it. New one tomorrow." : "Played. New one tomorrow." }
        guard number > 0 else { return "A new puzzle every day" }
        return difficulty.isEmpty ? "No. \(number)" : "No. \(number) · \(difficulty)"
    }
}

/// Today's Move as a tile: the position drawn small, how hard it is (or done), and the
/// way to solve it. The same puzzle for everyone in the world, every day.
struct HomeDailyTile: View {
    let puzzle: HomePuzzle?
    let daily: HomeDailyState
    let tone: HomeTone
    let pieceTheme: BoardTheme
    let solve: () -> Void

    @ScaledMetric(relativeTo: .body) private var boardSize: CGFloat = 72

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        Button(action: solve) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    HomeMiniBoard(fen: puzzle?.fen, flipped: puzzle?.solver == .black, theme: pieceTheme,
                                  tone: tone, lit: !daily.played)
                        .frame(width: min(boardSize, 96), height: min(boardSize, 96))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    Spacer(minLength: 0)
                    badge
                }
                Spacer(minLength: 12)
                Text("Today's Move")
                    .font(.app(.headline))
                    .foregroundStyle(tone.ink)
                HStack(spacing: 5) {
                    Text(daily.moveLine)
                        .foregroundStyle(daily.played ? tone.metal : tone.ink2)
                    if !daily.played {
                        Text("Solve")
                            .font(.app(.footnote, weight: .semibold))
                            .foregroundStyle(tone.metal)
                    }
                }
                .font(.app(.footnote))
                .padding(.top, 2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topTrailing) {
                HomeTileGlow(color: tone.metal, strength: 0.3)
                    .offset(x: 70, y: -70)
            }
            .clipShape(shape)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's Move")
        .accessibilityValue(spoken)
        .accessibilityHint(daily.played ? "Opens Today's Move again" : "Solve today's puzzle")
        .accessibilityAddTraits(.isButton)
    }

    /// How hard today's puzzle is, or a check once it is played.
    @ViewBuilder
    private var badge: some View {
        if daily.played {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tone.onIvory)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tone.metal))
        } else if !daily.difficulty.isEmpty {
            Text(daily.difficulty)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(tone.metal)
                .padding(.horizontal, 9)
                .frame(minHeight: 24)
                .background(Capsule().fill(tone.metal.opacity(0.14)))
        }
    }

    private var spoken: String {
        var parts = [daily.moveLine]
        if let puzzle, !daily.played { parts.append(puzzle.title) }
        return parts.joined(separator: ". ")
    }
}

/// Today with the coach as a tile: a ring for the way to the next rank with the coach in
/// it, and today's session in a few words. A tap starts it.
struct HomeCoachTile: View {
    let plan: SessionPlan?
    let trainedToday: Bool
    /// From 0 to 1, how far along to the next rank.
    let progress: Double
    let tone: HomeTone
    let start: (SessionPlan) -> Void
    let train: () -> Void

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 70

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 0) {
                HomeProgressRing(progress: progress, tone: tone) {
                    Glyph(name: Glyphs.coach, size: min(ringSize, 96) * 0.44)
                        .foregroundStyle(tone.ink)
                }
                .frame(width: min(ringSize, 96), height: min(ringSize, 96))
                Spacer(minLength: 12)
                Text("Train with \(Coach.current.name)")
                    .font(.app(.headline))
                    .foregroundStyle(tone.ink)
                HStack(spacing: 5) {
                    if trainedToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tone.metal)
                    }
                    Text(line)
                        .foregroundStyle(trainedToday ? tone.metal : tone.ink2)
                }
                .font(.app(.footnote))
                .padding(.top, 2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .bottomLeading) {
                HomeTileGlow(color: tone.pool, strength: 0.55)
                    .offset(x: -80, y: 80)
            }
            .clipShape(shape)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Train with \(Coach.current.name)")
        .accessibilityValue(line)
        .accessibilityHint(plan != nil && !trainedToday ? "Starts today's session" : "Opens training")
        .accessibilityAddTraits(.isButton)
    }

    private func tap() {
        if let plan, !trainedToday {
            start(plan)
        } else {
            train()
        }
    }

    /// "8 min · Forks", "Done for today", or "Lessons and drills" before a plan is ready.
    private var line: String {
        if trainedToday { return "Done for today" }
        guard let plan else { return "Lessons and drills" }
        let what = plan.focus?.title ?? plan.headline ?? "Today's session"
        return "\(plan.minutes) min · \(what)"
    }
}

/// A ring that fills in gold, with something in its middle.
struct HomeProgressRing<Content: View>: View {
    let progress: Double
    let tone: HomeTone
    @ViewBuilder let content: () -> Content

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(tone.ink.opacity(0.1), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(min(shown, 1), 0.02))
                .stroke(LinearGradient(colors: [Color(hex: 0xFFE2A8), tone.metal, Color(hex: 0xB98A4A)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tone.metal.opacity(0.35), radius: 4)
            content()
        }
        .padding(2)
        .accessibilityHidden(true)
        .onAppear { fill(progress) }
        .onChange(of: progress) { _, value in fill(value) }
    }

    private func fill(_ value: Double) {
        guard !reduceMotion else { shown = value; return }
        withAnimation(.easeOut(duration: 1.1).delay(0.3)) { shown = value }
    }
}

/// A short note under the day's tiles, only when there is one: the streak mark a piece just
/// earned, or the one question the home ever asks, whether to send a reminder.
struct HomeNoticeCard: View {
    let daily: HomeDailyState
    let tone: HomeTone
    let remind: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Whether there is anything to say today.
    static func shows(_ daily: HomeDailyState) -> Bool {
        daily.asksReminder || (daily.doneToday && daily.mark != nil)
    }

    var body: some View {
        Group {
            if daily.asksReminder {
                reminder
            } else if let mark = daily.mark {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HomeGreeting.flame)
                    Text(mark)
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(tone.metal)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous), tone: tone)
    }

    /// The question, with Remind me beside it and a small cross for Not now, so it fits on
    /// one card without cutting either short.
    private var reminder: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone.metal)
                Text("A reminder tomorrow, around this time?")
                    .font(.app(.subheadline))
                    .foregroundStyle(tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                Button("Remind me") { remind(true) }
                    .buttonStyle(HomeGlassButtonStyle(tone: tone, compact: true))
                    .fixedSize()
                Button {
                    remind(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone.ink3)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle())
                .accessibilityLabel("Not now")
                .padding(.trailing, -8)
            }
        }
    }
}

// MARK: - Games still going

/// Every game still going with a person, as a strip of chips you swipe: the position drawn
/// small and whose move it is, your move first and lit in gold. Tap one to go back to it.
struct HomeCurrentStrip: View {
    let games: [HomeCurrentGame]
    let tone: HomeTone
    let pieceTheme: BoardTheme
    let open: (HomeCurrentGame) -> Void

    @ScaledMetric(relativeTo: .body) private var boardSize: CGFloat = 46

    private var yours: Int { games.filter(\.isYourMove).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(games) { game in
                        chip(game)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(yours > 0 ? "Your move" : "Current games")
                .font(.app(.headline))
                .foregroundStyle(tone.ink)
            if yours > 0 {
                Text(verbatim: "· \(yours)")
                    .font(.app(.headline).monospacedDigit())
                    .foregroundStyle(tone.metal)
            }
            Spacer(minLength: 8)
            if yours == 0 {
                Text("Waiting on them")
                    .font(.app(.footnote))
                    .foregroundStyle(tone.ink2)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(HomeCurrentGame.note(games).map { "Current games, \($0)" } ?? "Current games")
    }

    private func chip(_ game: HomeCurrentGame) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let board: CGFloat = min(boardSize, 60)
        return Button {
            open(game)
        } label: {
            HStack(spacing: 10) {
                HomeMiniBoard(fen: game.fen, flipped: game.flipped, theme: pieceTheme, tone: tone, lit: game.isYourMove)
                    .frame(width: board, height: board)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.name(game))
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(game.isYourMove ? tone.metal : tone.ink3.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(game.status.words)
                            .font(.app(.caption, weight: game.isYourMove ? .semibold : .regular))
                            .foregroundStyle(game.isYourMove ? tone.metal : tone.ink2)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
            .padding(8)
            .padding(.trailing, 8)
            .frame(minWidth: 148, alignment: .leading)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.status.words), \(game.detail.replacingOccurrences(of: " · ", with: ", "))")
        .accessibilityAddTraits(.isButton)
    }

    /// The other player's name, without the "vs": "Maya", "Open challenge".
    static func name(_ game: HomeCurrentGame) -> String {
        game.title.hasPrefix("vs ") ? String(game.title.dropFirst(3)) : game.title
    }
}

// MARK: - The ladder

/// The five rivals in a row, weakest to strongest, on a track lit in gold up to the one to
/// beat next. Under each, the match score. Tap a rival to set up a game against them.
struct HomeLadderTile: View {
    let ladder: HomeLadder
    let tone: HomeTone
    let play: (MatchController.Level) -> Void

    @ScaledMetric(relativeTo: .body) private var portraitSize: CGFloat = 44

    private var portrait: CGFloat { min(portraitSize, 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("The ladder")
                    .font(.app(.headline))
                    .foregroundStyle(tone.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(note)
                    .font(.app(.footnote))
                    .foregroundStyle(ladder.nextToBeat == nil ? tone.ink2 : tone.metal)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            HStack(alignment: .top, spacing: 0) {
                ForEach(ladder.rungs) { rung in
                    rungButton(rung)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) { track }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous), tone: tone)
    }

    private var note: String {
        guard let next = ladder.nextToBeat else { return "You lead every rival" }
        return "Next to beat: \(next.rival.name)"
    }

    /// A fine line through the portraits, gold from the first rival up to the next to beat.
    private var track: some View {
        GeometryReader { geo in
            let count = CGFloat(max(ladder.rungs.count, 2))
            let column: CGFloat = geo.size.width / count
            let start: CGFloat = column / 2
            let span: CGFloat = geo.size.width - column
            let reached = CGFloat(ladder.nextToBeat?.rawValue ?? (ladder.rungs.count - 1))
            let lit: CGFloat = span * reached / (count - 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(tone.ink.opacity(0.14))
                    .frame(width: span, height: 1)
                Rectangle()
                    .fill(LinearGradient(colors: [tone.metal.opacity(0.25), tone.metal], startPoint: .leading, endPoint: .trailing))
                    .frame(width: lit, height: 1.5)
            }
            .offset(x: start, y: portrait / 2)
        }
        .frame(height: portrait)
        .accessibilityHidden(true)
    }

    private func rungButton(_ rung: HomeLadder.Rung) -> some View {
        let rival = rung.level.rival
        let isNext = ladder.nextToBeat == rung.level
        let beaten = rung.standing == .ahead
        return Button {
            play(rung.level)
        } label: {
            VStack(spacing: 6) {
                HomeRivalPortrait(rival: rival, tone: tone, size: portrait)
                    .background { Circle().fill(tone.canvas) }
                    .overlay {
                        if isNext {
                            Circle()
                                .strokeBorder(tone.metal, lineWidth: 1.5)
                                .padding(-3)
                                .shadow(color: tone.metal.opacity(0.6), radius: 5)
                        }
                    }
                    .opacity(beaten || isNext || rung.played > 0 ? 1 : 0.72)
                Text(rival.name)
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(isNext ? tone.metal : tone.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(rung.score ?? "–")
                    .font(.app(.caption2).monospacedDigit())
                    .foregroundStyle(rung.played == 0 ? tone.ink3 : tone.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(rung, isNext: isNext))
        .accessibilityHint("Sets up a game against \(rival.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func spoken(_ rung: HomeLadder.Rung, isNext: Bool) -> String {
        let rival = rung.level.rival
        var parts = ["\(rival.name), rung \(rung.level.rawValue + 1), rated \(rung.level.spokenRating)"]
        if isNext { parts.append("next to beat") }
        if rung.played == 0 {
            parts.append("not played yet")
        } else {
            parts.append("\(rung.standingText), \(Self.spokenPoints(rung.yourPoints)) to \(Self.spokenPoints(rung.theirPoints))")
        }
        return parts.joined(separator: ". ")
    }

    static func spokenPoints(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        guard value - Double(whole) >= 0.5 else { return "\(whole)" }
        return whole == 0 ? "a half" : "\(whole) and a half"
    }
}

/// A rival's portrait, printed in the page's ivory rather than its own neon, so the home
/// keeps one palette while every rival keeps the face it has across the app.
struct HomeRivalPortrait: View {
    let rival: Rival
    let tone: HomeTone
    let size: CGFloat

    var body: some View {
        Image(rival.portraitName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            // A little closer in, so the rival's shape fills the small circle.
            .scaleEffect(1.2)
            .grayscale(1)
            .colorMultiply(tone.ivory)
            .contrast(1.3)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(tone.ink.opacity(0.18), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

// MARK: - Your games

/// Your games in one row: how many, how many this week, and the last few results the way a
/// scoresheet writes them (1, ½, 0), oldest to newest. A tap opens them all in Rewind.
struct HomeGamesTile: View {
    let rows: [HomeGameRow]
    let total: Int
    let week: Int
    let tone: HomeTone
    let openAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        Button(action: openAll) {
            HStack(spacing: 12) {
                HomeIconChip(glyph: Glyphs.games, tone: tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your games")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    Text(detail)
                        .font(.app(.footnote))
                        .foregroundStyle(tone.ink2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    form
                }
                Image(systemName: "chevron.forward")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(tone.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your games")
        .accessibilityValue(detail)
        .accessibilityHint("Opens your games in Rewind")
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String {
        let games = total == 1 ? "1 game" : "\(total) games"
        return week > 0 ? "\(games) · \(week) this week" : games
    }

    /// The last results, oldest first, so the newest sits nearest the chevron.
    private var form: some View {
        HStack(spacing: 4) {
            ForEach(Array(rows.prefix(5).reversed())) { row in
                Text(HomeGameRow.score(row.game.result))
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(color(row.game.result))
                    .frame(width: 20, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(row.game.result == .win ? tone.ink.opacity(0.14) : tone.ink.opacity(0.05))
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ result: SavedGame.Result) -> Color {
        switch result {
        case .win: return tone.ink
        case .draw: return tone.ink2
        case .loss, .unfinished: return tone.ink3
        }
    }
}

// MARK: - Small parts

/// An icon in a small rounded well of the pieces' gold: the home's way of marking a door.
struct HomeIconChip: View {
    let glyph: String
    let tone: HomeTone
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Glyph(name: glyph, size: size * 0.54)
            .foregroundStyle(tone.metal)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: [tone.metal.opacity(0.26), tone.metal.opacity(0.05)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { shape.strokeBorder(tone.metal.opacity(0.32), lineWidth: 0.75) }
            .accessibilityHidden(true)
    }
}

/// A soft round glow behind a tile's corner, so the glass catches a little light.
struct HomeTileGlow: View {
    let color: Color
    var strength: Double = 0.3

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 170, height: 170)
            .blur(radius: 42)
            .opacity(strength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
