import ChessKit
import SwiftUI

/// Board scan: the Traffic Light habit as a drill. Eight real positions from the puzzle
/// pack, near the player's puzzle rating; in each, find every check, every capture, or
/// every piece of yours in danger. Mixed asks for a different one at each position.
struct BoardScanView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(\.dismiss) private var dismiss
    @AppStorage("haptics") private var hapticsOn = true
    @AppStorage("visionScanMode") private var modeID = BoardScan.Mode.checks.rawValue
    @State private var runner: BoardScanRunner?
    @State private var loading = false
    @State private var nothingToScan = false
    private let store: VisionStore

    init(theme: BoardTheme) {
        self.init(theme: theme, store: .live(), runner: nil)
    }

    /// A store of its own and a round already under way, for tests and pictures.
    init(theme: BoardTheme, store: VisionStore, runner: BoardScanRunner?) {
        self.theme = theme
        self.store = store
        _runner = State(initialValue: runner)
    }

    private var mode: BoardScan.Mode { BoardScan.Mode(rawValue: modeID) ?? .checks }

    var body: some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.5, 560))
            VStack(spacing: 0) {
                RoomHeader(title: "Board scan", subtitle: subtitle) { close() }
                if let runner {
                    if runner.phase == .finished {
                        results(runner)
                    } else {
                        scan(runner, boardSide: boardSide)
                    }
                } else {
                    picker
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { TrainingBackdrop(theme: theme) }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy(duration: 0.25), value: runner?.phase)
        .animation(.snappy(duration: 0.25), value: runner?.index)
        .sensoryFeedback(.impact(weight: .light), trigger: runner?.foundTaps ?? 0) { old, new in hapticsOn && new > old }
        .sensoryFeedback(.error, trigger: runner?.slipTaps ?? 0) { old, new in hapticsOn && new > old }
        .task { await puzzles.load() }
        .onDisappear { runner?.cancel() }
    }

    private var subtitle: String {
        guard let runner else { return "Checks, captures and threats" }
        if runner.phase == .finished { return "\(runner.mode.title) · \(runner.exercises.count) positions" }
        return "\(runner.mode.title) · \(runner.index + 1) of \(runner.exercises.count)"
    }

    // MARK: Before a round

    /// What to scan for, each mode's best, and Start.
    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    RoomMessage(text: nothingToScan
                                    ? "I couldn't find positions for that scan just now. Try another one."
                                    : "Before every move, strong players look for checks, captures and threats. Eight real positions: find them all.",
                                tone: .coach, theme: theme)
                        .padding(.bottom, 4)
                    ForEach(BoardScan.Mode.allCases) { option in
                        modeRow(option)
                    }
                    Text("Positions from real games on Lichess.")
                        .font(.system(.footnote, design: .themed))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button {
                start(mode)
            } label: {
                if loading || puzzles.library == nil {
                    ProgressView()
                } else {
                    Label("Start", systemImage: "play.fill")
                }
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .disabled(loading || puzzles.library == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func modeRow(_ option: BoardScan.Mode) -> some View {
        let selected = option == mode
        let accent = theme.trainingAccent
        let best = store.scanBest(option).map { "Best \($0.percent)%" }
        return Button {
            modeID = option.rawValue
        } label: {
            HStack(spacing: 14) {
                TrainIcon(symbol: option.symbol, theme: theme, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(.headline, design: .themed))
                    Text(option.detail)
                        .font(.system(.subheadline, design: .themed))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let best {
                    Text(best)
                        .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .trainingCard(theme, tint: selected ? accent : nil, cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel([option.title, option.detail, best].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Scanning

    /// One position: what to find, the board, and Coach Leo.
    private func scan(_ runner: BoardScanRunner, boardSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ProgressDots(count: runner.exercises.count, index: runner.index, outcomes: runner.outcomes, theme: theme)
                        .padding(.horizontal, 16)
                        .accessibilityHidden(true)
                    kindRow(runner)
                        .padding(.horizontal, 16)
                    board(runner, side: boardSide)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            scanButton(runner)
        }
    }

    /// What to look for here, whose move it is, and how many are left to find.
    private func kindRow(_ runner: BoardScanRunner) -> some View {
        let kind = runner.exercise.kind
        let found = runner.attempt.found.sorted(by: { $0.rawValue < $1.rawValue }).map(\.notation)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.system(.title3, design: .themed).weight(.bold))
                .foregroundStyle(theme.trainingAccent)
                .lineLimit(1)
                .id(runner.exercise.id)
                .transition(.opacity)
            Text(runner.exercise.player == .white ? "White to move" : "Black to move")
                .font(.system(.footnote, design: .themed).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: 8)
            Text(counter(runner))
                .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                .foregroundStyle(runner.phase == .revealed ? Color.secondary : Color.primary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(found.isEmpty ? "" : "Found \(BoardGeometry.list(found))")
    }

    private func counter(_ runner: BoardScanRunner) -> String {
        let attempt = runner.attempt
        switch runner.phase {
        case .revealed, .finished:
            return "\(attempt.found.count) of \(attempt.exercise.targets.count) · \(BoardScanRunner.time(attempt.seconds ?? 0))"
        case .intro, .scanning:
            return "\(runner.remaining) to find"
        }
    }

    /// The position, with the squares found, the slips and, once revealed, the misses on it.
    private func board(_ runner: BoardScanRunner, side: CGFloat) -> some View {
        let flipped = runner.exercise.player == .black
        let attempt = runner.attempt
        return TrainingBoardView(
            game: runner.game,
            theme: theme,
            flipped: flipped,
            arrows: runner.arrows,
            onTap: runner.phase == .scanning ? { (square: Square) in runner.tap(square) } : nil
        )
        .frame(width: side, height: side)
        .overlay {
            ScanMarks(theme: theme, flipped: flipped, found: attempt.found, slips: attempt.slips,
                      missed: runner.phase == .revealed ? attempt.missed.map(\.square) : [])
        }
    }

    /// Done while scanning, Next once the position is revealed.
    private func scanButton(_ runner: BoardScanRunner) -> some View {
        Group {
            if runner.phase == .revealed {
                Button {
                    withAnimation(.snappy) { runner.next() }
                } label: {
                    Label(runner.isLast ? "See results" : "Next",
                          systemImage: runner.isLast ? "flag.checkered" : "arrow.right")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
            } else {
                Button {
                    withAnimation(.snappy) { runner.done() }
                } label: {
                    Text("Done")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                .disabled(runner.phase != .scanning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: After a round

    /// The round's totals, every position, and Again.
    private func results(_ runner: BoardScanRunner) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if let summary = runner.summary {
                        summaryCard(summary, runner: runner)
                    }
                    positionList(runner)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { self.runner = nil }
                } label: {
                    Text("Other scans")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                Button {
                    start(runner.mode)
                } label: {
                    if loading {
                        ProgressView()
                    } else {
                        Label("Again", systemImage: "arrow.counterclockwise")
                    }
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .disabled(loading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func summaryCard(_ summary: BoardScan.Summary, runner: BoardScanRunner) -> some View {
        let accent = theme.trainingAccent
        let best = store.scanBest(runner.mode)
        return VStack(spacing: 10) {
            Text(runner.mode.title.uppercased())
                .font(.system(.caption, design: .themed).weight(.bold))
                .tracking(1)
                .foregroundStyle(accent)
            Text("\(summary.percent)%")
                .font(.system(size: 56, weight: .bold, design: .themed).monospacedDigit())
            HStack(spacing: 0) {
                stat("\(summary.found) of \(summary.total)", label: "found")
                stat("\(summary.slips)", label: summary.slips == 1 ? "slip" : "slips")
                stat(BoardScanRunner.time(summary.seconds), label: "a position")
            }
            if runner.newBest {
                TrainingChip(text: "New best", symbol: "star.fill", color: accent)
            } else if let best {
                Text("Best \(best.percent)%, \(BoardScanRunner.time(best.seconds)) a position")
                    .font(.system(.footnote, design: .themed))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .trainingCard(theme, tint: accent)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .themed).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(.caption, design: .themed))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Every position in the round: what it asked for, what was found, and how long it took.
    private func positionList(_ runner: BoardScanRunner) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(runner.attempts.enumerated()), id: \.offset) { index, attempt in
                positionRow(number: index + 1, attempt: attempt)
                if index < runner.attempts.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 46)
                }
            }
        }
        .padding(.vertical, 4)
        .trainingCard(theme, cornerRadius: 18)
    }

    private func positionRow(number: Int, attempt: BoardScan.Attempt) -> some View {
        let kind = attempt.exercise.kind
        let total = attempt.exercise.targets.count
        let seconds = BoardScanRunner.time(attempt.seconds ?? 0)
        let slips = attempt.slips.count
        var spoken = "Position \(number), \(kind.title): \(attempt.found.count) of \(total) found"
        if slips > 0 { spoken += slips == 1 ? ", 1 slip" : ", \(slips) slips" }
        spoken += ", \(seconds)"
        return HStack(spacing: 10) {
            Circle()
                .fill(color(of: attempt.outcome))
                .frame(width: 8, height: 8)
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.trainingAccent)
                .frame(width: 18)
            Text(kind.title)
                .font(.system(.subheadline, design: .themed).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if slips > 0 {
                Label("\(slips)", systemImage: "xmark")
                    .font(.system(.caption, design: .themed).weight(.bold).monospacedDigit())
                    .foregroundStyle(TrainingColor.red.color(on: theme))
            }
            Text("\(attempt.found.count)/\(total)")
                .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
            Text(seconds)
                .font(.system(.subheadline, design: .themed).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func color(of outcome: Outcome) -> Color {
        switch outcome {
        case .firstTry: return TrainingColor.green.color(on: theme)
        case .withHint, .afterMistake: return TrainingColor.yellow.color(on: theme)
        case .missed: return TrainingColor.red.color(on: theme)
        }
    }

    // MARK: Starting and closing

    /// Picks a round's positions off the main thread, then starts it.
    private func start(_ mode: BoardScan.Mode) {
        guard let library = puzzles.library, !loading else { return }
        loading = true
        nothingToScan = false
        let rating = puzzles.progress.rating
        let avoid = store.recentScans
        Task { @MainActor in
            let exercises = await Task.detached(priority: .userInitiated) {
                var generator = SystemRandomNumberGenerator()
                return BoardScan.exercises(from: library, mode: mode, rating: rating, avoid: avoid, using: &generator)
            }.value
            loading = false
            runner?.cancel()
            guard let made = BoardScanRunner(mode: mode, exercises: exercises, store: store, sounds: SoundPlayer.shared) else {
                nothingToScan = true
                withAnimation(.snappy) { runner = nil }
                return
            }
            withAnimation(.snappy) { runner = made }
            made.begin()
        }
    }

    private func close() {
        runner?.cancel()
        dismiss()
    }
}
