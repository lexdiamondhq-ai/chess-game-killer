import ChessKit
import SwiftUI

/// A training session from start to finish: a quick intro, the lesson if
/// there is one, the drills, and a summary that ends on a high note.
struct SessionView: View {
    let plan: SessionPlan
    let theme: BoardTheme
    /// Skips the intro, for a session started from a card that already showed what's in it.
    var startsAtOnce = false
    @Environment(TrainingStore.self) private var store
    /// Puzzles from the Lichess pack report back to the puzzle store, for review.
    @Environment(PuzzleStore.self) private var puzzles: PuzzleStore?
    @Environment(\.dismiss) private var dismiss
    @State private var runner: SessionRunner?

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            if let runner {
                switch runner.stage {
                case .intro:
                    SessionIntro(plan: plan, theme: theme, store: store) {
                        withAnimation(.snappy) { runner.begin() }
                    } close: {
                        dismiss()
                    }
                    .transition(.opacity)
                case .lesson:
                    if let lesson = runner.plan.lesson {
                        LessonPlayerView(lesson: lesson, theme: theme, onFinish: {
                            withAnimation(.snappy) { runner.lessonFinished() }
                        }, onSkip: {
                            withAnimation(.snappy) { runner.skipLesson() }
                        })
                        .transition(.opacity)
                    }
                case .drills:
                    drills(runner)
                        .transition(.opacity)
                case .summary:
                    SessionSummary(runner: runner, theme: theme, next: nextStep(after: runner)) {
                        dismiss()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .onAppear {
            if runner == nil {
                let made = SessionRunner(plan: plan, store: store, engine: StockfishEngine.shared)
                runner = made
                if startsAtOnce { made.begin() }
            }
        }
        .onDisappear { runner?.drill?.cancel() }
    }

    /// What to offer after a finished session: the player's own mistakes, when some are due.
    private func nextStep(after runner: SessionRunner) -> SessionSummary.Next? {
        let onlyMistakes = runner.plan.items.allSatisfy {
            if case .mistake = $0.content { return true } else { return false }
        }
        guard !runner.endedEarly, !onlyMistakes else { return nil }
        let due = store.dueMistakeCount
        guard due > 0, let plan = store.mistakesPlan() else { return nil }
        return SessionSummary.Next(title: due == 1 ? "Fix 1 position from your games" : "Fix \(due) positions from your games",
                                   symbol: "arrow.uturn.backward") {
            start(plan)
        }
    }

    /// Moves straight on to another session in the same screen.
    private func start(_ plan: SessionPlan) {
        runner?.drill?.cancel()
        let made = SessionRunner(plan: plan, store: store, engine: StockfishEngine.shared)
        withAnimation(.snappy) {
            runner = made
            made.begin()
        }
    }

    // MARK: Drills

    private func drills(_ runner: SessionRunner) -> some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.54))
            VStack(spacing: 12) {
                header(runner)
                if let note = runner.coachNote {
                    coachNote(note)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let drill = runner.drill {
                    ScrollView {
                        DrillView(runner: drill, theme: theme, boardSide: boardSide, talks: true)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .id(runner.index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .onChange(of: drill.outcome) { _, outcome in
                        guard let outcome else { return }
                        if case .drill(let played)? = runner.current?.content, let id = played.lichessPuzzleID {
                            puzzles?.recordTraining(id, outcome: outcome)
                        }
                        runner.record(outcome)
                    }
                }
                Spacer(minLength: 0)
                if runner.drill?.isDone == true {
                    Button {
                        withAnimation(.snappy) { runner.next() }
                    } label: {
                        Text(runner.index + 1 < runner.items.count ? "Continue" : "See how you did")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width)
        }
        .animation(.snappy, value: runner.drill?.isDone)
        .animation(.snappy, value: runner.coachNote)
    }

    private func header(_ runner: SessionRunner) -> some View {
        HStack(spacing: 12) {
            Button {
                runner.end()
                if runner.stage != .summary { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End session")

            ProgressDots(count: runner.items.count, index: runner.index, outcomes: runner.outcomes, theme: theme)

            Text("+\(runner.reward.xp)")
                .font(.app(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(theme.trainingAccent)
                .contentTransition(.numericText(value: Double(runner.reward.xp)))
                .animation(.snappy, value: runner.reward.xp)
                .accessibilityLabel("\(runner.reward.xp) XP earned")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func coachNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CoachAvatar(theme: theme, size: 30)
            Text(note)
                .font(.app(.subheadline, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .trainingCard(theme, tint: TrainingColor.violet.color(on: theme), cornerRadius: 16)
    }
}

/// One dot per drill: green solved, yellow solved with help, red missed.
struct ProgressDots: View {
    let count: Int
    let index: Int
    let outcomes: [Outcome]
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color(at: i))
                    .frame(height: i == index ? 7 : 5)
                    .shadow(color: theme.glows && i < outcomes.count ? color(at: i).opacity(0.8) : .clear, radius: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: outcomes.count)
        .animation(.snappy, value: index)
        .accessibilityElement()
        .accessibilityLabel("Drill \(min(index + 1, count)) of \(count)")
        .accessibilityValue(summary)
    }

    /// The results so far in words, since the dots only say it in color.
    private var summary: String {
        guard !outcomes.isEmpty else { return "" }
        let solved = outcomes.filter { $0 == .firstTry }.count
        let helped = outcomes.filter { $0 == .withHint || $0 == .afterMistake }.count
        let missed = outcomes.filter { $0 == .missed }.count
        var parts = ["\(solved) solved"]
        if helped > 0 { parts.append("\(helped) with help") }
        if missed > 0 { parts.append("\(missed) missed") }
        return parts.joined(separator: ", ")
    }

    private func color(at i: Int) -> Color {
        if i < outcomes.count {
            switch outcomes[i] {
            case .firstTry: return TrainingColor.green.color(on: theme)
            case .withHint, .afterMistake: return TrainingColor.yellow.color(on: theme)
            case .missed: return TrainingColor.red.color(on: theme)
            }
        }
        return i == index ? theme.trainingAccent : Color.secondary.opacity(0.25)
    }
}

/// What today's session holds, and a big Start button.
struct SessionIntro: View {
    let plan: SessionPlan
    let theme: BoardTheme
    let store: TrainingStore
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 12)
            VStack(spacing: 18) {
                CoachAvatar(theme: theme, size: 84)
                VStack(spacing: 6) {
                    Text(plan.title)
                        .font(.app(.title, weight: .bold))
                        .multilineTextAlignment(.center)
                    if let focus = plan.focus {
                        Label(focus.title, systemImage: focus.symbol)
                            .font(.app(.headline))
                            .foregroundStyle(theme.trainingAccent)
                    } else if let headline = plan.headline {
                        Label(headline, systemImage: plan.symbol ?? "puzzlepiece.fill")
                            .font(.app(.headline))
                            .foregroundStyle(theme.trainingAccent)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let lesson = plan.lesson {
                        row("play.rectangle.fill", "Lesson: \(lesson.title)", TrainingColor.blue)
                    }
                    let mistakes = plan.items.filter { if case .mistake = $0.content { return true } else { return false } }.count
                    let drills = plan.items.count - mistakes
                    if drills > 0 {
                        row("puzzlepiece.fill", drills == 1 ? "1 puzzle" : "\(drills) puzzles", TrainingColor.violet)
                    }
                    if mistakes > 0 {
                        row("arrow.uturn.backward.circle.fill",
                            mistakes == 1 ? "1 position from your games" : "\(mistakes) positions from your games",
                            TrainingColor.pink)
                    }
                    row("clock.fill", "About \(plan.minutes) min", TrainingColor.teal)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trainingCard(theme)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 12)
            Button("Let's go", action: start)
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private func row(_ symbol: String, _ text: String, _ color: TrainingColor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // One accent on the executive looks; Neon keeps its colors.
                .foregroundStyle(theme.glows ? color.color(on: theme) : theme.trainingAccent)
                .frame(width: 24)
            Text(text)
                .font(.app(.subheadline, weight: .medium))
        }
    }
}

/// The end of a session: how it went, what was earned, and the next rank.
struct SessionSummary: View {
    /// A follow-up worth doing right away, offered under Done.
    struct Next {
        let title: String
        let symbol: String
        let action: () -> Void
    }

    let runner: SessionRunner
    let theme: BoardTheme
    var next: Next?
    let done: () -> Void

    @State private var shown = false
    /// The app-wide daily streak, when the app provides it.
    @Environment(DailyStore.self) private var daily: DailyStore?

    private var store: TrainingStore { runner.store }

    var body: some View {
        let accuracy = runner.accuracy
        let days = daily?.streak ?? max(runner.reward.streak, store.streak)
        let green = theme.glows ? TrainingColor.green.color(on: theme) : theme.trainingAccent
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: shown ? accuracy : 0, color: green, lineWidth: 10)
                        .frame(width: 150, height: 150)
                        .shadow(color: theme.glows ? green.opacity(0.6) : .clear, radius: 10)
                    VStack(spacing: 2) {
                        Text("\(runner.solvedCount)/\(runner.outcomes.count)")
                            .font(.app(size: 38, weight: .bold).monospacedDigit())
                        Text("solved")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 28)

                Text(headline)
                    .font(.app(.title2, weight: .bold))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    stat("+\(runner.reward.xp)", "XP", "sparkles", theme.trainingAccent)
                    stat("\(days)", days == 1 ? "day" : "days", "flame.fill",
                         TrainingColor.orange.color(on: theme))
                }

                if let promotion = runner.reward.promotion {
                    promotionCard(promotion)
                } else {
                    rankCard
                }

                if let line = store.library?.course.lines.sessionDone.randomElement() {
                    HStack(alignment: .top, spacing: 12) {
                        CoachAvatar(theme: theme, size: 40)
                        Text(runner.reward.usedRestDay
                             ? "Your streak used its rest day, so it's still alive. \(line)"
                             : line)
                            .font(.app(.body, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .trainingCard(theme)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let next {
                    Button(action: next.action) {
                        Label(next.title, systemImage: next.symbol)
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme))
                }
                Button("Done", action: done)
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: next == nil))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { shown = true }
        }
        .sensoryFeedback(.success, trigger: shown)
    }

    private var headline: String {
        switch runner.accuracy {
        case 0.9...: return "Outstanding!"
        case 0.7..<0.9: return "Strong session!"
        case 0.45..<0.7: return "Good work. It's sinking in."
        default: return "Tough one. That's where learning happens."
        }
    }

    private func stat(_ value: String, _ unit: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.app(.title3))
                .foregroundStyle(color)
                .shadow(color: theme.glows ? color : .clear, radius: 6)
            Text(value)
                .font(.app(.title3, weight: .bold).monospacedDigit())
            Text(unit)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .trainingCard(theme, cornerRadius: 18)
    }

    @ViewBuilder
    private var rankCard: some View {
        if let rank = store.rank {
            HStack(spacing: 14) {
                PieceImage(piece: Piece(rank.pieceKind, color: .white, square: .a1), theme: theme, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(rank.title)
                            .font(.app(.headline))
                        Spacer()
                        if let next = store.nextRank {
                            Text("\(next.xp - store.progress.xp) XP to \(next.title)")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: shown ? store.rankProgress : 0)
                        .tint(theme.trainingAccent)
                }
            }
            .padding(16)
            .trainingCard(theme)
        }
    }

    private func promotionCard(_ rank: Rank) -> some View {
        let gold = TrainingColor.yellow.color(on: theme)
        return VStack(spacing: 10) {
            PieceImage(piece: Piece(rank.pieceKind, color: .white, square: .a1), theme: theme, size: 72)
                .scaleEffect(shown ? 1 : 0.4)
                .shadow(color: gold.opacity(0.8), radius: 16)
            Text("Promoted to \(rank.title)!")
                .font(.app(.title3, weight: .bold))
                .foregroundStyle(gold)
            Text(store.library?.course.lines.promotion.randomElement() ?? "A new rank. Well earned.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .trainingCard(theme, tint: gold)
    }
}
