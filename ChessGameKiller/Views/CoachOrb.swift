import Accessibility
import ChessKit
import SwiftUI

/// The coach as one circle at the bottom of the screen. Its ring is the player's share
/// of the game and its face the grade of their last move. Tapped, it unfolds into the
/// full coach panel: the grade, the eval bar, Leo's picks and the game's controls, and
/// after a game the result and what comes next.
struct CoachOrb: View {
    let match: MatchController
    let theme: BoardTheme
    @Binding var isExpanded: Bool
    /// How tall the unfolded panel may get before its contents scroll, so the board keeps its room.
    var expandedMaxHeight: CGFloat? = nil
    let newGame: () -> Void
    /// Opens the player's saved games.
    let showGames: () -> Void
    /// Opens Talk it through for the position on the board. Nil leaves it out.
    var talk: (() -> Void)? = nil

    @AppStorage("haptics") private var hapticsOn = true
    /// Counts the times the person opened or closed the panel, for a light tap each.
    /// The panel also opens by itself when a game ends, and that stays silent.
    @State private var touches = 0
    /// Counts the holds on the closed orb that opened Talk it through, for a firmer tap each.
    @State private var talkHolds = 0
    /// The move Leo last played for the person, by the game's move count. Moves he plays
    /// aren't graded, so the panel mustn't promise a grade for one.
    @State private var coachMove: Int?
    /// Coach Leo, when the app has training. His tips show in the open panel.
    @Environment(GameCoach.self) private var gameCoach: GameCoach?

    static let orbSize: CGFloat = 68

    private var accent: Color { theme.accent ?? .accentColor }
    private var tint: Color {
        if match.isOver { return accent }
        return match.review?.grade.color(on: theme) ?? accent
    }

    var body: some View {
        ZStack {
            if isExpanded {
                CoachPanel(match: match, theme: theme, coachMove: $coachMove, newGame: newGame, showGames: showGames,
                           talk: talk, close: { collapse(felt: true) }, collapse: { collapse() })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                OrbFace(match: match, theme: theme, open: { expand() })
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : Self.orbSize)
        .frame(minHeight: isExpanded ? nil : Self.orbSize, maxHeight: isExpanded ? expandedMaxHeight : Self.orbSize)
        .background { orbBackground }
        .overlay(alignment: .topTrailing) {
            ZStack {
                if !isExpanded, let gameCoach, let moment = gameCoach.moment {
                    CoachOrbBadge(moment: moment, theme: theme)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .offset(x: 6, y: -6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: gameCoach?.moment)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.orbSize / 2, style: .continuous))
        // Only on the closed orb: the open panel's buttons and scrolling keep their own gestures.
        .gesture(orbGesture, including: isExpanded ? .subviews : .all)
        .onChange(of: match.review?.id) { _, id in
            // Once the game is over the result is said instead, and it names the mate.
            guard id != nil, !match.isOver, let review = match.review else { return }
            announce("\(review.title). \(review.shortDetail.replacingOccurrences(of: " · ", with: ", "))")
        }
        .onChange(of: match.isOver) { _, over in
            guard over else { return }
            let result = ResultText(match: match)
            announce("\(result.title). \(result.detail)")
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: touches) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: talkHolds) { (_: Int, _: Int) -> Bool in hapticsOn }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coach")
        .accessibilityHint(isExpanded ? "Double-tap to close" : "Double-tap to open the coach")
        .accessibilityAction(named: isExpanded ? "Close" : "Open") {
            if isExpanded { collapse(felt: true) } else { expand() }
        }
        .accessibilityActions {
            if let talk, match.canTalkItThrough {
                Button("Talk it through", action: talk)
            }
        }
    }

    // MARK: Opening and closing

    /// A tap opens the panel. A hold goes straight to Talk it through on the player's turn, and
    /// opens the panel like a tap any other time. The hold is tried first, so a tap waits for it to fail.
    private var orbGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in holdToTalk() }
            .exclusively(before: TapGesture().onEnded { _ in expand() })
    }

    private func holdToTalk() {
        guard !isExpanded else { return }
        guard let talk, match.canTalkItThrough else {
            expand()
            return
        }
        talkHolds += 1
        talk()
    }

    /// Opens the panel at the person's tap, with a light tap back.
    private func expand() {
        touches += 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isExpanded = true
        }
    }

    /// Closes the panel. `felt` when the person closed it themselves; a button that
    /// closes it on the way to something else stays quiet.
    private func collapse(felt: Bool = false) {
        if felt { touches += 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isExpanded = false
        }
    }

    /// Read out by VoiceOver, when it is on.
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Background

    /// The orb sits on the dock's glass, so it has no glass of its own (glass on glass turns
    /// muddy): a faint well while it is round or stretched for a verdict, and nothing once it
    /// unfolds, when the dock's glass grows to hold the panel.
    @ViewBuilder
    private var orbBackground: some View {
        if !isExpanded {
            let shape = RoundedRectangle(cornerRadius: Self.orbSize / 2, style: .continuous)
            shape
                .fill(Color.primary.opacity(theme.isDark ? 0.055 : 0.04))
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [tint.opacity(theme.glows ? 0.9 : 0.35), Color.primary.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75
                    )
                }
                .shadow(color: theme.glows ? tint.opacity(0.35) : .clear, radius: 16)
                .transition(.opacity)
        }
    }
}

// MARK: - The game from the player's side

private extension MatchController {
    /// The engine's score turned to the player's side, as the Big Board strip shows it:
    /// plus is good for them. `whiteView` is from White's side, like `evaluation`.
    func forPlayer(_ whiteView: Evaluation) -> Evaluation {
        setup.playerColor == .white ? whiteView : whiteView.flipped
    }

    /// True when the player won, false when they lost, nil for a draw or a game still on.
    var playerWon: Bool? { winner.map { $0 == setup.playerColor } }

    /// The player's share of the game, 0 to 1: all of it once they have won, none once they have lost.
    var playerShare: Double {
        if isOver {
            guard let won = playerWon else { return 0.5 }
            return won ? 1 : 0
        }
        guard let evaluation else { return 0.5 }
        return (forPlayer(evaluation).winningChances + 1) / 2
    }
}

/// How a game ended, in words, from the player's side: "you", and the rival by name.
@MainActor
private struct ResultText {
    let match: MatchController

    private var rival: String { match.setup.level.rival.name }
    private var player: Piece.Color { match.setup.playerColor }

    var title: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser):
                return loser == player ? "\(rival) wins on time" : "You win on time"
            case .timeoutDraw:
                return "Draw"
            case .resigned(let loser):
                return loser == player ? "You resigned" : "\(rival) resigns"
            }
        }
        guard let winner = match.game.winner else { return "Draw" }
        return winner == player ? "You win" : "\(rival) wins"
    }

    var detail: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser):
                return loser == player ? "Your clock ran out." : "\(rival)'s clock ran out."
            case .timeoutDraw(let flagged):
                return flagged == player
                    ? "Your clock ran out, but \(rival) can't checkmate with what's left."
                    : "\(rival)'s clock ran out, but you can't checkmate with what's left."
            case .resigned(let loser):
                return loser == player ? "\(rival) takes this one." : "You win. There was no way back for \(rival)."
            }
        }
        if match.game.winner != nil {
            return match.game.moves.last.map { "Checkmate with \($0)." } ?? "Checkmate."
        }
        if case .draw(let reason) = match.game.state {
            switch reason {
            case .stalemate: return "Stalemate: no legal move, and no check."
            case .repetition: return "The same position came up three times."
            case .fiftyMoves: return "Fifty moves without a capture or a pawn move."
            case .insufficientMaterial: return "Neither side has enough left to checkmate."
            case .agreement: return "Both sides agreed to a draw."
            }
        }
        return ""
    }
}

// MARK: - The orb itself

/// The circle: the player's share of the game around the mark of the last grade.
private struct OrbFace: View {
    let match: MatchController
    let theme: BoardTheme
    /// What a VoiceOver double-tap does: the same as a tap.
    let open: () -> Void

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        ZStack {
            EvalRing(share: match.playerShare, theme: theme)
            mark
        }
        .frame(width: CoachOrb.orbSize, height: CoachOrb.orbSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to open the coach")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    @ViewBuilder
    private var mark: some View {
        if match.isComputerThinking {
            ThinkingSigil(rival: match.setup.level.rival, size: 36, glows: theme.glows)
        } else if match.isOver {
            // What the result means to the player, never a side's own color.
            if let won = match.playerWon {
                Image(systemName: won ? "crown.fill" : "flag.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(won ? accent : Color.primary.opacity(0.85))
                    .shadow(color: theme.glows && won ? accent.opacity(0.9) : .clear, radius: 8)
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
            .foregroundStyle(review.grade.color(on: theme))
            .shadow(color: theme.glows ? review.grade.color(on: theme).opacity(0.9) : .clear, radius: 8)
            .contentTransition(.symbolEffect(.replace))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: theme.glows ? accent.opacity(0.9) : .clear, radius: 8)
        }
    }

    private var accessibilityText: String {
        if match.isComputerThinking { return "\(match.setup.level.rival.name) is thinking" }
        if match.isOver { return ResultText(match: match).title }
        var text = match.review.map { "\($0.title). \($0.detail)" } ?? "Leo, your coach."
        if let evaluation = match.evaluation {
            text += " Score \(match.forPlayer(evaluation).label) for you."
        }
        return text
    }
}

/// A gauge round the orb: the player's share of the game against the rival's. Theirs
/// fills in the accent from the bottom, clockwise; the rest is the rival's. The two meet
/// at the tick at the top when the game is even.
struct EvalRing: View {
    /// The player's share, 0 to 1.
    let share: Double
    let theme: BoardTheme
    var lineWidth: CGFloat = 3.5

    /// The rival's part of the ring and the bar: light enough to read as a share on
    /// every look, not as an empty track.
    static let rivalTone = Color.primary.opacity(0.3)
    /// The "even" tick.
    static let tickTone = Color.primary.opacity(0.8)

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.rivalTone, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, share)))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(90))
                .shadow(color: theme.glows ? accent.opacity(0.9) : .clear, radius: 4)
            // Across the ring at the top, and a little into the orb so it shows on the accent too.
            Rectangle()
                .fill(Self.tickTone)
                .frame(width: 1, height: lineWidth + 3)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -lineWidth / 2)
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: share)
        .accessibilityHidden(true)
    }
}

/// The rival's sigil breathing slowly while it thinks: a turn under way, not a spinner.
/// With Reduce Motion on it holds still.
private struct ThinkingSigil: View {
    let rival: Rival
    let size: CGFloat
    let glows: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            RivalSigil(rival: rival, size: size, glows: glows)
        } else {
            RivalSigil(rival: rival, size: size, glows: glows)
                .phaseAnimator([false, true]) { sigil, full in
                    sigil
                        .scaleEffect(full ? 1 : 0.88)
                        .opacity(full ? 1 : 0.55)
                } animation: { _ in .easeInOut(duration: 1.1) }
        }
    }
}

/// A small rounded score like "+0.3".
struct EvalChip: View {
    let text: String
    let color: Color
    var large = false
    /// What VoiceOver says, when "Score" and the text isn't enough.
    var spoken: String? = nil

    var body: some View {
        Text(text)
            .font(.system(large ? .subheadline : .footnote, design: .themed).weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, large ? 10 : 8)
            .padding(.vertical, large ? 5 : 4)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(spoken ?? "Score \(text)")
    }
}

// MARK: - The unfolded coach

/// Everything the coach knows, in the unfolded orb. The handle and the latest word sit at
/// the top, the controls at the bottom, both always in sight; on a short screen the
/// details between them scroll.
private struct CoachPanel: View {
    let match: MatchController
    let theme: BoardTheme
    @Binding var coachMove: Int?
    let newGame: () -> Void
    let showGames: () -> Void
    /// Opens Talk it through. Nil leaves it out.
    let talk: (() -> Void)?
    /// Closes the panel when the person closes it themselves, with a light tap.
    let close: () -> Void
    /// Closes the panel quietly, on the way to something else.
    let collapse: () -> Void

    @AppStorage("showBestMoves") private var showBestMoves = false
    @Environment(GameCoach.self) private var gameCoach: GameCoach?
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(ArmyStore.self) private var army: ArmyStore?
    @Environment(GameVault.self) private var vault: GameVault?
    @State private var reel: GameReel?
    @State private var rewind: SavedGame?
    @State private var confirmingResign = false

    /// This game's Piece of the Match, once the game is over and counted.
    private var hero: MatchHero? {
        guard match.isOver, let hero = army?.lastHero, hero.gameID == match.game.ledger?.gameID else { return nil }
        return hero
    }

    private var accent: Color { theme.accent ?? .accentColor }
    private var rival: String { match.setup.level.rival.name }

    var body: some View {
        VStack(spacing: 0) {
            // A swipe down on the handle or the header closes the panel. Only there:
            // anywhere else it would fight the scrolling below.
            VStack(spacing: 0) {
                handle
                header
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height > 40 { close() }
                    }
            )
            // Where it all fits the panel is its natural height; on a short screen
            // the details scroll instead of squeezing the board.
            ViewThatFits(in: .vertical) {
                details
                ScrollView {
                    details
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.3), value: match.hints)
        .animation(.snappy(duration: 0.3), value: match.isComputerThinking)
    }

    /// The grabber. A tap on it closes the panel, and so does a swipe down.
    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityElement()
            .accessibilityLabel("Close the coach")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { close() }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if match.isOver {
                let result = ResultText(match: match)
                resultBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).font(.headline).foregroundStyle(resultColor)
                    Text(result.detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                // The title has already said who won.
                EvalChip(text: scoreline, color: resultColor, large: true)
                    .accessibilityHidden(true)
            } else if match.isComputerThinking {
                ThinkingSigil(rival: match.setup.level.rival, size: 40, glows: theme.glows)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rival) is thinking").font(.headline)
                    if gradeIsComing {
                        Text("Your grade comes right after \(rival)'s reply.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
            } else if match.engineFailed {
                // Ahead of the last grade, which is about a move that is no longer the news.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3).foregroundStyle(accent).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leo is offline").font(.headline)
                    Text("The engine didn't answer. Play on: grades and hints come back when it does.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            } else if let review = match.review {
                GradeBadge(grade: review.grade, glows: theme.glows, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title).font(.headline).foregroundStyle(review.grade.color(on: theme))
                    Text(review.detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let evaluation = review.evaluationForWhite {
                    let score = match.forPlayer(evaluation).label
                    EvalChip(text: score, color: review.grade.color(on: theme), large: true,
                             spoken: "Score \(score) for you")
                }
            } else {
                CoachAvatar(theme: theme, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leo").font(.headline)
                    Text("Play a move and I'll tell you how it was.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The person's last move is waiting for its grade, which comes once the rival has replied.
    /// Not one Leo played for them: those aren't graded.
    private var gradeIsComing: Bool {
        match.showVerdicts && match.game.lastPlayed?.color == match.setup.playerColor
            && match.game.moveCount != coachMove
    }

    /// What the result means to the player: the accent when they won, plain when they lost,
    /// quiet for a draw. Never a side's own color: Black's is near-black on the dark looks.
    private var resultColor: Color {
        guard let won = match.playerWon else { return .secondary }
        return won ? accent : .primary
    }

    private var resultBadge: some View {
        let symbol = match.playerWon.map { $0 ? "crown.fill" : "flag.fill" } ?? "equal"
        return ZStack {
            Circle().fill(resultColor.opacity(0.16))
            Circle().strokeBorder(resultColor.opacity(0.55), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(resultColor)
        }
        .frame(width: 38, height: 38)
        .shadow(color: theme.glows ? resultColor.opacity(0.6) : .clear, radius: 8)
        .accessibilityHidden(true)
    }

    private var scoreline: String {
        guard let winner = match.winner else { return "½–½" }
        return winner == .white ? "1–0" : "0–1"
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: 0) {
            if let gameCoach, let training, GameCoachRow.hasContent(coach: gameCoach, match: match) {
                GameCoachRow(coach: gameCoach, store: training, match: match, theme: theme)
                    .padding(.top, 10)
            }
            if match.isOver {
                summary.padding(.top, 12)
                if let hero {
                    PieceOfTheMatchCard(hero: hero, color: match.setup.playerColor, theme: theme)
                        .padding(.top, 10)
                }
            } else {
                if let talk, match.canTalkItThrough {
                    TalkEntryRow(theme: theme, countsAsHelp: match.talkCountsAsHelp) {
                        collapse()
                        talk()
                    }
                    .padding(.top, 12)
                }
                EvalBar(share: match.playerShare, label: evalLabel, theme: theme)
                    .padding(.top, 12)
                bestMoves.padding(.top, 12)
            }
        }
    }

    /// The score from the player's side, plus being good for them. Nil until the engine has answered.
    private var evalLabel: String? {
        match.evaluation.map { match.forPlayer($0).label }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            StatTile(title: "Accuracy", value: match.accuracy.map { "\($0)%" } ?? "–",
                     color: MoveReview.Grade.best.color(on: theme), theme: theme)
            StatTile(title: "Best", value: "\(match.gradeCounts[.best, default: 0] + match.gradeCounts[.checkmate, default: 0])",
                     color: .primary, theme: theme)
            StatTile(title: "Mistakes", value: "\(match.gradeCounts[.mistake, default: 0])",
                     color: MoveReview.Grade.mistake.color(on: theme), theme: theme)
            StatTile(title: "Blunders", value: "\(match.gradeCounts[.blunder, default: 0])",
                     color: MoveReview.Grade.blunder.color(on: theme), theme: theme)
        }
    }

    // MARK: Leo's picks

    @ViewBuilder
    private var bestMoves: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showBestMoves {
                Text("Leo's picks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if match.engineFailed {
                    Text("No picks right now. The engine is offline.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if match.hints.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(match.isComputerThinking ? "Waiting for \(rival)…" : "Thinking…")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(match.hints) { hint in
                        HintRow(hint: hint, score: playerScore(of: hint), theme: theme,
                                show: {
                                    // Points at the move on the board and leaves the move to the player.
                                    if match.game.selected != hint.from { match.tap(hint.from) }
                                    collapse()
                                },
                                play: {
                                    let before = match.game.moveCount
                                    match.play(hint)
                                    if match.game.moveCount != before { coachMove = match.game.moveCount }
                                    collapse()
                                })
                    }
                }
            } else {
                Button {
                    showBestMoves = true
                } label: {
                    Label("Show Leo's picks", systemImage: "lightbulb.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .frame(minHeight: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A hint's score is from the side to move. Hints only come on the player's turn, so
    /// that is the player, but it is turned round should it ever not be.
    private func playerScore(of hint: MoveHint) -> String {
        let mine = match.game.sideToMove == match.setup.playerColor
        return (mine ? hint.evaluation : hint.evaluation.flipped).label
    }

    // MARK: Controls

    /// The game's buttons, or once it is over what comes next.
    @ViewBuilder
    private var controls: some View {
        if match.isOver {
            VStack(spacing: 8) {
                endButtons
                if canReview || hasHighlights {
                    HStack(spacing: 8) {
                        if canReview { reviewButton }
                        if hasHighlights { highlightsButton }
                    }
                }
            }
            .padding(.top, 12)
        } else {
            actions.padding(.top, 10)
        }
    }

    private var actions: some View {
        // Top-aligned, so every circle sits on one line whatever its label does.
        HStack(alignment: .top, spacing: 6) {
            ActionButton(title: "Undo", symbol: Glyphs.undo, theme: theme) {
                withAnimation(.snappy(duration: 0.22)) { match.undo() }
            }
            .disabled(!match.canUndo)
            ActionButton(title: "Hints", symbol: showBestMoves ? Glyphs.hints : Glyphs.hintsOff, isOn: showBestMoves, theme: theme) {
                showBestMoves.toggle()
            }
            if gameCoach != nil {
                ThinkActionButton(match: match, theme: theme)
            }
            ActionButton(title: "Flip", symbol: Glyphs.flip, theme: theme) {
                withAnimation(.snappy(duration: 0.45)) { match.flipBoard() }
            }
            if match.canResign {
                // While a game is on, Resign takes the place of Games (also in the dock).
                ActionButton(title: "Resign", symbol: "flag.fill", theme: theme) {
                    confirmingResign = true
                }
                .confirmationDialog("Resign this game?", isPresented: $confirmingResign, titleVisibility: .visible) {
                    Button("Resign", role: .destructive) {
                        withAnimation(.snappy) { match.resign() }
                    }
                    Button("Keep playing", role: .cancel) {}
                }
            } else {
                ActionButton(title: "Games", symbol: Glyphs.games, theme: theme) {
                    collapse()
                    showGames()
                }
            }
            ActionButton(title: "New game", symbol: Glyphs.play, theme: theme) {
                collapse()
                newGame()
            }
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

    /// Rewind needs somewhere to keep the game, and a move to look back on.
    private var canReview: Bool { vault != nil && match.game.plyCount > 0 }

    /// The reel is only offered when the game has moments for one. Working that out is
    /// quick, and grades that land just after the end are counted too.
    private var hasHighlights: Bool { !match.highlightReel().highlights.isEmpty }

    /// Rewind: the game's line, Leo on each moment, and a second chance at the mistakes.
    private var reviewButton: some View {
        Button {
            guard let game = match.savedGame() else { return }
            vault?.record(game)
            rewind = vault?.game(game.id) ?? game
        } label: {
            Label("Review game", systemImage: "backward.circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 28)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.primary)
        .fullScreenCover(item: $rewind) { game in
            if let vault {
                RewindView(game: game, theme: theme, onPlayAgain: { _ in
                    rewind = nil
                    collapse()
                    withAnimation(.snappy) { match.rematch() }
                })
                .environment(vault)
            }
        }
    }

    /// Leo's 30-second story of the game, to watch and share.
    private var highlightsButton: some View {
        Button {
            let names = army?.names(for: match.setup.playerColor) ?? [:]
            reel = match.highlightReel(pieceName: { names[$0] }, hero: hero?.line)
        } label: {
            Label("Highlights", systemImage: "film.stack")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 28)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.primary)
        .fullScreenCover(item: $reel) { reel in
            HighlightReelView(reel: reel, theme: theme)
        }
    }
}

/// The player's share of the game against the rival's, the same as the orb's ring, with
/// the score riding on the boundary.
struct EvalBar: View {
    /// The player's share, 0 to 1.
    let share: Double
    /// The score from the player's side, like "+0.4". Nil until the engine has answered.
    let label: String?
    let theme: BoardTheme

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = max(0, min(1, share))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(EvalRing.rivalTone)
                Capsule()
                    .fill(accent)
                    .frame(width: max(12, width * clamped))
                    .shadow(color: theme.glows ? accent.opacity(0.6) : .clear, radius: 12)
                // Even.
                Rectangle()
                    .fill(EvalRing.tickTone)
                    .frame(width: 1, height: geo.size.height + 4)
                    .position(x: width / 2, y: geo.size.height / 2)
                Text(label ?? "—")
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
        .accessibilityLabel(label.map { "Score \($0) for you" } ?? "No score yet")
    }
}

/// One of Leo's picks: its mark on the board, the move, how good it is for the player, and
/// a button that plays it. A tap on the row itself only points at the move on the board.
private struct HintRow: View {
    let hint: MoveHint
    /// The score after the move, from the player's side.
    let score: String
    let theme: BoardTheme
    let show: () -> Void
    let play: () -> Void

    private var isBest: Bool { hint.rank == 0 }
    private var rankName: String { isBest ? "Best" : "Runner-up" }
    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: show) {
                HStack(spacing: 10) {
                    HintSwatch(color: theme.hint, isBest: isBest, glow: theme.hintGlow)
                    Text(hint.san)
                        .font(.system(.body, design: .themed).weight(.bold))
                        .frame(minWidth: 46, alignment: .leading)
                    Text(rankName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(score)
                        .font(.system(.footnote, design: .themed).weight(.bold).monospacedDigit())
                        .foregroundStyle(isBest ? theme.bestArrow : Color.secondary)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(hint.san)")
            .accessibilityValue("\(rankName), score \(score) for you")

            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.16), in: Circle())
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(hint.san) for me")
        }
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(theme.isDark ? 0.05 : 0.04))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(theme.isDark ? 0.09 : 0.08), lineWidth: 1))
        )
    }
}

/// The board's mark for a hint, in small: a dot in a halo, fainter for the runner-up.
private struct HintSwatch: View {
    let color: Color
    let isBest: Bool
    let glow: Color?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(isBest ? 1 : 0.55), lineWidth: isBest ? 1.8 : 1.4)
                .frame(width: 18, height: 18)
            Circle()
                .fill(color.opacity(isBest ? 1 : 0.7))
                .frame(width: 7, height: 7)
        }
        .shadow(color: glow?.opacity(isBest ? 0.9 : 0.5) ?? .clear, radius: 4)
        .frame(width: 28, height: 18)
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
                Glyph(name: symbol, size: 23)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(theme.isDark ? 0.07 : 0.05), in: Circle())
                    .overlay(Circle().strokeBorder(lit ? accent.opacity(0.5) : Color.primary.opacity(0.11), lineWidth: 1))
                    .shadow(color: lit && theme.glows ? accent.opacity(0.25) : .clear, radius: 10)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    // Six to a row: "New game" shrinks a little rather than break onto two lines.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
    /// The score after the move from White's point of view. `evaluation` itself is
    /// from the mover's side; the coach turns it to the player's.
    var evaluationForWhite: Evaluation? {
        guard let evaluation else { return nil }
        let moverWasBlack = fenBefore?.split(separator: " ").dropFirst().first == "b"
        return moverWasBlack ? evaluation.flipped : evaluation
    }

    /// The verdict in one short line, after its title: what VoiceOver says when the grade lands.
    var shortDetail: String {
        let better = best ?? "another move"
        switch grade {
        case .checkmate: return "\(played) ends it."
        case .best: return "\(played) · the top choice."
        case .excellent: return "\(played) · nearly as good as \(better)."
        case .good: return "\(played) · \(better) was a little better."
        case .inaccuracy: return "\(played) · \(better) was better."
        case .mistake: return "\(played) · \(better) was much better."
        case .blunder: return "\(played) · \(better) was the move."
        }
    }
}
