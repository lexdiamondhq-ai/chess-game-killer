import ChessKit
import SwiftUI

/// Cycles, the Woodpecker Method: a fixed set of puzzles solved again and
/// again, each cycle aiming for half the time of the one before, until the
/// patterns are instant. One wrong move ends a puzzle and shows the answer.
/// Leaving part way keeps the place and pauses the clock. Cycles never
/// change the puzzle rating. Needs the PuzzleStore in the environment.
struct PuzzleCyclesView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("haptics") private var hapticsOn = true
    /// The set size picked last time; 0 until the player picks one.
    @AppStorage("puzzleCycles.size") private var savedSize = 0

    @State private var puzzle: LichessPuzzle?
    @State private var runner: DrillRunner?
    @State private var stopwatch = CycleStopwatch()
    @State private var advancing: Task<Void, Never>?
    /// Picking a new set while one is under way.
    @State private var choosingSet = false
    @State private var confirmingNewSet = false

    /// Twenty on a phone, so a cycle fits in a sitting; forty on a big screen.
    private var size: PuzzleCycleSize {
        PuzzleCycleSize(rawValue: savedSize) ?? (sizeClass == .regular ? .standard : .short)
    }

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            VStack(spacing: 0) {
                RoomHeader(title: "Cycles", subtitle: "The Woodpecker Method") { close() }
                    .overlay(alignment: .topTrailing) { optionsMenu }
                screen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy, value: runner == nil)
        .animation(.snappy, value: choosingSet)
        .animation(.snappy, value: runner?.isDone)
        .task {
            await store.load()
            resume()
        }
        .onChange(of: runner?.phase) { _, _ in updateClock() }
        .onChange(of: runner?.outcome) { _, outcome in
            if let outcome { finished(outcome) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateClock() } else { pause() }
        }
        .onDisappear {
            pause()
            advancing?.cancel()
            runner?.cancel()
        }
        .sensoryFeedback(.success, trigger: store.cycleSet?.finishedRuns.count ?? 0) { old, new in
            hapticsOn && new > old
        }
        .confirmationDialog("Start a new set?", isPresented: $confirmingNewSet, titleVisibility: .visible) {
            Button("Start a new set", role: .destructive) { startSet() }
            Button("Keep my set", role: .cancel) {}
        } message: {
            Text(replaceWarning)
        }
    }

    // MARK: Screens

    @ViewBuilder
    private var screen: some View {
        if let runner, let puzzle {
            playing(runner, puzzle)
                .transition(.opacity)
        } else if choosingSet || store.cycleSet == nil {
            CycleSetupView(theme: theme, rating: store.progress.rating, setsFinished: store.cycles.setsFinished,
                           ready: store.library != nil,
                           size: Binding(get: { size }, set: { savedSize = $0.rawValue }),
                           canGoBack: choosingSet && store.cycleSet != nil,
                           start: requestStart, back: backToSet)
                .transition(.opacity)
        } else if let set = store.cycleSet {
            switch set.stage {
            case .playing:
                loading
            case .between, .complete:
                CycleSummaryView(theme: theme, set: set, restSuggested: store.cycleRestSuggested(),
                                 startNext: startNextCycle, newSet: { choosingSet = true }, done: close)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var loading: some View {
        VStack {
            Spacer()
            ProgressView("Loading puzzles…")
            Spacer()
        }
    }

    private func playing(_ runner: DrillRunner, _ puzzle: LichessPuzzle) -> some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 32, geo.size.height - 270, 560))
            ScrollView {
                VStack(spacing: 14) {
                    if let set = store.cycleSet, let run = set.currentRun {
                        CycleStatusCard(theme: theme, cycle: set.cycles.count, run: run, total: set.count,
                                        stopwatch: stopwatch)
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    }
                    TrainingBoardView(game: runner.game, theme: theme, flipped: runner.learner == .black,
                                      arrows: runner.arrows, marks: runner.marks, labels: runner.labels,
                                      onTap: runner.acceptsTaps ? { (square: Square) in runner.tap(square) } : nil)
                        .frame(width: side, height: side)
                        .boardHeadroom(theme: theme, side: side)
                    TurnBadge(theme: theme, side: runner.learner, showing: runner.phase == .solving)
                        .padding(.top, -8)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                    actions(runner)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(width: geo.size.width)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// While solving, the way out; after a miss, the way on. A clean solve moves on by itself.
    private func actions(_ runner: DrillRunner) -> some View {
        Group {
            if runner.isDone, runner.outcome != .firstTry {
                Button {
                    withAnimation(.snappy) { showNext() }
                } label: {
                    Text(store.cycleSet?.currentRun?.isFinished == true ? "See how it went" : "Next puzzle")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
            } else if runner.phase == .solving {
                Button {
                    withAnimation(.snappy) { runner.reveal() }
                } label: {
                    Label("Show me", systemImage: "eye.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                .accessibilityHint("Shows the answer. It counts as missed.")
            } else {
                Color.clear
            }
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var optionsMenu: some View {
        if store.cycleSet != nil, !choosingSet {
            Menu {
                Button {
                    chooseNewSet()
                } label: {
                    Label("New set", systemImage: "plus.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Cycles options")
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
    }

    private var replaceWarning: String {
        guard let set = store.cycleSet, case .playing(let cycle, _) = set.stage else {
            return "A new set replaces the one you're on."
        }
        return "You're on cycle \(cycle) of your current set. A new set replaces it."
    }

    // MARK: Playing

    /// Picks the cycle up at the puzzle up next.
    private func resume() {
        guard runner == nil, !choosingSet, let stage = store.cycleSet?.stage, case .playing = stage else { return }
        showNext()
    }

    /// Puts the puzzle up next on the board, or clears the board when the cycle is done.
    private func showNext() {
        advancing?.cancel()
        runner?.cancel()
        stopwatch = CycleStopwatch()
        guard let library = store.library, let id = store.cycleSet?.currentRun?.nextPuzzleID else {
            runner = nil
            puzzle = nil
            return
        }
        guard let next = library.puzzle(id: id),
              let made = DrillRunner(item: SessionItem(content: .drill(next.drill), role: .focus),
                                     library: TrainingLibrary.shared, engine: nil) else {
            // The pack no longer has it, after an update: take it out and carry on.
            store.dropFromCycles(id)
            showNext()
            return
        }
        made.strict = true
        puzzle = next
        runner = made
        made.begin()
    }

    private func finished(_ outcome: Outcome) {
        guard let puzzle else { return }
        store.recordCycle(puzzle.id, clean: outcome == .firstTry, seconds: stopwatch.take(at: .now))
        // A clean solve moves straight on; a miss waits so the answer can be studied.
        guard outcome == .firstTry else { return }
        advancing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showNext() }
        }
    }

    /// The clock runs only while it's the player's move, before any slip, with the app in front.
    private func updateClock() {
        if let runner, runner.phase == .solving, runner.mistakes == 0, scenePhase == .active {
            stopwatch.start(at: .now)
        } else {
            stopwatch.stop(at: .now)
        }
    }

    /// Stops the clock and keeps the time spent on an unfinished puzzle for the next visit.
    private func pause() {
        let seconds = stopwatch.take(at: .now)
        if let runner, !runner.isDone {
            store.pauseCycle(carrying: seconds)
        }
    }

    private func close() {
        pause()
        advancing?.cancel()
        runner?.cancel()
        dismiss()
    }

    // MARK: Sets and cycles

    private func requestStart() {
        if store.cycleSetInProgress {
            confirmingNewSet = true
        } else {
            startSet()
        }
    }

    private func startSet() {
        guard store.startCycleSet(size: size) else { return }
        choosingSet = false
        showNext()
    }

    private func startNextCycle() {
        guard store.startNextCycle() else { return }
        showNext()
    }

    private func chooseNewSet() {
        pause()
        advancing?.cancel()
        runner?.cancel()
        runner = nil
        puzzle = nil
        choosingSet = true
    }

    private func backToSet() {
        choosingSet = false
        resume()
    }
}

// MARK: - Pieces of the screen

/// The cycle, the puzzle and the clock, above the board.
private struct CycleStatusCard: View {
    let theme: BoardTheme
    let cycle: Int
    let run: PuzzleCycleRun
    let total: Int
    let stopwatch: CycleStopwatch

    /// The puzzle on the board, counting from 1.
    private var current: Int { min(run.attempts.count + 1, total) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle \(cycle)")
                        .font(.system(.headline, design: .themed))
                    Text("\(current) of \(total)")
                        .font(.system(.subheadline, design: .themed).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let elapsed = run.elapsed + stopwatch.elapsed(at: context.date)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CycleClock.text(elapsed))
                            .font(.system(.title3, design: .themed).weight(.bold).monospacedDigit())
                            .foregroundStyle(isOver(elapsed) ? TrainingColor.orange.color(on: theme) : theme.trainingAccent)
                        Text(run.target.map { "target \(CycleClock.text($0))" } ?? "your pace")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            PuzzleRunTrack(results: run.attempts.map(\.clean), total: total, theme: theme)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .trainingCard(theme, cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenStatus)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func isOver(_ elapsed: TimeInterval) -> Bool {
        run.target.map { elapsed > $0 } ?? false
    }

    private var spokenStatus: String {
        let elapsed = run.elapsed + stopwatch.elapsed(at: .now)
        var text = "Cycle \(cycle), puzzle \(current) of \(total). Time \(CycleClock.spoken(elapsed))"
        if let target = run.target { text += ", target \(CycleClock.spoken(target))" }
        return text + "."
    }
}

/// One segment per puzzle: green for a clean solve, red for a miss, the accent for the one up next.
struct PuzzleRunTrack: View {
    let results: [Bool]
    let total: Int
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: total <= 24 ? 3 : (total <= 48 ? 2 : 1)) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(color(at: index))
                    .frame(height: index == results.count ? 6 : 4)
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: results)
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        if index < results.count {
            return results[index] ? TrainingColor.green.color(on: theme) : TrainingColor.red.color(on: theme)
        }
        return index == results.count ? theme.trainingAccent : Color.primary.opacity(0.14)
    }
}

/// Before a set: what Cycles is, the size to pick, and Start.
private struct CycleSetupView: View {
    let theme: BoardTheme
    let rating: Int
    let setsFinished: Int
    /// Whether the puzzle pack has loaded.
    let ready: Bool
    @Binding var size: PuzzleCycleSize
    /// Picking a new set over one under way, which can still be kept.
    let canGoBack: Bool
    let start: () -> Void
    let back: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                CycleIllustration(theme: theme)
                    .padding(.top, 16)
                VStack(spacing: 10) {
                    Text("The same puzzles, faster each round")
                        .font(.system(.title2, design: .themed).weight(.bold))
                    Text("Solve a set at your own pace. Rest a day, then solve it again in half the time. Repeat until you see the answers at a glance.")
                        .font(.system(.subheadline, design: .themed))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if setsFinished > 0 {
                        TrainingChip(text: setsFinished == 1 ? "1 set finished" : "\(setsFinished) sets finished",
                                     symbol: "checkmark.seal.fill", color: theme.trainingAccent)
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.center)
                sizes
                levelNote
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { buttons }
    }

    private var sizes: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ForEach(PuzzleCycleSize.allCases) { option in
                sizeTile(option)
            }
        }
    }

    private func sizeTile(_ option: PuzzleCycleSize) -> some View {
        let selected = option == size
        let accent = theme.trainingAccent
        return Button {
            withAnimation(.snappy) { size = option }
        } label: {
            VStack(spacing: 3) {
                Text("\(option.count)")
                    .font(.system(.title2, design: .themed).weight(.bold).monospacedDigit())
                    .foregroundStyle(selected ? accent : Color.primary)
                Text(option.name)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                Text(option.firstCycle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .trainingCard(theme, tint: selected ? accent : nil, cornerRadius: 16)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name): \(option.count) puzzles, \(option.firstCycle) the first time through")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var levelNote: some View {
        let level = PuzzleCycleSet.level(forRating: rating)
        let relation = level < rating ? "a step below your \(rating.formatted())" : "gentle for your \(rating.formatted())"
        let note = "Puzzles around \(level.formatted()), \(relation), so you learn to recognize the ideas instead of working them out."
        return Label {
            Text(note)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "scope")
                .foregroundStyle(theme.trainingAccent)
        }
        .font(.system(.footnote, design: .themed))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: start) {
                Text(ready ? "Start cycle 1" : "Loading puzzles…")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .disabled(!ready)
            if canGoBack {
                Button("Back to my set", action: back)
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

private extension PuzzleCycleSize {
    /// About how long the first, unhurried cycle takes.
    var firstCycle: String {
        switch self {
        case .short: return "about 15 min"
        case .standard: return "about 30 min"
        case .long: return "about an hour"
        }
    }
}

/// Four bars, each half the one before: Cycles at a glance.
private struct CycleIllustration: View {
    let theme: BoardTheme

    var body: some View {
        let accent = theme.trainingAccent
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(1 - Double(index) * 0.2))
                        .frame(width: 26, height: 80 / CGFloat(1 << index))
                    Text("\(index + 1)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .shadow(color: theme.glows ? accent.opacity(0.5) : .clear, radius: 10)
        .accessibilityHidden(true)
    }
}

/// Between cycles and at the end: every cycle's time and accuracy, and what's next.
private struct CycleSummaryView: View {
    let theme: BoardTheme
    let set: PuzzleCycleSet
    /// The last cycle ended today: suggest coming back tomorrow.
    let restSuggested: Bool
    let startNext: () -> Void
    let newSet: () -> Void
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(.title, design: .themed).weight(.bold))
                    Text(subtitle)
                        .font(.system(.subheadline, design: .themed).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                CycleBars(set: set, theme: theme)
                RoomMessage(text: coachLine, tone: set.isComplete ? .success : .coach, theme: theme)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { buttons }
    }

    private var runs: [PuzzleCycleRun] { self.set.finishedRuns }

    private var title: String {
        if case .between(let next, _) = set.stage { return "Cycle \(next - 1) done" }
        return "Set complete"
    }

    private var subtitle: String {
        guard let last = runs.last else { return "" }
        if set.isComplete, let first = runs.first, runs.count > 1 {
            return "\(runs.count) cycles · from \(CycleClock.text(first.elapsed)) to \(CycleClock.text(last.elapsed))"
        }
        return "\(set.count) puzzles in \(CycleClock.text(last.elapsed)) · \(last.cleanCount) clean"
    }

    private var coachLine: String {
        guard case .between(let next, let target) = set.stage, let last = runs.last else {
            return "These \(set.count) patterns are yours now. Watch for them in your games."
        }
        let opener: String
        if runs.count == 1 {
            opener = last.accuracy < 0.7
                ? "Every answer seen once. The misses are fine: the first time through is for learning them."
                : "Every answer seen once, and most of them found on your own."
        } else if last.beatTarget == true {
            opener = "Under target. The answers are starting to come before you think."
        } else {
            opener = "Close. Speed comes as the answers feel familiar."
        }
        let plan = restSuggested
            ? "Sleep on it: patterns settle overnight. Cycle \(next) tomorrow, target \(CycleClock.text(target))."
            : "Rested and ready. Cycle \(next): target \(CycleClock.text(target)). Trust your first look."
        return opener + " " + plan
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            switch set.stage {
            case .between(let next, _):
                if restSuggested {
                    Button("Done for today", action: done)
                        .buttonStyle(TrainingButtonStyle(theme: theme))
                    Button("Start cycle \(next) now", action: startNext)
                        .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                } else {
                    Button("Start cycle \(next)", action: startNext)
                        .buttonStyle(TrainingButtonStyle(theme: theme))
                    Button("New set", action: newSet)
                        .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                }
            case .complete, .playing:
                Button("New set", action: newSet)
                    .buttonStyle(TrainingButtonStyle(theme: theme))
                Button("Done", action: done)
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

/// Each cycle as two bars: its time (with a tick at its target) and its
/// clean solves, then the next cycle's target as a dashed bar.
private struct CycleBars: View {
    let set: PuzzleCycleSet
    let theme: BoardTheme

    var body: some View {
        let runs = set.finishedRuns
        let next = set.nextTarget
        let longest = max(runs.map(\.elapsed).max() ?? 0, next ?? 0, 1)
        VStack(alignment: .leading, spacing: 16) {
            legend
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                row(number: index + 1, run: run, longest: longest)
            }
            if let next {
                targetRow(number: runs.count + 1, target: next, longest: longest)
            }
        }
        .padding(16)
        .trainingCard(theme)
    }

    private var green: Color { TrainingColor.green.color(on: theme) }

    private var legend: some View {
        HStack(spacing: 14) {
            Label {
                Text("Time")
            } icon: {
                Circle().fill(theme.trainingAccent).frame(width: 8, height: 8)
            }
            Label {
                Text("Solved cleanly")
            } icon: {
                Circle().fill(green).frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func row(number: Int, run: PuzzleCycleRun, longest: TimeInterval) -> some View {
        let percent = Int((run.accuracy * 100).rounded())
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(.subheadline, design: .themed).weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 16)
            VStack(spacing: 5) {
                bar(run.elapsed / longest, color: theme.trainingAccent, height: 10,
                    tick: run.target.map { $0 / longest })
                bar(run.accuracy, color: green, height: 4)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(CycleClock.text(run.elapsed))
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                Text("\(percent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(green)
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(number: number, run: run, percent: percent))
    }

    private func targetRow(number: Int, target: TimeInterval, longest: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(.subheadline, design: .themed).weight(.bold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 16)
            GeometryReader { geo in
                Capsule()
                    .strokeBorder(theme.trainingAccent.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: max(14, geo.size.width * CGFloat(min(1, target / longest))), height: 10)
            }
            .frame(height: 10)
            VStack(alignment: .trailing, spacing: 1) {
                Text(CycleClock.text(target))
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle \(number): target \(CycleClock.spoken(target))")
    }

    /// A rounded bar filled to `fraction`, with an optional mark at `tick`.
    private func bar(_ fraction: Double, color: Color, height: CGFloat, tick: Double? = nil) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(height, width * CGFloat(min(1, max(0, fraction)))))
                if let tick {
                    Capsule()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 2, height: height + 6)
                        .offset(x: min(width - 2, max(0, width * CGFloat(min(1, tick)) - 1)))
                }
            }
        }
        .frame(height: height)
    }

    private func spoken(number: Int, run: PuzzleCycleRun, percent: Int) -> String {
        var text = "Cycle \(number): \(CycleClock.spoken(run.elapsed)), \(percent) percent solved cleanly"
        if let target = run.target {
            text += run.elapsed <= target ? ", under the target of \(CycleClock.spoken(target))"
                : ", over the target of \(CycleClock.spoken(target))"
        }
        return text
    }
}
