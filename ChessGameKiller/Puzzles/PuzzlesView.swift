import ChessKit
import SwiftUI

/// Puzzles from real games, from the Lichess database. Rated: endless puzzles
/// at the player's level in any theme, with a puzzle rating. Rush: three
/// minutes, puzzles that keep getting harder, three mistakes and you're out.
struct PuzzlesView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var store
    @Environment(TrainingStore.self) private var training
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case rated = "Rated"
        case rush = "Puzzle Rush"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .rated
    @State private var puzzle: LichessPuzzle?
    @State private var runner: DrillRunner?
    @State private var change: Int?
    @State private var showingThemes = false
    @State private var rush: RushRound?

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            GeometryReader { geo in
                let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.56))
                VStack(spacing: 12) {
                    header
                    if store.library == nil {
                        Spacer()
                        ProgressView("Loading puzzles…")
                        Spacer()
                    } else if mode == .rush, rush == nil || rush?.isOver == true {
                        RushCard(theme: theme, best: store.progress.rushBest, last: rush) { startRush() }
                            .padding(.horizontal, 16)
                        Spacer(minLength: 0)
                    } else if let runner {
                        if mode == .rated { themeRow.padding(.horizontal, 16) }
                        if mode == .rush, let rush { RushBar(round: rush, theme: theme) { endRush() }.padding(.horizontal, 16) }
                        ScrollView {
                            DrillView(runner: runner, theme: theme, boardSide: boardSide)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .id(puzzle?.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                        Spacer(minLength: 0)
                        if mode == .rated, runner.isDone { ratedFooter }
                    } else {
                        themeRow.padding(.horizontal, 16)
                        Spacer()
                        Text("No puzzles in this theme yet.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(width: geo.size.width)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy, value: runner?.isDone)
        .animation(.snappy, value: mode)
        .task {
            await store.load()
            if puzzle == nil, mode == .rated { nextRated() }
        }
        .onChange(of: runner?.outcome) { _, outcome in
            guard let outcome, let puzzle else { return }
            finished(puzzle, outcome: outcome)
        }
        .onChange(of: mode) { _, mode in
            runner?.cancel()
            runner = nil
            puzzle = nil
            change = nil
            if mode == .rated { rush = nil; nextRated() }
        }
        .onDisappear { runner?.cancel() }
        .sheet(isPresented: $showingThemes) {
            ThemePicker(theme: theme, selected: store.theme, library: store.library) { picked in
                store.theme = picked
                showingThemes = false
                nextRated()
            }
            .presentationDetents([.large])
        }
    }

    // MARK: Header

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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close puzzles")

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(store.progress.rating)")
                    .font(.system(.headline, design: .themed).weight(.bold).monospacedDigit())
                    .foregroundStyle(theme.trainingAccent)
                    .contentTransition(.numericText(value: Double(store.progress.rating)))
                Text("rating")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Puzzle rating \(store.progress.rating)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.snappy, value: store.progress.rating)
    }

    /// The theme in use, one tap from the picker.
    private var themeRow: some View {
        Button {
            showingThemes = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: store.theme.symbol)
                    .foregroundStyle(theme.trainingAccent)
                    .frame(width: 22)
                Text(store.theme.name)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                Spacer()
                if store.progress.streak > 1 {
                    Label("\(store.progress.streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(TrainingColor.orange.color(on: theme))
                }
                Text("Theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .trainingCard(theme, cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme: \(store.theme.name). Change theme")
    }

    // MARK: Rated

    private var ratedFooter: some View {
        VStack(spacing: 10) {
            if let outcome = runner?.outcome, outcome != .firstTry {
                // Anything short of a clean solve joins the review queue (PuzzleStore.record).
                TrainingChip(text: "Back for review tomorrow", symbol: "arrow.triangle.2.circlepath",
                             color: theme.trainingAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            if let puzzle {
                HStack(spacing: 8) {
                    if let change {
                        Text(change >= 0 ? "+\(change)" : "\(change)")
                            .font(.system(.subheadline, design: .themed).weight(.bold).monospacedDigit())
                            .foregroundStyle(change >= 0 ? TrainingColor.green.color(on: theme) : TrainingColor.red.color(on: theme))
                    }
                    Text("Puzzle \(puzzle.rating)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(puzzle.themeNames.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let url = puzzle.url {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .accessibilityLabel("Open on Lichess")
                    }
                }
                .padding(.horizontal, 20)
            }
            Button {
                withAnimation(.snappy) { nextRated() }
            } label: {
                Text("Next puzzle")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func nextRated() {
        change = nil
        show(store.nextRated(), strict: false)
    }

    private func show(_ next: LichessPuzzle?, strict: Bool) {
        runner?.cancel()
        puzzle = next
        guard let next else { runner = nil; return }
        let item = SessionItem(content: .drill(next.drill), role: .focus)
        let made = DrillRunner(item: item, library: training.library, engine: nil)
        made?.strict = strict
        runner = made
        made?.begin()
    }

    private func finished(_ puzzle: LichessPuzzle, outcome: Outcome) {
        switch mode {
        case .rated:
            change = store.record(puzzle, outcome: outcome)
        case .rush:
            guard var round = rush, !round.isOver else { return }
            store.seen(puzzle)
            if outcome == .firstTry { round.score += 1 } else { round.strikes += 1 }
            round.played.insert(puzzle.id)
            rush = round
            if round.strikes >= RushRound.lives {
                endRush()
                return
            }
            let solvedSoFar = round.score
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(outcome == .firstTry ? 450 : 900))
                guard let current = rush, !current.isOver else { return }
                withAnimation(.snappy) {
                    show(store.nextRush(solvedSoFar: solvedSoFar, avoid: current.played), strict: true)
                }
            }
        }
    }

    // MARK: Rush

    private func startRush() {
        let round = RushRound(endsAt: .now.addingTimeInterval(RushRound.duration))
        rush = round
        withAnimation(.snappy) {
            show(store.nextRush(solvedSoFar: 0, avoid: []), strict: true)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RushRound.duration))
            if rush?.endsAt == round.endsAt { endRush() }
        }
    }

    private func endRush() {
        guard var round = rush, !round.isOver else { return }
        runner?.cancel()
        round.isOver = true
        round.newBest = store.finishRush(score: round.score)
        withAnimation(.snappy) {
            rush = round
            runner = nil
            puzzle = nil
        }
    }
}

/// One Puzzle Rush run.
struct RushRound: Equatable {
    static let duration: TimeInterval = 180
    static let lives = 3

    let endsAt: Date
    var score = 0
    var strikes = 0
    var played: Set<String> = []
    var isOver = false
    var newBest = false
}

/// The clock, the score and the lives left, above the board during a Rush.
private struct RushBar: View {
    let round: RushRound
    let theme: BoardTheme
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let left = max(0, round.endsAt.timeIntervalSince(context.date))
                Label(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60), systemImage: "timer")
                    .font(.system(.headline, design: .themed).monospacedDigit())
                    .foregroundStyle(left < 20 ? TrainingColor.red.color(on: theme) : Color.primary)
            }
            Spacer()
            Text("\(round.score)")
                .font(.system(.title2, design: .themed).weight(.heavy).monospacedDigit())
                .foregroundStyle(theme.trainingAccent)
                .contentTransition(.numericText(value: Double(round.score)))
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<RushRound.lives, id: \.self) { index in
                    Image(systemName: index < round.strikes ? "xmark.circle.fill" : "circle")
                        .foregroundStyle(index < round.strikes ? TrainingColor.red.color(on: theme) : Color.secondary)
                }
            }
            Button("End", action: onStop)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .trainingCard(theme, cornerRadius: 14)
        .animation(.snappy, value: round)
    }
}

/// Before a Rush and after one: the rules, the best score and the start button.
private struct RushCard: View {
    let theme: BoardTheme
    let best: Int
    let last: RushRound?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.trainingAccent)
                .shadow(color: theme.glows ? theme.trainingAccent.opacity(0.7) : .clear, radius: 14)
            if let last, last.isOver {
                Text(last.newBest ? "New best!" : "Time!")
                    .font(.system(.title, design: .themed).weight(.bold))
                Text("\(last.score) solved")
                    .font(.system(.title3, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.trainingAccent)
            } else {
                Text("Puzzle Rush")
                    .font(.system(.title, design: .themed).weight(.bold))
                Text("Three minutes. The puzzles start easy and get harder with every one you solve. Three mistakes and you're out.")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Best: \(best)")
                .font(.system(.headline, design: .themed).monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: onStart) {
                Text(last?.isOver == true ? "Play again" : "Start")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .trainingCard(theme)
        .padding(.top, 24)
    }
}

/// Every theme, grouped, with how many puzzles each has.
private struct ThemePicker: View {
    let theme: BoardTheme
    let selected: PuzzleTheme
    let library: PuzzleLibrary?
    let onPick: (PuzzleTheme) -> Void

    @State private var counts: [String: Int] = [:]
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tile(.all)
                    ForEach(PuzzleTheme.Group.allCases, id: \.self) { group in
                        Text(group.rawValue)
                            .font(.system(.headline, design: .themed))
                            .padding(.leading, 4)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(PuzzleTheme.choices.filter { $0.group == group }) { tile($0) }
                        }
                    }
                }
                .padding(16)
            }
            .background { TrainingBackdrop(theme: theme) }
            .navigationTitle("Puzzle themes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .task {
            guard let library, counts.isEmpty else { return }
            var found: [String: Int] = [:]
            for choice in [PuzzleTheme.all] + PuzzleTheme.choices {
                found[choice.id] = library.count(of: choice)
            }
            counts = found
        }
    }

    private func tile(_ option: PuzzleTheme) -> some View {
        let isSelected = option.id == selected.id
        let accent = theme.trainingAccent
        return Button {
            onPick(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let count = counts[option.id] {
                        Text("\(count) puzzles")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainingCard(theme, tint: isSelected ? accent : nil, cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .disabled(counts[option.id] == 0)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
