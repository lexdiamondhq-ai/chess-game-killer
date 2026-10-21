import ChessKit
import SwiftUI

/// The coach as one circle at the bottom of the screen. Its ring is the live
/// evaluation, Gold against Violet. After a move it stretches sideways to show
/// the verdict for a moment, then shrinks back. Tapped, it unfolds into the
/// full coach panel: the eval bar, the two best moves, and the game's controls.
struct CoachOrb: View {
    let match: MatchController
    let theme: BoardTheme
    @Binding var isExpanded: Bool
    /// True while the orb is stretched to show a verdict; the parent hides what sits beside it.
    @Binding var isPeeking: Bool
    /// How tall the unfolded panel may get before its contents scroll, so the board keeps its room.
    var expandedMaxHeight: CGFloat? = nil
    let newGame: () -> Void

    @State private var peekTask: Task<Void, Never>?
    @AppStorage("haptics") private var hapticsOn = true
    /// Coach Leo, when the app has training. His tips show in the open panel.
    @Environment(GameCoach.self) private var gameCoach: GameCoach?

    static let orbSize: CGFloat = 68

    private var accent: Color { theme.accent ?? .accentColor }
    private var tint: Color {
        if match.isOver { return theme.accent ?? .accentColor }
        return match.review?.grade.color ?? accent
    }

    var body: some View {
        ZStack {
            if isExpanded {
                CoachPanel(match: match, theme: theme, newGame: newGame, collapse: collapse)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if isPeeking, let review = match.review {
                PeekRow(review: review, theme: theme)
                    .transition(.opacity)
            } else {
                OrbFace(match: match, theme: theme)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: isExpanded || isPeeking ? .infinity : Self.orbSize)
        .frame(minHeight: isExpanded ? nil : Self.orbSize, maxHeight: isExpanded ? expandedMaxHeight : Self.orbSize)
        .background { orbBackground }
        .overlay(alignment: .topTrailing) {
            ZStack {
                if !isExpanded, !isPeeking, let gameCoach, let moment = gameCoach.moment {
                    CoachOrbBadge(moment: moment, theme: theme)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .offset(x: 6, y: -6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: gameCoach?.moment)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.orbSize / 2, style: .continuous))
        .onTapGesture {
            if !isExpanded { expand() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if isExpanded, value.translation.height > 60 { collapse() }
                }
        )
        .onChange(of: match.review?.id) { _, id in
            guard id != nil, !isExpanded else { return }
            peek()
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { cancelPeek() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isExpanded) { _, _ in hapticsOn }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coach")
        .accessibilityHint(isExpanded ? "Swipe down to close" : "Tap to open the coach")
        .accessibilityAction(named: isExpanded ? "Close" : "Open") {
            if isExpanded { collapse() } else { expand() }
        }
    }

    // MARK: Opening and closing

    private func expand() {
        cancelPeek()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isExpanded = false
        }
    }

    /// Shows the verdict in the stretched orb for a few seconds.
    private func peek() {
        peekTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isPeeking = true
        }
        peekTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isPeeking = false
            }
        }
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
        if isPeeking {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isPeeking = false
            }
        }
    }

    // MARK: Background

    private var orbBackground: some View {
        let shape = RoundedRectangle(cornerRadius: isExpanded ? 30 : Self.orbSize / 2, style: .continuous)
        return shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [tint.opacity(theme.glows ? 0.9 : 0.45), tint.opacity(0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            }
            .shadow(color: theme.glows ? tint.opacity(0.35) : .black.opacity(0.12),
                    radius: theme.glows ? 16 : 10, y: theme.glows ? 0 : 3)
    }
}

// MARK: - The orb itself

/// The circle: the eval ring around the last verdict's mark.
private struct OrbFace: View {
    let match: MatchController
    let theme: BoardTheme

    var body: some View {
        ZStack {
            if match.isComputerThinking {
                ThinkingRing(color: match.setup.level.rival.hue)
            } else {
                EvalRing(share: goldShare, theme: theme)
            }
            mark
        }
        .frame(width: CoachOrb.orbSize, height: CoachOrb.orbSize)
        .accessibilityLabel(accessibilityText)
    }

    /// Gold's (White's) share of the ring, 0 to 1.
    private var goldShare: Double {
        if match.isOver {
            guard let winner = match.winner else { return 0.5 }
            return winner == .white ? 1 : 0
        }
        return ((match.evaluation?.winningChances ?? 0) + 1) / 2
    }

    @ViewBuilder
    private var mark: some View {
        if match.isComputerThinking {
            RivalSigil(rival: match.setup.level.rival, size: 36, glows: theme.glows)
        } else if match.isOver {
            if let winner = match.winner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.sideColor(winner))
                    .shadow(color: theme.glows ? theme.sideColor(winner).opacity(0.9) : .clear, radius: 8)
            } else {
                Text("½")
                    .font(.system(size: 24, weight: .heavy, design: .themed))
                    .foregroundStyle(.secondary)
            }
        } else if let review = match.review {
            Group {
                switch review.grade.mark {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 22, weight: .bold))
                case .text(let text):
                    Text(text).font(.system(size: 22, weight: .heavy, design: .themed))
                }
            }
            .foregroundStyle(review.grade.color)
            .shadow(color: theme.glows ? review.grade.color.opacity(0.9) : .clear, radius: 8)
            .contentTransition(.symbolEffect(.replace))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent ?? .accentColor)
                .shadow(color: theme.glows ? (theme.accent ?? .accentColor).opacity(0.9) : .clear, radius: 8)
        }
    }

    private var accessibilityText: String {
        if match.isComputerThinking { return "\(match.setup.level.rival.name) is thinking" }
        if match.isOver {
            return match.winner.map { "\(theme.name(of: $0)) wins" } ?? "Draw"
        }
        var text = match.review.map { "\($0.title). \($0.detail)" } ?? "Your coach"
        if let evaluation = match.evaluation {
            text += " Evaluation \(evaluation.label) for \(theme.whiteName)."
        }
        return text
    }
}

/// A ring split between the two sides: Gold's part from the top, clockwise.
struct EvalRing: View {
    /// Gold's (White's) share, 0 to 1.
    let share: Double
    let theme: BoardTheme
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.blackSide.opacity(theme.isDark ? 0.9 : 0.85), lineWidth: lineWidth)
                .shadow(color: theme.glows ? theme.blackSide.opacity(0.8) : .clear, radius: 4)
            Circle()
                .trim(from: 0, to: max(0, min(1, share)))
                .stroke(theme.whiteSide, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.glows ? (theme.whiteGlow ?? theme.whiteSide).opacity(0.9) : .black.opacity(0.35),
                        radius: theme.glows ? 4 : 1)
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: share)
        .accessibilityHidden(true)
    }
}

/// A sweeping arc in the rival's color while the computer thinks. With Reduce
/// Motion on it steps round once every four seconds instead of sweeping.
private struct ThinkingRing: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let steps = (context.date.timeIntervalSinceReferenceDate / 0.5).rounded(.down)
                    arc(turn: steps.truncatingRemainder(dividingBy: 8) / 8)
                }
            } else {
                TimelineView(.animation) { context in
                    let seconds = context.date.timeIntervalSinceReferenceDate
                    arc(turn: seconds.truncatingRemainder(dividingBy: 1.1) / 1.1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The ring with the arc `turn` of the way round, 0 to 1.
    private func arc(turn: Double) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(turn * 360 - 90))
                .shadow(color: color.opacity(0.9), radius: 5)
        }
        .padding(1.75)
    }
}

// MARK: - The stretched orb

/// The verdict, shown in the stretched orb right after a move.
private struct PeekRow: View {
    let review: MoveReview
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 12) {
            GradeBadge(grade: review.grade, glows: theme.glows)
            VStack(alignment: .leading, spacing: 1) {
                Text(review.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(review.grade.color)
                Text(review.shortDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let evaluation = review.evaluationForWhite {
                EvalChip(text: evaluation.label, color: review.grade.color)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: CoachOrb.orbSize)
        // The stretched orb is as tall as the orb, so the type stops growing at the
        // largest regular size instead of spilling past the pill.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
    }
}

/// A small rounded score like "+0.3".
struct EvalChip: View {
    let text: String
    let color: Color
    var large = false

    var body: some View {
        Text(text)
            .font(.system(large ? .subheadline : .footnote, design: .themed).weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, large ? 10 : 8)
            .padding(.vertical, large ? 5 : 4)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Score \(text)")
    }
}

// MARK: - The expanded coach

/// Everything the coach knows, in the unfolded orb.
private struct CoachPanel: View {
    let match: MatchController
    let theme: BoardTheme
    let newGame: () -> Void
    let collapse: () -> Void

    @AppStorage("showBestMoves") private var showBestMoves = true
    @Environment(GameCoach.self) private var gameCoach: GameCoach?
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @State private var reel: GameReel?
    @State private var rewind: SavedGame?
    @State private var showingGames = false
    @Environment(GameVault.self) private var vault: GameVault?

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .onTapGesture(perform: collapse)
                .accessibilityHidden(true)
            // Where it all fits the panel is its natural height; on a short screen
            // the rest scrolls under the handle instead of squeezing the board.
            ViewThatFits(in: .vertical) {
                content
                ScrollView {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.3), value: match.hints)
        .animation(.snappy(duration: 0.3), value: match.isComputerThinking)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if let gameCoach, let training, GameCoachRow.hasContent(coach: gameCoach, match: match) {
                GameCoachRow(coach: gameCoach, store: training, match: match, theme: theme)
                    .padding(.top, 10)
            }
            EvalBar(share: evalShare, label: evalLabel, theme: theme)
                .padding(.top, 12)
            if match.isOver {
                summary.padding(.top, 12)
                endButtons.padding(.top, 10)
                HStack(spacing: 8) {
                    rewindButton
                    reelButton
                }
                .padding(.top, 8)
            } else {
                bestMoves.padding(.top, 12)
                actions.padding(.top, 8)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if match.isOver {
                resultBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(resultTitle).font(.headline).foregroundStyle(resultColor)
                    Text(resultDetail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                EvalChip(text: scoreline, color: resultColor, large: true)
            } else if match.isComputerThinking {
                ThinkingRing(color: match.setup.level.rival.hue).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(match.setup.level.rival.name) is thinking").font(.headline)
                    Text("Your move is graded here as soon as it answers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            } else if match.engineFailed {
                // Ahead of the last verdict, which is about a move that is no longer the news.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3).foregroundStyle(accent).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach offline").font(.headline)
                    Text("Stockfish didn't answer. Undo and try again, or play a friend.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            } else if let review = match.review {
                GradeBadge(grade: review.grade, glows: theme.glows)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title).font(.headline).foregroundStyle(review.grade.color)
                    Text(review.detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let evaluation = review.evaluationForWhite {
                    EvalChip(text: evaluation.label, color: review.grade.color, large: true)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.title3).foregroundStyle(accent).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your coach").font(.headline)
                    Text("Make a move and I'll tell you how good it was.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resultColor: Color {
        if let winner = match.winner { return theme.sideColor(winner) }
        return .secondary
    }

    private var resultBadge: some View {
        ZStack {
            Circle().fill(resultColor)
            Image(systemName: match.winner == nil ? "equal" : "crown.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
        }
        .frame(width: 38, height: 38)
        .shadow(color: theme.glows ? resultColor.opacity(0.8) : .clear, radius: 8)
    }

    private var resultTitle: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser): return "\(theme.name(of: loser.opposite)) wins on time"
            case .timeoutDraw: return "Draw"
            }
        }
        if match.game.winner != nil { return "Checkmate!" }
        return "Draw"
    }

    private var resultDetail: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser):
                return "\(theme.name(of: loser)) ran out of time."
            case .timeoutDraw(let flagged):
                return "\(theme.name(of: flagged)) ran out of time, but \(theme.name(of: flagged.opposite)) cannot checkmate."
            }
        }
        if let winner = match.game.winner {
            let last = match.game.moves.last ?? "The last move"
            return "\(last) ends the game. \(theme.name(of: winner)) wins."
        }
        return match.game.status(white: theme.whiteName, black: theme.blackName)
    }

    private var scoreline: String {
        guard let winner = match.winner else { return "½–½" }
        return winner == .white ? "1–0" : "0–1"
    }

    // MARK: Evaluation

    private var evalShare: Double {
        if match.isOver {
            guard let winner = match.winner else { return 0.5 }
            return winner == .white ? 1 : 0
        }
        return ((match.evaluation?.winningChances ?? 0) + 1) / 2
    }

    private var evalLabel: String {
        if match.isOver {
            guard let winner = match.winner else { return "Draw" }
            return "\(theme.name(of: winner)) wins"
        }
        return match.evaluation?.label ?? "0.0"
    }

    // MARK: Best moves

    @ViewBuilder
    private var bestMoves: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showBestMoves ? "Best moves now · tap to play one" : "Hints are off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .textCase(.uppercase)
            if showBestMoves {
                if match.engineFailed {
                    Text("Stockfish is offline, so there are no best moves to show.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if match.hints.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(match.isComputerThinking ? "Waiting for \(match.setup.level.rival.name)" : "Looking at the position")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(match.hints) { hint in
                        HintRow(hint: hint, mover: match.game.sideToMove, theme: theme) {
                            match.play(hint)
                            collapse()
                        }
                    }
                }
            } else {
                Button {
                    showBestMoves = true
                } label: {
                    Label("Show the two best moves", systemImage: "lightbulb.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .frame(minHeight: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 6) {
            ActionButton(title: "Undo", symbol: "arrow.uturn.backward", theme: theme) {
                withAnimation(.snappy(duration: 0.22)) { match.undo() }
            }
            .disabled(!match.canUndo)
            ActionButton(title: "Hints", symbol: showBestMoves ? "lightbulb.fill" : "lightbulb.slash", isOn: showBestMoves, theme: theme) {
                showBestMoves.toggle()
            }
            if gameCoach != nil {
                ThinkActionButton(match: match, theme: theme)
            }
            ActionButton(title: "Flip", symbol: "arrow.triangle.2.circlepath", theme: theme) {
                withAnimation(.snappy(duration: 0.45)) { match.flipBoard() }
            }
            if vault != nil {
                ActionButton(title: "Games", symbol: "backward.circle", theme: theme) {
                    showingGames = true
                }
            }
            ActionButton(title: "New game", symbol: "plus", theme: theme) {
                collapse()
                newGame()
            }
        }
        .fullScreenCover(isPresented: $showingGames) {
            if let vault {
                RewindGamesView(theme: theme) { game in
                    collapse()
                    var setup = match.setup
                    if let raw = game.level, let level = MatchController.Level(rawValue: raw) {
                        setup.opponent = .computer
                        setup.level = level
                        setup.playerColor = game.playerColor
                    }
                    withAnimation(.snappy) { match.start(setup) }
                }
                .environment(vault)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            StatTile(title: "Accuracy", value: match.accuracy.map { "\($0)%" } ?? "–",
                     color: MoveReview.Grade.best.color, theme: theme)
            StatTile(title: "Best", value: "\(match.gradeCounts[.best, default: 0] + match.gradeCounts[.checkmate, default: 0])",
                     color: .primary, theme: theme)
            StatTile(title: "Mistakes", value: "\(match.gradeCounts[.mistake, default: 0])",
                     color: MoveReview.Grade.mistake.color, theme: theme)
            StatTile(title: "Blunders", value: "\(match.gradeCounts[.blunder, default: 0])",
                     color: MoveReview.Grade.blunder.color, theme: theme)
        }
    }

    /// Rewind: the game's line, Leo on each moment, and a second chance at the mistakes.
    private var rewindButton: some View {
        Button {
            guard let game = match.savedGame() else { return }
            vault?.record(game)
            rewind = vault?.game(game.id) ?? game
        } label: {
            Label("Rewind", systemImage: "backward.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(accent)
        .fullScreenCover(item: $rewind) { game in
            if let vault {
                RewindView(game: game, theme: theme) { _ in
                    collapse()
                    withAnimation(.snappy) { match.rematch() }
                }
                .environment(vault)
            }
        }
    }

    /// Leo's 30-second story of the game, to watch and share.
    private var reelButton: some View {
        Button {
            reel = match.highlightReel()
        } label: {
            Label("Highlight reel", systemImage: "film.stack")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(accent)
        .fullScreenCover(item: $reel) { reel in
            HighlightReelView(reel: reel, theme: theme)
        }
    }

    private var endButtons: some View {
        HStack(spacing: 10) {
            Button {
                collapse()
                withAnimation(.snappy) { match.rematch() }
            } label: {
                Label("Rematch", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(accent)
            .foregroundStyle(theme.isDark ? Color.black : Color.white)
            .shadow(color: theme.glows ? accent.opacity(0.5) : .clear, radius: 12)

            Button {
                collapse()
                newGame()
            } label: {
                Label("New game", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
        }
    }
}

/// The Gold-versus-Violet bar with the score riding on the boundary.
struct EvalBar: View {
    /// Gold's (White's) share, 0 to 1.
    let share: Double
    let label: String
    let theme: BoardTheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = max(0, min(1, share))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.blackSide.opacity(theme.isDark ? 0.55 : 0.8))
                    .shadow(color: theme.glows ? theme.blackSide.opacity(0.25) : .clear, radius: 12)
                Capsule()
                    .fill(LinearGradient(colors: [theme.whiteSide.opacity(0.75), theme.whiteSide],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(12, width * clamped))
                    .shadow(color: theme.glows ? (theme.whiteGlow ?? theme.whiteSide).opacity(0.6) : .black.opacity(0.2),
                            radius: theme.glows ? 12 : 2)
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .themed).monospacedDigit())
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white, in: Capsule())
                    .fixedSize()
                    .position(x: min(max(width * clamped, 28), width - 28), y: geo.size.height / 2)
            }
        }
        .frame(height: 12)
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: share)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evaluation \(label)")
    }
}

/// One of the best moves: how it is drawn, what it is, how good it is, and a button to play it.
private struct HintRow: View {
    let hint: MoveHint
    /// Whose move it is. The hint's score is from their side; the row shows White's, like the eval bar.
    let mover: Piece.Color
    let theme: BoardTheme
    let play: () -> Void

    private var isBest: Bool { hint.rank == 0 }
    private var score: String { (mover == .white ? hint.evaluation : hint.evaluation.flipped).label }

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                HintSwatch(color: isBest ? theme.bestArrow : theme.secondArrow, dashed: !isBest, glow: theme.glows ? theme.arrowGlow : nil)
                Text(hint.san)
                    .font(.system(.body, design: .themed).weight(.bold))
                    .frame(minWidth: 46, alignment: .leading)
                Text(isBest ? "Best" : "Next best")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(score)
                    .font(.system(.footnote, design: .themed).weight(.bold).monospacedDigit())
                    .foregroundStyle(isBest ? theme.bestArrow : Color.secondary)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent ?? .accentColor)
                    .frame(width: 30, height: 30)
                    .background((theme.accent ?? .accentColor).opacity(0.16), in: Circle())
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(theme.isDark ? 0.05 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(theme.isDark ? 0.09 : 0.08), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isBest ? "Best" : "Next best") move \(hint.san), score \(score)")
        .accessibilityHint("Plays it for you")
    }
}

/// A short line in an arrow's style.
private struct HintSwatch: View {
    let color: Color
    let dashed: Bool
    let glow: Color?

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 2, y: 5))
            path.addLine(to: CGPoint(x: 26, y: 5))
        }
        .stroke(color, style: StrokeStyle(lineWidth: dashed ? 3 : 4, lineCap: dashed ? .butt : .round,
                                          dash: dashed ? [5, 3] : []))
        .shadow(color: glow?.opacity(dashed ? 0.5 : 0.9) ?? .clear, radius: 4)
        .frame(width: 28, height: 10)
        .accessibilityHidden(true)
    }
}

/// A round icon button with a caption under it.
private struct ActionButton: View {
    let title: String
    let symbol: String
    /// Set for a toggle, so VoiceOver can say which way it is.
    var isOn: Bool? = nil
    let theme: BoardTheme
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var accent: Color { theme.accent ?? .accentColor }
    private var lit: Bool { isOn == true }
    /// What VoiceOver says after the name: the state of a toggle, nothing for a plain button.
    private var spokenState: String { isOn.map { $0 ? "On" : "Off" } ?? "" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(theme.isDark ? 0.07 : 0.05), in: Circle())
                    .overlay(Circle().strokeBorder(lit ? accent.opacity(0.5) : Color.primary.opacity(0.11), lineWidth: 1))
                    .shadow(color: lit && theme.glows ? accent.opacity(0.25) : .clear, radius: 10)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(lit ? accent : Color.primary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(spokenState)
        .accessibilityAddTraits(isOn == nil ? [] : .isToggle)
    }
}

/// One number from the game's summary.
private struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    let theme: BoardTheme

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .themed).weight(.heavy).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(theme.isDark ? 0.05 : 0.04))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(theme.isDark ? 0.09 : 0.08), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }
}

extension MoveReview {
    /// The score after the move from White's point of view, the way the eval bar
    /// and ring show it. `evaluation` itself is from the mover's side.
    var evaluationForWhite: Evaluation? {
        guard let evaluation else { return nil }
        let moverWasBlack = fenBefore?.split(separator: " ").dropFirst().first == "b"
        return moverWasBlack ? evaluation.flipped : evaluation
    }

    /// One short line for the stretched orb.
    var shortDetail: String {
        let better = best ?? "another move"
        switch grade {
        case .checkmate: return "\(played) ends it. Beautiful."
        case .best: return "\(played) is Stockfish's choice too."
        case .excellent: return "\(played) · nearly as good as \(better)."
        case .good: return "\(played) · \(better) was a little better."
        case .inaccuracy: return "\(played) · \(better) was better."
        case .mistake: return "\(played) · \(better) was much better."
        case .blunder: return "\(played) · \(better) was the move."
        }
    }
}
