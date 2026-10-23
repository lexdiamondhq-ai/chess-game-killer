import ChessKit
import SwiftUI

/// Review: rated puzzles that weren't solved cleanly, back on a schedule
/// (tomorrow, then after 3, 7 and 16 days). Plays the due ones in a row,
/// never touching the rating, and ends with "All caught up". Needs the
/// PuzzleStore in the environment.
struct PuzzleReviewView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The puzzles due when this review began, in order.
    @State private var queue: [String] = []
    @State private var index = 0
    @State private var began = false
    @State private var puzzle: LichessPuzzle?
    @State private var runner: DrillRunner?
    /// When the puzzle just played comes back.
    @State private var result: PuzzleReviewQueue.Result?
    /// Whether each puzzle reviewed this time was solved cleanly.
    @State private var results: [Bool] = []

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            VStack(spacing: 0) {
                RoomHeader(title: "Review", subtitle: "Missed puzzles, back on schedule") { close() }
                Group {
                    if !began {
                        VStack {
                            Spacer()
                            ProgressView("Loading puzzles…")
                            Spacer()
                        }
                    } else if let runner, let puzzle {
                        playing(runner, puzzle)
                    } else {
                        ReviewCaughtUpView(theme: theme, reviewed: results.count, clean: results.filter { $0 }.count,
                                           queue: store.progress.reviews, done: close)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy, value: runner?.isDone)
        .animation(.snappy, value: runner == nil)
        .task {
            await store.load()
            begin()
        }
        .onChange(of: runner?.outcome) { _, outcome in
            guard let outcome, let puzzle else { return }
            result = store.recordReview(puzzle.id, outcome: outcome)
            results.append(outcome == .firstTry)
        }
        .onDisappear { runner?.cancel() }
    }

    private func playing(_ runner: DrillRunner, _ puzzle: LichessPuzzle) -> some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.54, 560))
            VStack(spacing: 12) {
                ReviewProgressCard(theme: theme, position: index + 1, total: queue.count, results: results)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                ScrollView {
                    DrillView(runner: runner, theme: theme, boardSide: boardSide)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .id(puzzle.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                Spacer(minLength: 0)
                if runner.isDone {
                    footer(puzzle)
                }
            }
            .frame(width: geo.size.width)
        }
    }

    /// After each puzzle: when it comes back, its themes, and on to the next.
    private func footer(_ puzzle: LichessPuzzle) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let result {
                    chip(for: result)
                }
                Spacer(minLength: 0)
                Text(puzzle.themeNames.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            Button {
                withAnimation(.snappy) { next() }
            } label: {
                Text(index + 1 < queue.count ? "Next puzzle" : "Finish")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func chip(for result: PuzzleReviewQueue.Result) -> TrainingChip {
        switch result {
        case .learned:
            return TrainingChip(text: "Learned. It won't come back.", symbol: "checkmark.seal.fill",
                                color: TrainingColor.green.color(on: theme))
        case .returns(let days):
            return TrainingChip(text: days == 1 ? "Back tomorrow" : "Back in \(days) days", symbol: "calendar",
                                color: days == 1 ? TrainingColor.orange.color(on: theme) : theme.trainingAccent)
        }
    }

    // MARK: Moving through

    private func begin() {
        guard !began else { return }
        queue = store.dueReviews().map(\.id)
        index = 0
        began = true
        showCurrent()
    }

    /// Puts the puzzle at `index` on the board, skipping any the pack no longer has.
    private func showCurrent() {
        runner?.cancel()
        result = nil
        while index < queue.count {
            let id = queue[index]
            // Shown like a rated puzzle: the header already says this is review.
            if let next = store.library?.puzzle(id: id),
               let made = DrillRunner(item: SessionItem(content: .drill(next.drill), role: .focus),
                                      library: TrainingLibrary.shared, engine: nil) {
                puzzle = next
                runner = made
                made.begin()
                return
            }
            store.dropReview(id)
            index += 1
        }
        puzzle = nil
        runner = nil
    }

    private func next() {
        index += 1
        showCurrent()
    }

    private func close() {
        runner?.cancel()
        dismiss()
    }
}

/// Where the review is: the puzzle, what's left after it, and how each one went.
private struct ReviewProgressCard: View {
    let theme: BoardTheme
    let position: Int
    let total: Int
    let results: [Bool]

    private var left: Int { max(0, total - position) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(min(position, total)) of \(total)")
                    .font(.system(.headline, design: .themed).monospacedDigit())
                Spacer(minLength: 8)
                Text(left == 0 ? "Last one" : "\(left) left")
                    .font(.system(.subheadline, design: .themed).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PuzzleRunTrack(results: results, total: total, theme: theme)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .trainingCard(theme, cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenStatus)
    }

    private var spokenStatus: String {
        let after = left == 0 ? "The last one." : "\(left) left after it."
        return "Review puzzle \(min(position, total)) of \(total). " + after
    }
}

/// Nothing due, or the review just finished: how it went, what's waiting and when.
private struct ReviewCaughtUpView: View {
    let theme: BoardTheme
    /// Reviewed this time, and how many of those cleanly.
    let reviewed: Int
    let clean: Int
    let queue: PuzzleReviewQueue
    let done: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
                    .shadow(color: theme.glows ? theme.trainingAccent.opacity(0.7) : .clear, radius: 14)
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("All caught up")
                        .font(.system(.title, design: .themed).weight(.bold))
                    if reviewed > 0 {
                        Text("\(reviewed) reviewed · \(clean) clean")
                            .font(.system(.subheadline, design: .themed).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                stats
                RoomMessage(text: coachLine, tone: .coach, theme: theme)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: done)
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: 560)
        }
    }

    private var stats: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            stat("\(queue.count)", "in review")
            stat(nextDue, "next one")
            stat("\(queue.learned)", "learned")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .themed).weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .trainingCard(theme, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    /// When the next puzzle comes back: "Today", "Tomorrow", "In 3 days", or a dash.
    private var nextDue: String {
        let now = Date.now
        guard let due = queue.nextDue(after: now) else { return "–" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }

    private var coachLine: String {
        if queue.count == 0, queue.learned == 0, reviewed == 0 {
            return "Nothing to review yet. A puzzle you miss in rated play comes back here the next day, then after 3, 7 and 16 days."
        }
        if reviewed > 0, clean == reviewed {
            return "Clean sweep. Each one comes back later, just before you'd forget it."
        }
        return "Missed puzzles come back here: tomorrow, then after 3, 7 and 16 days. Solve one cleanly each time and it's learned for good."
    }
}
