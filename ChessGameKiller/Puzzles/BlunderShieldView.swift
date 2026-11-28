import ChessKit
import SwiftUI

/// Blunder Shield: the board, a gold ring counting down, and two stone cards under the board.
/// One move is safe, the other loses something. The shield grows with every safe pick in a row.
struct BlunderShieldView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(\.dismiss) private var dismiss
    @State private var session: BlunderShieldSession?
    @AppStorage("haptics") private var hapticsOn = true
    private let engine: ChessEngine?

    /// The drill, with Stockfish naming the safe move in each puzzle. Needs
    /// `.environment(puzzleStore)`; with `.environment(trainingStore)` the player's own
    /// game mistakes come first.
    init(theme: BoardTheme, engine: ChessEngine? = StockfishEngine.shared) {
        self.theme = theme
        self.engine = engine
    }

    /// The drill with a session already made, for tests and previews.
    init(theme: BoardTheme, session: BlunderShieldSession) {
        self.theme = theme
        engine = nil
        _session = State(initialValue: session)
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - TrainingBoardView.sideRoom, geo.size.height * 0.48))
            VStack(spacing: 8) {
                header
                content(boardSide: side)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .screenScheme(theme)
        .tint(theme.trainingAccent)
        .task {
            await puzzles.load()
            begin()
        }
        .onDisappear { session?.cancel() }
        .sensoryFeedback(trigger: session?.outcome) { _, outcome in
            guard hapticsOn, let outcome else { return nil }
            return outcome.isSafe ? .success : .error
        }
    }

    private func begin() {
        if let session {
            session.start()
            return
        }
        let made = BlunderShieldSession(mistakes: training?.openMistakes ?? [], library: puzzles.library,
                                        rating: puzzles.progress.rating, engine: engine, store: puzzles,
                                        sounds: SoundPlayer.shared)
        session = made
        made.start()
    }

    // MARK: Header

    private var header: some View {
        RoomHeader(title: "Blunder Shield", subtitle: subtitle) {
            session?.cancel()
            dismiss()
        }
        .padding(.trailing, showsRing ? 60 : 0)
        .overlay(alignment: .trailing) {
            if showsRing, let session {
                ShieldRing(session: session, theme: theme)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }

    private var showsRing: Bool {
        guard let stage = session?.stage else { return false }
        return stage == .choosing || stage == .revealed
    }

    private var subtitle: String {
        guard let session else { return "Pick the safe move" }
        switch session.stage {
        case .choosing, .revealed:
            let side = session.position?.mover == .black ? "Black to move" : "White to move"
            return "Position \(session.number) of \(ShieldRound.length) · \(side)"
        case .loading: return "Setting up the next position"
        case .summary: return "Round complete"
        case .empty: return "Pick the safe move"
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(boardSide: CGFloat) -> some View {
        if let session {
            switch session.stage {
            case .choosing, .revealed:
                ShieldPositionView(session: session, theme: theme, boardSide: boardSide)
            case .loading:
                Spacer()
                HStack(spacing: 10) {
                    KnightWait(size: 18)
                    Text("Setting a trap…")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
            case .summary:
                ShieldRoundSummary(session: session, theme: theme) { dismiss() }
                    .transition(.opacity)
            case .empty:
                Spacer()
                RoomMessage(text: "I couldn't set up any positions just now. Try again in a moment.",
                            tone: .coach, theme: theme)
                    .padding(.horizontal, 16)
                Spacer()
            }
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }
    }
}

// MARK: - The ring

/// The gold ring in the corner: it empties as the seconds run out, with the seconds in it.
private struct ShieldRing: View {
    let session: BlunderShieldSession
    let theme: BoardTheme
    private let size: CGFloat = 44

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: session.stage != .choosing)) { timeline in
            let left = remaining(at: timeline.date)
            ZStack {
                Circle()
                    .stroke(theme.trainingAccent.opacity(0.18), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: left / session.limit)
                    .stroke(theme.trainingAccent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(left.rounded(.up)))")
                    .font(.app(.headline, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.trainingAccent)
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(left.rounded(.up))) seconds left")
        }
    }

    private func remaining(at date: Date) -> Double {
        guard session.stage == .choosing else {
            return session.outcome == .timedOut ? 0 : max(0, session.limit - (session.pickedAt ?? date).timeIntervalSince(session.startedAt))
        }
        return max(0, session.limit - date.timeIntervalSince(session.startedAt))
    }
}

// MARK: - One position

/// The board, the question (or Leo's word on the pick), the two cards and the shield.
private struct ShieldPositionView: View {
    let session: BlunderShieldSession
    let theme: BoardTheme
    let boardSide: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if let game = session.game {
                        TrainerBoard(game: game, theme: theme, side: boardSide,
                                     flipped: session.position?.mover == .black,
                                     arrows: session.arrows,
                                     turn: session.position?.mover, showsTurn: session.stage == .choosing)
                            .id(session.position?.id)
                    }
                    if session.stage == .revealed {
                        RoomMessage(text: session.verdict, tone: session.outcome?.isSafe == true ? .success : .wrong,
                                    theme: theme)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    } else {
                        Text(question)
                            .font(.app(.headline))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                    }
                    HStack(spacing: 12) {
                        ForEach(session.options) { option in
                            ShieldCard(option: option, session: session, theme: theme)
                        }
                    }
                    .padding(.horizontal, 16)
                    ShieldCount(shield: session.shield, best: session.best, theme: theme)
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            if session.stage == .revealed {
                Button {
                    withAnimation(.snappy) { session.next() }
                } label: {
                    Text(session.round.isFinished ? "See your round" : "Next position")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: session.stage)
    }

    private var question: String {
        session.position?.source == .yours
            ? "From one of your games. One of these loses something. Pick the safe one."
            : "One of these loses something. Pick the safe one."
    }
}

/// One of the two stone cards: the move, big, and what it does in small words. After the pick
/// the safe card glows green and the other red.
private struct ShieldCard: View {
    let option: ShieldOption
    let session: BlunderShieldSession
    let theme: BoardTheme

    var body: some View {
        Button {
            withAnimation(.snappy) { session.pick(option) }
        } label: {
            VStack(spacing: 4) {
                Text(option.san)
                    .font(.display(size: 26, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(option.words)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.horizontal, 8)
            .trainingCard(theme, tint: tint, cornerRadius: 20)
            .overlay(alignment: .topTrailing) { mark }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(session.stage != .choosing)
        .opacity(faded ? 0.55 : 1)
        .accessibilityLabel("\(option.san), \(option.words)")
        .accessibilityIdentifier("Shield move")
        .accessibilityValue(accessibilityValue)
    }

    private var revealed: Bool { session.stage == .revealed }

    private var tint: Color? {
        guard revealed else { return nil }
        return (option.isSafe ? TrainingColor.green : TrainingColor.red).color(on: theme)
    }

    /// The card not picked fades a little, unless it was the safe one the player missed.
    private var faded: Bool {
        revealed && session.picked != nil && session.picked != option && !option.isSafe
    }

    @ViewBuilder
    private var mark: some View {
        if revealed {
            Image(systemName: option.isSafe ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint ?? theme.trainingAccent)
                .padding(10)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var accessibilityValue: String {
        guard revealed else { return "" }
        return option.isSafe ? "Safe" : "Loses something"
    }
}

/// "Shield 6 · Best 9" under the cards.
private struct ShieldCount: View {
    let shield: Int
    let best: Int
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: shield)
            Text("Shield \(shield) · Best \(best)")
                .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(value: Double(shield)))
        }
        .foregroundStyle(theme.trainingAccent)
        .animation(.snappy, value: shield)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shield \(shield). Best \(best).")
    }
}

// MARK: - The round

/// The end of a round: how many were safe, the longest shield, the best ever, and Leo's line.
private struct ShieldRoundSummary: View {
    let session: BlunderShieldSession
    let theme: BoardTheme
    let done: () -> Void

    var body: some View {
        let round = session.round
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        if theme.screenTone != nil {
                            JewelIcon(symbol: "shield.lefthalf.filled", stone: TrainDoor.puzzles.stone, size: 60)
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(theme.trainingAccent)
                                .frame(width: 60, height: 60)
                                .background(theme.trainingAccent.opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        Text("\(round.safe)")
                            .font(.app(.largeTitle, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.trainingAccent)
                        Text("safe out of \(round.outcomes.count)")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                        if session.newBest {
                            TrainingChip(text: "New best shield", symbol: "trophy.fill", color: theme.trainingAccent)
                        }
                        HStack(spacing: 0) {
                            stat("\(round.longestRun)", "longest shield")
                            Divider().frame(height: 34)
                            stat("\(session.best)", "best ever")
                        }
                        .padding(.top, 6)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .trainingCard(theme)
                    RoomMessage(text: round.summary, tone: round.safe >= 8 ? .success : .coach, theme: theme)
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
