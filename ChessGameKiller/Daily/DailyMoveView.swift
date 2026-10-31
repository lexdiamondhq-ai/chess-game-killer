import SwiftUI

/// Today's Move: the day's puzzle, the same for every player, then how the world did, the streak
/// and what's next. Played once a day for the streak; opened again, it can be replayed for fun.
struct DailyMoveView: View {
    let theme: BoardTheme
    /// Opens Puzzles, for more.
    var morePuzzles: (() -> Void)?
    var stats: DailyStatsAPI? = LiveDailyStatsAPI.shared

    @Environment(DailyStore.self) private var daily
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(TrainingStore.self) private var training
    @Environment(\.dismiss) private var dismiss

    @State private var puzzle: DailyPuzzle?
    @State private var runner: DrillRunner?
    /// This try counts for the day (the first one today).
    @State private var counts = true
    @State private var outcome: Outcome?
    @State private var tally: DailyTally?
    @State private var tallyFailed = false

    init(theme: BoardTheme, morePuzzles: (() -> Void)? = nil, stats: DailyStatsAPI? = LiveDailyStatsAPI.shared,
         outcome: Outcome? = nil, tally: DailyTally? = nil) {
        self.theme = theme
        self.morePuzzles = morePuzzles
        self.stats = stats
        _outcome = State(initialValue: outcome)
        _tally = State(initialValue: tally)
    }

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            GeometryReader { geo in
                let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.52))
                VStack(spacing: 12) {
                    header
                    ScrollView {
                        VStack(spacing: 14) {
                            if let runner {
                                DrillView(runner: runner, theme: theme, boardSide: boardSide)
                                    .padding(.top, 4)
                            } else if puzzle == nil {
                                Text("Today's Move couldn't be loaded.")
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 60)
                            }
                            if let outcome {
                                resultCard(outcome)
                                    .padding(.horizontal, 16)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(width: geo.size.width)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy, value: outcome)
        .task { start() }
        .onChange(of: runner?.outcome) { _, finished in
            guard let finished, outcome == nil else { return }
            finish(finished)
        }
        .onDisappear { runner?.cancel() }
    }

    // MARK: Pieces of the screen

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                runner?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Today's Move")

            VStack(alignment: .leading, spacing: 1) {
                Text("Today's Move")
                    .font(.app(.headline, weight: .semibold))
                Text(dateline)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StreakPill(streak: daily.streak, theme: theme)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// "No. 29 · Thursday · Tricky", or a note that a replay doesn't count again.
    private var dateline: String {
        guard let puzzle else { return Date.now.formatted(.dateTime.weekday(.wide)) }
        if !counts { return "No. \(puzzle.number) · Played today, this one is for fun" }
        return "No. \(puzzle.number) · \(Date.now.formatted(.dateTime.weekday(.wide))) · \(puzzle.difficulty)"
    }

    private func resultCard(_ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.verdict(outcome))
                .font(.app(.title2, weight: .semibold))
            tallyLine
            Divider().opacity(0.5)
            streakBlock
            HStack(spacing: 10) {
                if let morePuzzles {
                    Button("More puzzles") {
                        runner?.cancel()
                        dismiss()
                        morePuzzles()
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                }
                Button("Done") {
                    runner?.cancel()
                    dismiss()
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .trainingCard(theme, cornerRadius: 18)
    }

    @ViewBuilder
    private var tallyLine: some View {
        if let tally {
            Label(tally.line, systemImage: "globe")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        } else if tallyFailed || stats == nil {
            Label("Everyone gets this same puzzle today.", systemImage: "globe")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        } else {
            Label("Checking how everyone else did…", systemImage: "globe")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(theme.trainingAccent)
                    .symbolEffect(.bounce, value: daily.streak)
                Text(daily.streak == 1 ? "1-day streak" : "\(daily.streak)-day streak")
                    .font(.app(.headline).monospacedDigit())
                Spacer()
                Text("Day done")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
            }
            if let mark = daily.markToday {
                Label("\(mark.piece) now carries your \(mark.days)-day mark, for good.", systemImage: "seal.fill")
                    .font(.app(.subheadline))
                    .foregroundStyle(theme.trainingAccent)
            } else if let next = daily.nextMilestone {
                Text(next.toGo == 1 ? "Tomorrow earns a piece your \(next.days)-day mark."
                     : "\(next.toGo) more days and a piece earns your \(next.days)-day mark.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func verdict(_ outcome: Outcome) -> String {
        switch outcome {
        case .firstTry: return "Found it."
        case .withHint: return "Solved, with a hint."
        case .afterMistake: return "Solved on the second look."
        case .missed: return "Not this time."
        }
    }

    // MARK: Playing

    private func start() {
        guard runner == nil else { return }
        guard let today = daily.puzzle() else { puzzle = nil; return }
        puzzle = today
        counts = !daily.playedTodaysMove
        let lichess = LichessPuzzle(id: today.id, fen: today.fen, moves: today.moves, rating: today.rating, themes: today.themes)
        let item = SessionItem(content: .drill(lichess.drill), role: .focus)
        let made = DrillRunner(item: item, library: training.library, engine: nil)
        runner = made
        // Already finished (a picture of the result): the position stays as it was set.
        if outcome == nil { made?.begin() }
    }

    private func finish(_ result: Outcome) {
        withAnimation(.snappy) { outcome = result }
        guard counts, let puzzle else { return }
        let found = result == .firstTry
        daily.record(.todaysMove(found: found))
        puzzles.seen(LichessPuzzle(id: puzzle.id, fen: puzzle.fen, moves: puzzle.moves, rating: puzzle.rating, themes: puzzle.themes))
        training.recordPractice(xp: found ? 6 : 2)
        guard let stats else { return }
        let day = DailyMoves.dayKey(.now)
        Task { @MainActor in
            do {
                tally = try await stats.report(day: day, puzzle: puzzle.id, found: found, player: OnlinePlayerKey.current())
            } catch {
                tallyFailed = true
            }
        }
    }
}
