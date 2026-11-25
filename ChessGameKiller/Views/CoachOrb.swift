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
    /// Opens the New Game sheet. Nil when Home is on: new games start only from Home
    /// (Alex, 2026-11-07), and the finished game offers Home instead.
    let newGame: (() -> Void)?
    /// Goes back to Home, offered beside Rematch once the game is over.
    var home: (() -> Void)? = nil
    /// Opens the player's saved games.
    let showGames: () -> Void
    /// Opens Talk it through for the position on the board. Nil leaves it out.
    var talk: (() -> Void)? = nil
    /// Opens Analyze on the position. Nil leaves it out.
    var analyze: (() -> Void)? = nil
    /// Plays the next rival's film, then starts the game against it. Offered after a win
    /// while the rival above is still unbeaten. Nil leaves it out.
    var faceNext: ((MatchController.Level) -> Void)? = nil

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
                CoachPanel(match: match, theme: theme, coachMove: $coachMove, newGame: newGame, home: home, showGames: showGames,
                           talk: talk, analyze: analyze, faceNext: faceNext,
                           close: { collapse(felt: true) }, collapse: { collapse() })
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
    /// The engine's score turned to the player's side, as an eval strip shows it:
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

    private var rival: String { match.setup.rival.name }
    private var player: Piece.Color { match.setup.playerColor }

    var title: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser):
                return loser == player ? "\(rival) \(rival.agreeing("wins", "win")) on time" : "You win on time"
            case .timeoutDraw, .agreedDraw:
                return "Draw"
            case .resigned(let loser):
                return loser == player ? "You resigned" : "\(rival) \(rival.agreeing("resigns", "resign"))"
            }
        }
        guard let winner = match.game.winner else { return "Draw" }
        return winner == player ? "You win" : "\(rival) \(rival.agreeing("wins", "win"))"
    }

    var detail: String {
        if let outcome = match.outcome {
            switch outcome {
            case .timeout(let loser):
                return loser == player ? "Your clock ran out." : "\(rival.possessive) clock ran out."
            case .timeoutDraw(let flagged):
                return flagged == player
                    ? "Your clock ran out, but \(rival.midSentence) can't checkmate with what's left."
                    : "\(rival.possessive) clock ran out, but you can't checkmate with what's left."
            case .agreedDraw:
                return "You offered a draw and \(rival.midSentence) accepted."
            case .resigned(let loser):
                return loser == player ? "\(rival) \(rival.agreeing("takes", "take")) this one." : "You win. There was no way back for \(rival.midSentence)."
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
            ThinkingSigil(rival: match.setup.rival, size: 36, glows: theme.glows)
        } else if match.isOver {
            // What the result means to the player, never a side's own color.
            if let won = match.playerWon {
                Image(systemName: won ? "crown.fill" : "flag.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(won ? accent : Color.primary.opacity(0.85))
                    .shadow(color: theme.glows && won ? accent.opacity(0.9) : .clear, radius: 8)
            } else {
                Text("½")
                    .font(.app(size: 24, weight: .heavy))
                    .foregroundStyle(.secondary)
            }
        } else if let review = match.review {
            Group {
                switch review.grade.mark {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 22, weight: .bold))
                case .text(let text):
                    Text(text).font(.app(size: 22, weight: .heavy))
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
        if match.isComputerThinking { return "\(match.setup.rival.name) \(match.setup.rival.name.agreeing("is", "are")) thinking" }
        if match.isOver { return ResultText(match: match).title }
        var text = match.review.map { "\($0.title). \($0.detail)" } ?? "\(Coach.current.name), your coach."
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
            .font(.app(large ? .subheadline : .footnote, weight: .bold).monospacedDigit())
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
    let newGame: (() -> Void)?
    let home: (() -> Void)?
    let showGames: () -> Void
    /// Opens Talk it through. Nil leaves it out.
    let talk: (() -> Void)?
    /// Opens Analyze. Nil leaves it out, and Flip takes its place.
    let analyze: (() -> Void)?
    /// Plays the next rival's film, then the game. Nil leaves the offer out.
    var faceNext: ((MatchController.Level) -> Void)? = nil
    /// Closes the panel when the person closes it themselves, with a light tap.
    let close: () -> Void
    /// Closes the panel quietly, on the way to something else.
    let collapse: () -> Void

    @AppStorage("showBestMoves") private var showBestMoves = false
    /// Hints switched off in the New Game box: no Hints button and no picks to open.
    @AppStorage("hintsHidden") private var hintsHidden = false
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
    private var rival: String { match.setup.rival.name }

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
                    details.padding(.bottom, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
                // What runs past the bottom fades out, so it reads as more to scroll, not cut off.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 22)
                    }
                }
            }
            // The score stays in sight under the scrolling details, never behind the buttons.
            if !match.isOver {
                EvalBar(share: match.playerShare, label: evalLabel, theme: theme)
                    .padding(.top, 12)
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
        if match.isOver {
            scoreboard
        } else {
            playingHeader
        }
    }

    @ViewBuilder
    private var playingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if match.isComputerThinking {
                ThinkingSigil(rival: match.setup.rival, size: 40, glows: theme.glows)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rival) \(rival.agreeing("is", "are")) thinking").font(.app(.headline))
                    if gradeIsComing {
                        Text("Your grade comes right after \(rival.midSentence.possessive) reply.")
                            .font(.app(.subheadline)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
            } else if match.engineFailed {
                // Ahead of the last grade, which is about a move that is no longer the news.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.app(.title3)).foregroundStyle(accent).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Coach.current.name) is offline").font(.app(.headline))
                    Text("The engine didn't answer. Play on: grades and hints come back when it does.")
                        .font(.app(.subheadline)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            } else if let review = match.review {
                GradeBadge(grade: review.grade, glows: theme.glows, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title).font(.app(.headline)).foregroundStyle(review.grade.color(on: theme))
                    Text(review.detail).font(.app(.subheadline)).foregroundStyle(.secondary)
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
                    Text("\(Coach.current.name)").font(.app(.headline))
                    Text("Play a move and I'll tell you how it was.")
                        .font(.app(.subheadline)).foregroundStyle(.secondary)
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

    /// The game's end as a scoreboard (Alex's pick A, 2026-11-24): White's side, the score
    /// carved in Cinzel, Black's side, and one quiet line on how it ended.
    private var scoreboard: some View {
        let result = ResultText(match: match)
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                scoreSide(.white)
                Text(scoreline)
                    .font(.custom("Cinzel-Bold", size: 42))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                scoreSide(.black)
            }
            (Text(result.title + ". ").foregroundStyle(resultColor)
                + Text(result.detail).foregroundStyle(.secondary))
                .font(.system(size: 16, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.title). \(result.detail)")
    }

    /// One side of the scoreboard: the rival's coin, or a king for a person, and the name.
    private func scoreSide(_ color: Piece.Color) -> some View {
        // Against a rival, the side that isn't the player's is the rival's.
        let isRival = match.setup.opponent == .computer && color != match.setup.playerColor
        let name = match.setup.opponent == .computer
            ? (isRival ? match.setup.rival.name : "You")
            : theme.name(of: color)
        return VStack(spacing: 5) {
            Group {
                if isRival {
                    RivalCoin(rival: match.setup.rival, size: 44)
                } else {
                    PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: 30)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(theme.isDark ? 0.07 : 0.05), in: Circle())
                }
            }
            .overlay(Circle().strokeBorder(accent.opacity(0.5), lineWidth: 1))
            Text(name)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 84)
    }

    private var scoreline: String {
        guard let winner = match.winner else { return "½ – ½" }
        return winner == .white ? "1 – 0" : "0 – 1"
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: 0) {
            // Once the game is over the numbers come first, under the score, and the
            // practice pill after them.
            if match.isOver { summary.padding(.top, 14) }
            if let gameCoach, let training, GameCoachRow.hasContent(coach: gameCoach, match: match) {
                GameCoachRow(coach: gameCoach, store: training, match: match, theme: theme)
                    .padding(.top, match.isOver ? 14 : 10)
            }
            if match.isOver {
                if let hero {
                    PieceOfTheMatchCard(hero: hero, color: match.setup.playerColor, theme: theme)
                        .padding(.top, 10)
                }
                LearnedAboutYouRow(gameID: match.gameID, theme: theme)
            } else {
                if let talk, match.canTalkItThrough {
                    TalkEntryRow(theme: theme, countsAsHelp: match.talkCountsAsHelp) {
                        collapse()
                        talk()
                    }
                    .padding(.top, 12)
                }
                if !hintsHidden {
                    bestMoves.padding(.top, 12)
                }
            }
        }
    }

    /// The score from the player's side, plus being good for them. Nil until the engine has answered.
    private var evalLabel: String? {
        match.evaluation.map { match.forPlayer($0).label }
    }

    /// The four numbers on one line, between two thin gold rules, with no boxes.
    private var summary: some View {
        VStack(spacing: 0) {
            GoldRule(accent: accent)
            HStack(spacing: 0) {
                StatTile(title: "Accuracy", value: match.accuracy.map { "\($0)%" } ?? "–",
                         color: match.accuracy.map { MoveReview.Grade.forAccuracy($0).color(on: theme) } ?? .secondary)
                StatDivider(accent: accent)
                StatTile(title: "Best", value: "\(match.gradeCounts[.best, default: 0] + match.gradeCounts[.checkmate, default: 0])",
                         color: .primary)
                StatDivider(accent: accent)
                StatTile(title: "Mistakes", value: "\(match.gradeCounts[.mistake, default: 0])",
                         color: MoveReview.Grade.mistake.color(on: theme))
                StatDivider(accent: accent)
                StatTile(title: "Blunders", value: "\(match.gradeCounts[.blunder, default: 0])",
                         color: MoveReview.Grade.blunder.color(on: theme))
            }
            .padding(.vertical, 12)
            GoldRule(accent: accent)
        }
    }

    // MARK: Leo's picks

    @ViewBuilder
    private var bestMoves: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showBestMoves {
                Text("\(Coach.current.name)'s picks")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                if match.engineFailed {
                    Text("No picks right now. The engine is offline.")
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if match.hints.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(match.isComputerThinking ? "Waiting for \(rival.midSentence)…" : "Thinking…")
                            .font(.app(.footnote, weight: .medium))
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
                    Label("Show \(Coach.current.name)'s picks", systemImage: "lightbulb.fill")
                        .font(.app(.footnote, weight: .semibold))
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
            // One gold button, and the rest as quiet words under it (Alex's pick A, 2026-11-24).
            VStack(spacing: 14) {
                if let next = nextRival {
                    nextRivalOffer(next)
                } else {
                    rematchButton
                }
                endLinks
            }
            .padding(.top, 16)
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
            if !hintsHidden {
                ActionButton(title: "Hints", symbol: showBestMoves ? Glyphs.hints : Glyphs.hintsOff, isOn: showBestMoves, theme: theme) {
                    showBestMoves.toggle()
                }
            }
            if gameCoach != nil {
                ThinkActionButton(match: match, theme: theme)
            }
            if let analyze {
                // Analyze moved here from the dock; Flip is still on the dock.
                ActionButton(title: "Analyze", symbol: Glyphs.analyze, theme: theme) {
                    collapse()
                    analyze()
                }
            } else {
                ActionButton(title: "Flip", symbol: Glyphs.flip, theme: theme) {
                    withAnimation(.snappy(duration: 0.45)) { match.flipBoard() }
                }
            }
            if match.isUnderway {
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
            } else if match.isOver {
                // Before the first move the slot stays empty: Your games lives on Home now
                // (Alex's pick 10A, screen review 2026-11-19).
                ActionButton(title: "Games", symbol: Glyphs.games, theme: theme) {
                    collapse()
                    showGames()
                }
            }
            if let newGame {
                ActionButton(title: "New game", symbol: Glyphs.play, theme: theme) {
                    collapse()
                    newGame()
                }
            }
        }
    }

    /// The rival above the one just beaten, while it is still unbeaten: the climb's next step
    /// (Alex, 2026-11-11, audit pick R2: a win opened the next rival and nothing said so).
    /// Never after a loss or a draw, or once the last rival has fallen.
    private var nextRival: MatchController.Level? {
        guard faceNext != nil, match.playerWon == true,
              let next = MatchController.Level(rawValue: match.setup.level.rawValue + 1),
              !RivalLadder().beaten(next.rival) else { return nil }
        return next
    }

    /// One quiet line, and a gold button that plays the next rival's film.
    private func nextRivalOffer(_ next: MatchController.Level) -> some View {
        let gold = Color(hex: 0xE8C27A)
        let rival = next.rival
        return VStack(spacing: 8) {
            Text("\(rival.name) will see you now.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Button {
                collapse()
                faceNext?(next)
            } label: {
                HStack(spacing: 10) {
                    RivalCoin(rival: rival, size: 28)
                    // "Face the Hunter", as the hall's own button writes it.
                    Text("Face \(rival.name.lowercasedFirstWord)")
                        .font(.app(.headline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Color(hex: 0x1B1408))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xF3DDA8), gold, Color(hex: 0xC99A4B)],
                                             startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: gold.opacity(theme.glows ? 0.45 : 0.2), radius: 12, y: 3)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Face \(rival.name)")
            .accessibilityHint("Plays \(rival.name.possessive) film, then starts the game")
        }
        .padding(.bottom, 4)
    }

    /// Home (or New game), Review game and Highlights as plain words with dots between;
    /// Rematch joins them when the next rival's gold button has the top spot.
    private var endLinks: some View {
        HStack(spacing: 0) {
            let links = endLinkKinds
            ForEach(Array(links.enumerated()), id: \.element) { index, kind in
                if index > 0 {
                    Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                endLink(kind)
            }
        }
        .font(.app(.subheadline, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }

    private enum EndLink: Hashable { case rematch, newGame, home, review, highlights }

    private var endLinkKinds: [EndLink] {
        var links: [EndLink] = []
        if nextRival != nil { links.append(.rematch) }
        if newGame != nil { links.append(.newGame) } else if home != nil { links.append(.home) }
        if canReview { links.append(.review) }
        if hasHighlights { links.append(.highlights) }
        return links
    }

    @ViewBuilder
    private func endLink(_ kind: EndLink) -> some View {
        switch kind {
        case .rematch:
            linkButton("Rematch") {
                collapse()
                withAnimation(.snappy) { match.rematch() }
            }
        case .newGame:
            linkButton("New game") {
                collapse()
                newGame?()
            }
        case .home:
            linkButton("Home") {
                collapse()
                home?()
            }
        case .review: reviewButton
        case .highlights: highlightsButton
        }
    }

    /// A quiet word to tap, a full 44 pt tall.
    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The panel's one gold button: a full-width capsule, 52 pt tall.
    private var rematchButton: some View {
        Button {
            collapse()
            withAnimation(.snappy) { match.rematch() }
        } label: {
            Label("Rematch", systemImage: "play.fill")
                .font(.app(.headline))
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(accent.gradient))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: accent.opacity(theme.glows ? 0.5 : 0.22), radius: 12, y: 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
            Text("Review game")
                .foregroundStyle(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $rewind) { game in
            if let vault {
                RewindView(game: game, theme: theme, onPlayAgain: { _ in
                    rewind = nil
                    collapse()
                    withAnimation(.snappy) { match.rematch() }
                })
                .environment(vault)
                .keepsPhoneUpright("review")
            }
        }
        // A link from outside brings its own screen forward: this one steps aside for it.
        .onReceive(NotificationCenter.default.publisher(for: ScreenCovers.closeAll)) { _ in rewind = nil }
    }

    /// Leo's 30-second story of the game, to watch and share.
    private var highlightsButton: some View {
        Button {
            let names = army?.names(for: match.setup.playerColor) ?? [:]
            reel = match.highlightReel(pieceName: { names[$0] }, hero: hero?.line)
        } label: {
            Text("Highlights")
                .foregroundStyle(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $reel) { reel in
            HighlightReelView(reel: reel, theme: theme)
                .keepsPhoneUpright("highlights")
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenCovers.closeAll)) { _ in reel = nil }
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
                    .font(.app(size: 11, weight: .bold).monospacedDigit())
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
                        .font(.app(.body, weight: .bold))
                        .frame(minWidth: 46, alignment: .leading)
                    Text(rankName)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(score)
                        .font(.app(.footnote, weight: .bold).monospacedDigit())
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
                    .font(.app(.caption2, weight: .semibold))
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

/// One number from the game's summary: the number, and its name in small capitals under it.
private struct StatTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.app(.title2, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title.uppercased())
                .font(.app(.caption2, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// A thin gold rule across the panel that fades out at both ends.
private struct GoldRule: View {
    let accent: Color

    var body: some View {
        LinearGradient(colors: [.clear, accent.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The thin upright line between two numbers, fading out at top and bottom.
private struct StatDivider: View {
    let accent: Color

    var body: some View {
        LinearGradient(colors: [.clear, accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: 1, height: 40)
            .accessibilityHidden(true)
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
