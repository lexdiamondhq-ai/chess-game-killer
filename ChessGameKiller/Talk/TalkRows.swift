import ChessKit
import SwiftUI

// The talk under the board in Talk it through: Leo's greeting, the player's words (live while
// they speak), placeholder rows while Leo checks, then his verdicts (the move, each claim, what
// went unmentioned), the Traffic Light, and his answer. Glass throughout; the verdict colors are
// the only loud color.

// MARK: - Look

extension BoardTheme {
    /// Talk it through's type: the look's design (rounded on Neon), sized by Dynamic Type.
    func talkFont(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: challengeDesign, weight: weight)
    }
}

/// The verdict colors.
enum TalkPanelPalette {
    /// Right, and the good move: a clean green.
    static let good = Color(hex: 0x34D399)
    /// Wrong, and the danger: the app's clear red.
    static let bad = ChallengeColors.urgent
    /// Partly right.
    static let partly = Color(hex: 0xF7D046)
    /// What went unmentioned: amber.
    static let missed = Color(hex: 0xFF9A3C)
    /// Neither right nor wrong.
    static let unclear = Color(white: 0.62)

    /// A square's or an arrow's color on the board: green, red, or the look's accent.
    static func tone(_ tone: TalkArrow.Tone, theme: BoardTheme) -> Color {
        switch tone {
        case .good: return good
        case .bad: return bad
        case .info: return theme.challengeAccent
        }
    }
}

/// How the verdicts went overall, for the haptic and the color of Leo's ring.
enum TalkPanelMood: Equatable {
    case allRight, mixed, wrong

    init(_ check: TalkCheck) {
        let verdicts: [TalkClaim.Verdict] = check.claims.map { $0.verdict }
        let marks: [TalkHabits.Mark] = [check.habits.threats, check.habits.forcing, check.habits.safety]
        let badGrades: [TalkMoveCheck.Grade] = [.mistake, .blunder, .illegal]
        let fineGrades: [TalkMoveCheck.Grade] = [.checkmate, .best, .excellent, .good]
        let grade: TalkMoveCheck.Grade? = check.move?.grade
        let badMove: Bool = grade.map { badGrades.contains($0) } ?? false
        let fineMove: Bool = grade.map { fineGrades.contains($0) } ?? true
        let somethingWrong: Bool = verdicts.contains(.wrong) || !check.missed.isEmpty || marks.contains(.missed) || badMove
        let allRight: Bool = check.understood && fineMove && verdicts.allSatisfy({ $0 == .right })
        if somethingWrong {
            self = .wrong
        } else if allRight {
            self = .allRight
        } else {
            self = .mixed
        }
    }
}

/// Which verdict the board shows, and how each is drawn.
enum TalkPanelLogic {
    /// The verdict the board lights: the one tapped, else the move, else the first claim,
    /// else the first thing missed.
    static func effectiveFocus(_ focus: TalkFocus?, in check: TalkCheck) -> TalkFocus? {
        if let focus, isPresent(focus, in: check) { return focus }
        if check.move != nil { return .move }
        if let first = check.claims.first { return .claim(first.id) }
        if !check.missed.isEmpty { return .missed(0) }
        return nil
    }

    static func isPresent(_ focus: TalkFocus, in check: TalkCheck) -> Bool {
        switch focus {
        case .move:
            return check.move != nil
        case .claim(let id):
            return check.claims.contains(where: { $0.id == id })
        case .missed(let index):
            return check.missed.indices.contains(index)
        }
    }

    /// Whether a verdict has anything to light on the board.
    static func canLight(_ focus: TalkFocus, in check: TalkCheck) -> Bool {
        let lit = check.highlights(for: focus)
        return !lit.squares.isEmpty || !lit.arrows.isEmpty
    }

    /// The tone of a verdict's squares where no arrow says otherwise.
    static func tone(for focus: TalkFocus, in check: TalkCheck) -> TalkArrow.Tone {
        switch focus {
        case .move:
            guard let grade = check.move?.grade else { return .info }
            switch grade {
            case .checkmate, .best, .excellent, .good: return .good
            case .mistake, .blunder, .illegal: return .bad
            case .inaccuracy, .unknown: return .info
            }
        case .claim(let id):
            guard let claim = check.claims.first(where: { $0.id == id }) else { return .info }
            switch claim.verdict {
            case .right: return .good
            case .wrong: return .bad
            case .partly, .unclear: return .info
            }
        case .missed:
            return .bad
        }
    }

    /// A square from its name, like "e4"; nil for anything else.
    static func square(_ name: String) -> Square? {
        let letters: [Character] = Array(name.lowercased())
        let files: [Character] = ["a", "b", "c", "d", "e", "f", "g", "h"]
        guard letters.count == 2, let file = files.firstIndex(of: letters[0]),
              let rank = letters[1].wholeNumberValue, (1...8).contains(rank) else { return nil }
        return Square(file: file, rank: rank - 1)
    }

    /// The player's words with a capital first letter.
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    /// The heading of something that mattered and went unsaid.
    static func missedTitle(_ kind: String) -> String {
        switch kind {
        case "threat": return "You didn't mention their threat"
        case "mate": return "You didn't mention the mate"
        case "hanging": return "You didn't mention a loose piece"
        case "free": return "You didn't mention a free piece"
        default: return "You didn't mention this"
        }
    }
}

// MARK: - The conversation

/// The talk, in order: Leo's greeting until the player has spoken; their words, live while they
/// speak; placeholder rows while Leo checks; then his verdicts, the Traffic Light and his answer.
struct TalkPanelConversation: View {
    let session: TalkSession
    let theme: BoardTheme
    /// Lights a verdict on the board.
    let select: (TalkFocus) -> Void
    let stopSpeaking: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scroll targets: the player's words, Leo's answer, and why he couldn't answer.
    static let liveID = "talk.live"
    static let answerID = "talk.answer"
    static let problemID = "talk.problem"

    private static let greeting = "Talk me through your plan. I'll check every idea."
    private static let notUnderstood = "I didn't catch a plan there. Tell me a threat you see, an idea, or the move you want."
    private static let fallbackProblem = "Something went wrong. Try again."

    var body: some View {
        VStack(spacing: 16) {
            if showsGreeting {
                TalkPanelLeoBubble(text: Self.greeting, theme: theme)
                    .transition(arrival)
            }
            if showsWords {
                TalkPanelPlayerBubble(text: session.transcript, live: session.phase == .listening, theme: theme)
                    .id(Self.liveID)
                    .transition(arrival)
            }
            if session.phase == .checking, session.check == nil {
                TalkPanelCheckingCard()
                    .transition(arrival)
            }
            if let check = shownCheck, check.understood {
                TalkPanelVerdicts(check: check, focus: TalkPanelLogic.effectiveFocus(session.focus, in: check),
                                  theme: theme, select: select)
                    .transition(arrival)
            }
            if session.phase == .failed, session.outOfTalks {
                PremiumLimitCard(feature: .talk, accent: theme.challengeAccent)
                    .id(Self.problemID)
                    .transition(arrival)
            } else if session.phase == .failed {
                TalkPanelProblemCard(text: problemText, theme: theme)
                    .id(Self.problemID)
                    .transition(arrival)
            }
            if showsLeo {
                TalkPanelLeoBubble(text: leoText, theme: theme, speaking: session.isSpeaking, stop: stopSpeaking)
                    .id(Self.answerID)
                    .transition(arrival)
            }
        }
        .animation(motion, value: session.phase)
        .animation(motion, value: session.check)
        .animation(motion, value: session.answer)
        .animation(motion, value: session.isSpeaking)
    }

    private var showsGreeting: Bool {
        switch session.phase {
        case .ready, .listening, .typing: return true
        case .checking, .answered, .failed: return false
        }
    }

    private var showsWords: Bool {
        switch session.phase {
        case .listening: return true
        case .checking, .answered, .failed: return !words.isEmpty
        case .ready, .typing: return false
        }
    }

    private var words: String {
        session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Verdicts belong to the go they came from, so they show only while Leo checks or answers.
    private var shownCheck: TalkCheck? {
        switch session.phase {
        case .checking, .answered: return session.check
        case .ready, .listening, .typing, .failed: return nil
        }
    }

    private var answerText: String? {
        guard let answer = session.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
            return nil
        }
        return answer
    }

    private var showsLeo: Bool {
        switch session.phase {
        case .checking: return session.check != nil || answerText != nil
        case .answered: return answerText != nil || session.check?.understood == false
        case .ready, .listening, .typing, .failed: return false
        }
    }

    /// Leo's words; nil while they're still coming.
    private var leoText: String? {
        if let answerText { return answerText }
        return session.phase == .answered ? Self.notUnderstood : nil
    }

    private var problemText: String {
        let text = session.problem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? Self.fallbackProblem : text
    }

    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10))
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)
    }
}

// MARK: - Bubbles

/// The player's words on the right, in glass tinted with the accent. Live while they speak.
private struct TalkPanelPlayerBubble: View {
    let text: String
    let live: Bool
    let theme: BoardTheme

    var body: some View {
        let accent: Color = theme.challengeAccent
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let words: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(spacing: 0) {
            Spacer(minLength: 44)
            VStack(alignment: .leading, spacing: 6) {
                if live {
                    HStack(spacing: 7) {
                        TalkPanelLiveDot(color: accent)
                        Text("Listening")
                            .font(theme.talkFont(.caption, .semibold))
                            .foregroundStyle(accent)
                    }
                }
                if !words.isEmpty {
                    Text(words)
                        .font(theme.talkFont(.body))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassPane(shape, tint: accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(live ? "Listening. You said: \(words)" : "You said: \(words)")
    }
}

/// Leo speaking: his face beside a glass bubble. While his voice plays, a small Stop.
private struct TalkPanelLeoBubble: View {
    /// His words; nil while they're still coming, which shows three soft dots.
    let text: String?
    let theme: BoardTheme
    var speaking = false
    var stop: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CoachAvatar(theme: theme, size: 34)
            bubble
            Spacer(minLength: 28)
        }
    }

    private var bubble: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            if let text {
                Text(text)
                    .font(theme.talkFont(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(Coach.current.name): \(text)")
            } else {
                TalkPanelTypingDots(color: Color.secondary)
                    .frame(height: 22)
                    .accessibilityElement()
                    .accessibilityLabel("\(Coach.current.name) is answering")
            }
            if speaking, let stop {
                stopButton(stop)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPane(shape)
        .contentShape(shape)
        .onTapGesture {
            if speaking { stop?() }
        }
    }

    private func stopButton(_ stop: @escaping () -> Void) -> some View {
        let accent: Color = theme.challengeAccent
        return Button(action: stop) {
            HStack(spacing: 7) {
                TalkPanelSpeakingBars(color: accent)
                Text("Stop")
                    .font(theme.talkFont(.footnote, .semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(accent.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel("Stop \(Coach.current.name)")
        .transition(.opacity)
    }
}

// MARK: - Verdicts

/// "Leo checked" and how many claims held up, one row per verdict in a glass card, and the
/// Traffic Light. Tapping a row lights it on the board.
private struct TalkPanelVerdicts: View {
    let check: TalkCheck
    /// The verdict the board shows.
    let focus: TalkFocus?
    let theme: BoardTheme
    let select: (TalkFocus) -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            rows
            TalkPanelTrafficLight(habits: check.habits, theme: theme)
                .modifier(TalkPanelArrival(index: rowCount))
            if lightable > 1 {
                Text("Tap a line to see it on the board.")
                    .font(theme.talkFont(.caption))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .modifier(TalkPanelArrival(index: rowCount + 1))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("LEO CHECKED")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if check.judgedCount > 0 {
                Text("\(check.rightCount) of \(check.judgedCount) right")
                    .font(theme.talkFont(.footnote, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(summaryColor)
            }
        }
        .padding(.horizontal, 6)
    }

    private var summaryColor: Color {
        check.rightCount == check.judgedCount ? TalkPanelPalette.good : Color.secondary
    }

    private var rows: some View {
        VStack(spacing: 2) {
            if let move = check.move {
                row(.move, index: 0, label: moveLabel(move)) {
                    TalkPanelMoveRow(move: move, tip: tip, theme: theme)
                }
            }
            ForEach(Array(check.claims.enumerated()), id: \.offset) { offset, claim in
                row(.claim(claim.id), index: firstClaimIndex + offset, label: claimLabel(claim)) {
                    TalkPanelClaimRow(claim: claim, theme: theme)
                }
            }
            ForEach(Array(check.missed.enumerated()), id: \.offset) { offset, missed in
                row(.missed(offset), index: firstMissedIndex + offset, label: missedLabel(missed)) {
                    TalkPanelMissedRow(missed: missed, theme: theme)
                }
            }
        }
        .padding(6)
        .glassPane(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// One verdict: a button that lights it on the board when it has something to light.
    @ViewBuilder
    private func row<Content: View>(_ target: TalkFocus, index: Int, label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        let tappable: Bool = TalkPanelLogic.canLight(target, in: check)
        let lit: Bool = tappable && focus == target
        let line = content()
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { TalkPanelSelection(isOn: lit) }
            .contentShape(Rectangle())
        if tappable {
            Button {
                select(target)
            } label: {
                line
            }
            .buttonStyle(TalkPanelRowStyle())
            .accessibilityLabel(label)
            .accessibilityHint("Shows it on the board")
            .accessibilityAddTraits(lit ? .isSelected : [])
            .modifier(TalkPanelArrival(index: index))
        } else {
            line
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .modifier(TalkPanelArrival(index: index))
        }
    }

    private var firstClaimIndex: Int { check.move == nil ? 0 : 1 }
    private var firstMissedIndex: Int { firstClaimIndex + check.claims.count }
    private var rowCount: Int { firstMissedIndex + check.missed.count }

    /// How many rows light something on the board.
    private var lightable: Int {
        var targets: [TalkFocus] = []
        if check.move != nil { targets.append(.move) }
        targets += check.claims.map { TalkFocus.claim($0.id) }
        targets += check.missed.indices.map { TalkFocus.missed($0) }
        return targets.filter { TalkPanelLogic.canLight($0, in: check) }.count
    }

    /// Under the move: Leo's hint when he may not name the move, else the best move when it differs.
    private var tip: String? {
        if let nudge = check.nudge?.trimmingCharacters(in: .whitespacesAndNewlines), !nudge.isEmpty {
            return nudge
        }
        guard let best = check.best, let move = check.move, best.uci != move.uci else { return nil }
        let strong: [TalkMoveCheck.Grade] = [.checkmate, .best]
        return strong.contains(move.grade) ? nil : "Best here: \(best.san)"
    }

    private func moveLabel(_ move: TalkMoveCheck) -> String {
        let name: String = move.san ?? move.said
        let parts: [String] = ["Your move \(name)", TalkPanelGradeStyle(move.grade).title, move.note]
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private func claimLabel(_ claim: TalkClaim) -> String {
        let parts: [String] = [TalkPanelMark.Kind(claim.verdict).spoken, claim.said, claim.note]
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private func missedLabel(_ missed: TalkMissed) -> String {
        let parts: [String] = [TalkPanelLogic.missedTitle(missed.kind), missed.note]
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// The soft glass behind the row the board is showing.
private struct TalkPanelSelection: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        shape
            .fill(Color.white.opacity(isOn ? 0.08 : 0))
            .overlay { shape.strokeBorder(Color.white.opacity(isOn ? 0.14 : 0), lineWidth: 0.75) }
    }
}

/// A row dims a touch while pressed.
private struct TalkPanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The move they chose, big, with its grade in the app's grade colors, Leo's line under it,
/// and his pointer to something better.
private struct TalkPanelMoveRow: View {
    let move: TalkMoveCheck
    let tip: String?
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR MOVE")
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(theme.talkFont(.title, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                TalkPanelGradeChip(grade: move.grade, theme: theme)
                Spacer(minLength: 0)
            }
            if !move.note.isEmpty {
                Text(move.note)
                    .font(theme.talkFont(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tip {
                Label {
                    Text(tip)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                }
                .font(theme.talkFont(.footnote, .semibold))
                .foregroundStyle(theme.challengeAccent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
        }
    }

    /// The move in notation, or their words for it when it isn't legal.
    private var title: String {
        if let san = move.san, !san.isEmpty { return san }
        let said: String = move.said.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? "Your move" : TalkPanelLogic.capitalized(said)
    }
}

/// One claim: its verdict mark, the player's words, and Leo's line under them.
private struct TalkPanelClaimRow: View {
    let claim: TalkClaim
    let theme: BoardTheme

    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TalkPanelMark(kind: TalkPanelMark.Kind(claim.verdict), size: markSize)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + d.height * 0.22 }
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(theme.talkFont(.body, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(theme.talkFont(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var said: String {
        claim.said.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Their words in quotes; Leo's line instead when the words didn't come through.
    private var headline: String {
        if said.isEmpty { return claim.note.isEmpty ? "Your idea" : claim.note }
        return "\u{201C}\(TalkPanelLogic.capitalized(said))\u{201D}"
    }

    private var detail: String? {
        said.isEmpty || claim.note.isEmpty ? nil : claim.note
    }
}

/// Something that mattered and went unsaid, in amber.
private struct TalkPanelMissedRow: View {
    let missed: TalkMissed
    let theme: BoardTheme

    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TalkPanelMark(kind: .missed, size: markSize)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + d.height * 0.22 }
            VStack(alignment: .leading, spacing: 3) {
                Text(TalkPanelLogic.missedTitle(missed.kind))
                    .font(theme.talkFont(.body, .semibold))
                    .foregroundStyle(TalkPanelPalette.missed)
                    .fixedSize(horizontal: false, vertical: true)
                if !missed.note.isEmpty {
                    Text(missed.note)
                        .font(theme.talkFont(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A verdict's mark: a check, a cross, a half, a question, or the amber "missed" sign, in a
/// softly tinted circle.
private struct TalkPanelMark: View {
    enum Kind {
        case right, wrong, partly, unclear, missed

        init(_ verdict: TalkClaim.Verdict) {
            switch verdict {
            case .right: self = .right
            case .wrong: self = .wrong
            case .partly: self = .partly
            case .unclear: self = .unclear
            }
        }

        var color: Color {
            switch self {
            case .right: return TalkPanelPalette.good
            case .wrong: return TalkPanelPalette.bad
            case .partly: return TalkPanelPalette.partly
            case .unclear: return TalkPanelPalette.unclear
            case .missed: return TalkPanelPalette.missed
            }
        }

        var symbol: String {
            switch self {
            case .right: return "checkmark"
            case .wrong: return "xmark"
            case .partly: return "circle.lefthalf.filled"
            case .unclear: return "questionmark"
            case .missed: return "exclamationmark"
            }
        }

        /// What VoiceOver says for the mark.
        var spoken: String {
            switch self {
            case .right: return "Right"
            case .wrong: return "Not right"
            case .partly: return "Partly right"
            case .unclear: return "Not sure"
            case .missed: return "Missed"
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 26

    var body: some View {
        let color: Color = kind.color
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
            Circle()
                .strokeBorder(color.opacity(0.5), lineWidth: 1)
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A grade's name, color and chess mark: the app's own for real grades, plain ones for a move
/// that isn't legal or that Stockfish's numbers don't cover.
private struct TalkPanelGradeStyle {
    let title: String
    let color: Color
    var symbol: String? = nil
    var mark: String? = nil

    init(_ grade: TalkMoveCheck.Grade) {
        switch grade {
        case .checkmate: title = "Checkmate"
        case .best: title = "Best move"
        case .excellent: title = "Excellent"
        case .good: title = "Good move"
        case .inaccuracy: title = "Inaccuracy"
        case .mistake: title = "Mistake"
        case .blunder: title = "Blunder"
        case .illegal: title = "Not legal"
        case .unknown: title = "Not graded"
        }
        if let review = MoveReview.Grade(rawValue: grade.rawValue) {
            color = review.color
            switch review.mark {
            case .symbol(let name): symbol = name
            case .text(let text): mark = text
            }
        } else if grade == .illegal {
            color = TalkPanelPalette.bad
            symbol = "nosign"
        } else {
            color = TalkPanelPalette.unclear
            symbol = "questionmark"
        }
    }
}

/// The move's grade as a small capsule in the grade's color.
private struct TalkPanelGradeChip: View {
    let grade: TalkMoveCheck.Grade
    let theme: BoardTheme

    var body: some View {
        let style = TalkPanelGradeStyle(grade)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol = style.symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            } else if let mark = style.mark {
                Text(mark)
                    .fontWeight(.heavy)
            }
            Text(style.title)
        }
        .font(theme.talkFont(.subheadline, .semibold))
        .foregroundStyle(style.color)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(style.color.opacity(0.15), in: Capsule())
        .overlay { Capsule().strokeBorder(style.color.opacity(0.4), lineWidth: 0.75) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - The Traffic Light

/// Leo's Traffic Light for this go: their threats, the forcing moves, and the move's safety.
/// Each lamp is green when covered, red when missed, and dim when there was nothing to judge.
private struct TalkPanelTrafficLight: View {
    let habits: TalkHabits
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAFFIC LIGHT")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    lamps
                }
                VStack(alignment: .leading, spacing: 10) {
                    lamps
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var lamps: some View {
        lamp("Threats", habits.threats)
        lamp("Forcing", habits.forcing)
        lamp("Safety", habits.safety)
    }

    private func lamp(_ title: String, _ mark: TalkHabits.Mark) -> some View {
        let lit: Bool = mark != TalkHabits.Mark.none
        return HStack(spacing: 8) {
            TalkPanelLamp(mark: mark, glows: theme.glows)
            Text(title)
                .font(theme.talkFont(.subheadline, .semibold))
                .foregroundStyle(lit ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Self.spoken(mark))")
    }

    private static func spoken(_ mark: TalkHabits.Mark) -> String {
        switch mark {
        case .good: return "you covered it"
        case .missed: return "missed"
        case .none: return "nothing to judge this time"
        }
    }
}

/// One lamp: lit green with a check, lit red with a mark, or a dim ring.
private struct TalkPanelLamp: View {
    let mark: TalkHabits.Mark
    let glows: Bool

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 18

    var body: some View {
        ZStack {
            switch mark {
            case .good:
                lit(TalkPanelPalette.good, symbol: "checkmark")
            case .missed:
                lit(TalkPanelPalette.bad, symbol: "exclamationmark")
            case .none:
                Circle()
                    .fill(Color.white.opacity(0.06))
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func lit(_ color: Color, symbol: String) -> some View {
        let glow: Double = glows ? 0.9 : 0.55
        let radius: CGFloat = glows ? 8 : 5
        return ZStack {
            Circle()
                .fill(color)
                .shadow(color: color.opacity(glow), radius: radius)
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.78))
        }
    }
}

// MARK: - Waiting and failing

/// Placeholder rows with a soft sweep of light, while Leo checks. Nothing technical: the engine
/// may still be working, and that's Leo's business.
private struct TalkPanelCheckingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            placeholder(first: 80, second: 130)
            placeholder(first: 130, second: 70)
            placeholder(first: 50, second: 150)
        }
        .modifier(TalkPanelShimmer())
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Coach.current.name) is checking your ideas")
    }

    /// A mark and two lines; the numbers are how much room each line leaves at its end.
    private func placeholder(first: CGFloat, second: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.11))
                        .frame(height: 12)
                    Spacer(minLength: first)
                }
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 10)
                    Spacer(minLength: second)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// Why Leo couldn't answer, in his own plain words (they already say what went wrong).
private struct TalkPanelProblemCard: View {
    let text: String
    let theme: BoardTheme

    var body: some View {
        let accent: Color = theme.challengeAccent
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(theme.talkFont(.body, .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small motions

/// Rows arrive one after another, as if Leo ticks them off. A plain fade with Reduce Motion.
private struct TalkPanelArrival: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                let delay: Double = 0.05 + 0.07 * Double(min(index, 8))
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.42, dampingFraction: 0.86)
                withAnimation(animation.delay(delay)) {
                    shown = true
                }
            }
    }
}

/// A soft band of light sweeping across placeholders. Still with Reduce Motion.
private struct TalkPanelShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    sweep(at: context.date.timeIntervalSinceReferenceDate)
                }
                .mask { content }
                .allowsHitTesting(false)
            }
        }
    }

    private func sweep(at time: Double) -> some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let phase: CGFloat = CGFloat(time.truncatingRemainder(dividingBy: 1.6) / 1.6)
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.16), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.45)
                .offset(x: -width * 0.45 + phase * width * 1.45)
        }
    }
}

/// A dot that breathes while the microphone is open.
private struct TalkPanelLiveDot: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background {
                Circle()
                    .fill(color.opacity(0.4))
                    .scaleEffect(breathing ? 2.6 : 1)
                    .opacity(breathing ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    breathing = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Four small bars moving like a voice, beside Stop while Leo speaks. Still with Reduce Motion.
private struct TalkPanelSpeakingBars: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let still: [CGFloat] = [6, 10, 8, 5]

    var body: some View {
        Group {
            if reduceMotion {
                bars(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    bars(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: 17, height: 12)
        .accessibilityHidden(true)
    }

    private func bars(at time: Double) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: height(of: index, at: time))
            }
        }
    }

    private func height(of index: Int, at time: Double) -> CGFloat {
        if reduceMotion { return Self.still[index % Self.still.count] }
        let wave: Double = (sin(time * 7.5 + Double(index) * 1.4) + 1) / 2
        return CGFloat(3 + 9 * wave)
    }
}

/// Three soft dots while Leo finds his words. Still with Reduce Motion.
private struct TalkPanelTypingDots: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            dots(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                dots(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dots(at time: Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * wave(of: index, at: time))
                    .offset(y: -2.5 * CGFloat(wave(of: index, at: time)))
            }
        }
    }

    private func wave(of index: Int, at time: Double) -> Double {
        if reduceMotion { return 0.4 }
        return (sin(time * 5 - Double(index) * 0.9) + 1) / 2
    }
}
