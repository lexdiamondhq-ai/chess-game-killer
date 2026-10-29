import ChessKit
import SwiftUI

/// Think in candidates: a position near the player's puzzle rating, a list of up
/// to three moves worth a closer look, and Leo's verdict on the list. Five
/// positions make a round.
struct CandidateMovesView: View {
    let theme: BoardTheme
    private let engine: ChessEngine?
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(ThinkStore.self) private var store: ThinkStore?
    @Environment(\.dismiss) private var dismiss
    @State private var session: CandidateSession?

    /// The drill, with Stockfish checking each list. Needs `.environment(puzzleStore)`;
    /// with `.environment(thinkStore)` as well, the results are saved.
    init(theme: BoardTheme, engine: ChessEngine? = StockfishEngine.shared) {
        self.theme = theme
        self.engine = engine
    }

    /// The drill with a round already under way, for tests and previews.
    init(theme: BoardTheme, session: CandidateSession) {
        self.theme = theme
        engine = nil
        _session = State(initialValue: session)
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.5))
            VStack(spacing: 8) {
                header
                content(boardSide: side)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .task {
            await puzzles.load()
            start()
        }
        .onDisappear { session?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        RoomHeader(title: "Think in candidates", subtitle: subtitle) {
            session?.cancel()
            dismiss()
        }
        // Room for the points, so a long title never runs under them.
        .padding(.trailing, session?.stage == .playing ? 56 : 0)
        .overlay(alignment: .trailing) {
            if let session, session.stage == .playing {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(session.round.points)")
                        .font(.app(.headline, weight: .bold).monospacedDigit())
                        .foregroundStyle(theme.trainingAccent)
                        .contentTransition(.numericText(value: Double(session.round.points)))
                    Text("points")
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
                .animation(.snappy, value: session.round.points)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(session.round.points) points this round")
            }
        }
    }

    private var subtitle: String {
        guard let session else { return "Name the moves worth a look" }
        switch session.stage {
        case .playing: return "Position \(session.position) of \(CandidateRound.length)"
        case .summary: return "Round complete"
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(boardSide: CGFloat) -> some View {
        if let session {
            switch session.stage {
            case .playing:
                if let runner = session.runner {
                    CandidatePositionView(runner: runner, session: session, theme: theme, boardSide: boardSide)
                        .id(ObjectIdentifier(runner))
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    Spacer()
                    Text("No positions to show yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            case .summary:
                CandidateRoundSummary(session: session, theme: theme) {
                    dismiss()
                }
                .transition(.opacity)
            }
        } else {
            Spacer()
            ProgressView("Loading positions…")
            Spacer()
        }
    }

    private func start() {
        guard session == nil, let library = puzzles.library else { return }
        let made = CandidateSession(puzzles: library.puzzles, rating: puzzles.progress.rating, engine: engine,
                                    store: store, sounds: SoundPlayer.shared)
        session = made
        made.next()
    }
}

// MARK: - One position

/// The board, Leo's line, the list (or the verdict on it) and the buttons.
private struct CandidatePositionView: View {
    let runner: CandidateRunner
    let session: CandidateSession
    let theme: BoardTheme
    let boardSide: CGFloat
    @AppStorage("haptics") private var hapticsOn = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        board
                        turnBadge
                    }
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                    if let report = runner.report {
                        CandidateVerdictCard(report: report, theme: theme)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        CandidateSlots(runner: runner, theme: theme)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .animation(.snappy, value: runner.phase)
        .animation(.snappy, value: runner.candidates)
        .sensoryFeedback(.selection, trigger: runner.candidates.count) { _, _ in hapticsOn }
    }

    private var board: some View {
        TrainingBoardView(
            game: runner.game,
            theme: theme,
            flipped: runner.learner == .black,
            arrows: runner.arrows,
            labels: runner.labels,
            onTap: runner.phase == .listing ? { (square: Square) in runner.tap(square) } : nil
        )
        .frame(width: boardSide, height: boardSide)
        .boardHeadroom(theme: theme, side: boardSide)
    }

    /// "White to move" in the player's color, under the board while the list is made.
    private var turnBadge: some View {
        TurnBadge(theme: theme, side: runner.learner, showing: runner.phase == .listing)
    }

    @ViewBuilder
    private var actions: some View {
        switch runner.phase {
        case .intro, .listing:
            let ready = runner.phase == .listing && !runner.candidates.isEmpty
            Button {
                withAnimation(.snappy) { runner.check() }
            } label: {
                Text("Check my candidates")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .disabled(!ready)
            .opacity(ready ? 1 : 0.45)
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("\(Coach.current.name) is checking…")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityElement(children: .combine)
        case .judged:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    lineButton
                    nextButton
                }
                VStack(spacing: 8) {
                    nextButton
                    lineButton
                }
            }
        case .playingLine, .lineShown:
            nextButton
        }
    }

    private var lineButton: some View {
        Button {
            runner.showLine()
        } label: {
            Text("Show the winning line")
        }
        .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
    }

    private var nextButton: some View {
        Button {
            withAnimation(.snappy) { session.next() }
        } label: {
            Text(session.round.isFinished ? "See your round" : "Next position")
        }
        .buttonStyle(TrainingButtonStyle(theme: theme))
    }
}

// MARK: - The list

/// Three places for candidates under the board: the moves named so far, each
/// tapped to drop it, and the places still free.
private struct CandidateSlots: View {
    let runner: CandidateRunner
    let theme: BoardTheme
    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 22

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { slots }
            VStack(spacing: 8) { slots }
        }
    }

    @ViewBuilder
    private var slots: some View {
        ForEach(0..<CandidateRunner.maxCandidates, id: \.self) { index in
            if index < runner.candidates.count {
                filled(runner.candidates[index], number: index + 1)
            } else {
                empty(number: index + 1)
            }
        }
    }

    private func filled(_ candidate: CandidateRunner.Candidate, number: Int) -> some View {
        let color = TrainingColor.blue.color(on: theme)
        return Button {
            withAnimation(.snappy) { runner.remove(candidate) }
        } label: {
            HStack(spacing: 8) {
                CandidateNumber(number: number, color: color, size: badge, theme: theme)
                Text(candidate.san)
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.app(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(theme.isDark ? 0.14 : 0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(runner.phase != .listing)
        .accessibilityLabel("Candidate \(number): \(candidate.san)")
        .accessibilityHint("Takes it off your list")
    }

    private func empty(number: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.app(.caption, weight: .bold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: badge, height: badge)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Candidate \(number): empty")
    }
}

/// A list number in a filled circle, matching the number on the board.
private struct CandidateNumber: View {
    let number: Int
    let color: Color
    let size: CGFloat
    let theme: BoardTheme

    var body: some View {
        Text("\(number)")
            .font(.app(.caption, weight: .heavy).monospacedDigit())
            .foregroundStyle(theme.isDark ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - The verdict

/// Leo's verdict on the list: the winner first, then the other moves from
/// strongest to weakest, each in plain words, and what the list scored.
private struct CandidateVerdictCard: View {
    let report: CandidateReport
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(Coach.current.name)'s verdict")
                    .font(.app(.headline))
                Spacer()
                TrainingChip(text: "+\(report.points)", symbol: "star.fill", color: theme.trainingAccent)
                    .accessibilityLabel("\(report.points) \(report.points == 1 ? "point" : "points")")
            }
            VStack(spacing: 10) {
                ForEach(report.rows) { row in
                    VerdictRow(row: row, theme: theme)
                }
            }
            Text(scoring)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, cornerRadius: 18)
    }

    /// Where the points came from, like "Winner on your list +2 · Leo's top three +1".
    private var scoring: String {
        var parts: [String] = []
        if report.foundAt != nil { parts.append("Winner on your list +2") }
        if report.foundAt == 0 { parts.append("first idea +1") }
        if report.otherMatches > 0 { parts.append("\(Coach.current.name)'s top three +\(report.otherMatches)") }
        return parts.isEmpty ? "No points this time. The winner is on the board in green." : parts.joined(separator: " · ")
    }
}

/// One move in the verdict: its place on the list (or a crown for the winner),
/// the move, Leo's word for it, and a tick when it counted.
private struct VerdictRow: View {
    let row: CandidateReport.Row
    let theme: BoardTheme
    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 22

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                marker
                move
                verdict
                Spacer(minLength: 4)
                tick
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    marker
                    move
                    Spacer(minLength: 4)
                    tick
                }
                verdict
                    .padding(.leading, badge + 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var green: Color { TrainingColor.green.color(on: theme) }

    @ViewBuilder
    private var marker: some View {
        if let listed = row.listed {
            CandidateNumber(number: listed + 1, color: row.isWinner ? green : TrainingColor.blue.color(on: theme),
                            size: badge, theme: theme)
        } else if row.isWinner {
            Image(systemName: "crown.fill")
                .font(.system(size: badge * 0.55, weight: .bold))
                .foregroundStyle(green)
                .frame(width: badge, height: badge)
                .background(green.opacity(0.16), in: Circle())
        } else {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: badge * 0.55, height: badge * 0.55)
                .frame(width: badge, height: badge)
        }
    }

    private var move: some View {
        Text(row.san)
            .font(.app(.body, weight: .semibold).monospacedDigit())
            .foregroundStyle(row.listed == nil && !row.isWinner ? Color.secondary : Color.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var verdict: some View {
        if let verdict = row.verdict {
            Text(verdict.words)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(verdict.color.map { $0.color(on: theme) } ?? Color.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var tick: some View {
        if row.isMatch {
            Image(systemName: "checkmark.circle.fill")
                .font(.app(.body))
                .foregroundStyle(green)
        }
    }

    private var spoken: String {
        var parts = [row.san]
        if let verdict = row.verdict { parts.append(verdict.words) }
        if row.isWinner { parts.append("the winning move") }
        if let listed = row.listed {
            parts.append("your candidate \(listed + 1)")
        } else if let rank = row.leoRank {
            parts.append("\(Coach.current.name)'s choice \(rank + 1)")
        }
        if row.isMatch { parts.append("counted") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The round

/// The end of a round: the score, how many winners were on the lists, the best
/// round so far, and Leo's line.
private struct CandidateRoundSummary: View {
    let session: CandidateSession
    let theme: BoardTheme
    let done: () -> Void

    var body: some View {
        let round = session.round
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Image(systemName: "list.number")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.trainingAccent)
                            .frame(width: 60, height: 60)
                            .background(theme.trainingAccent.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("\(round.points)")
                            .font(.app(.largeTitle, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.trainingAccent)
                        Text("points out of \(CandidateRound.maxPoints)")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                        if session.newBest {
                            TrainingChip(text: "New best round", symbol: "trophy.fill", color: theme.trainingAccent)
                        }
                        stats(round)
                            .padding(.top, 6)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .trainingCard(theme)
                    RoomMessage(text: round.summary, tone: round.found >= 3 ? .success : .coach, theme: theme)
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { session.newRound() }
                } label: {
                    Text("Another round")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                Button(action: done) {
                    Text("Done")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func stats(_ round: CandidateRound) -> some View {
        HStack(spacing: 0) {
            stat("\(round.found) of \(CandidateRound.length)", "winners found")
            Divider().frame(height: 34)
            stat("\(round.foundFirst)", "first ideas")
            if let best = session.bestRound {
                Divider().frame(height: 34)
                stat("\(best)", "best round")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.app(.headline).monospacedDigit())
            Text(label)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
