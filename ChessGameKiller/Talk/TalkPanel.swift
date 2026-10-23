import ChessKit
import SwiftUI

// Talk it through: the player tells Leo what they see (the other side's threats, their idea,
// their move) and Leo checks each part and answers. The board stays still at the top with the
// verdict in focus lit on it, the talk runs under it, and the talk button sits on a glass dock at
// the foot. The caller presents it full height and dismisses it in `close`.

struct TalkPanel: View {
    let session: TalkSession
    let theme: BoardTheme
    /// Plays the checked move, given in UCI, in the game. Nil hides Play.
    var play: ((String) -> Void)? = nil
    let close: () -> Void

    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @GestureState private var pressing = false
    /// When the talk button went down, to tell a quick tap from a hold.
    @State private var pressedAt: Date?
    /// This press ends a listen that a quick tap started.
    @State private var pressSends = false
    /// A quick tap started listening, so the next tap sends.
    @State private var latched = false

    /// The talk and the dock stop growing here, on iPad.
    private static let column: CGFloat = 560
    private static let maxBoard: CGFloat = 460
    /// A press shorter than this is a tap: it starts listening, and the next tap sends.
    private static let tapLength: TimeInterval = 0.3

    private static let holdHint = "Hold and tell Leo what you see: their threats, your idea, your move."
    private static let typeOnlyHint = "Tell Leo what you see: their threats, your idea, your move."

    var body: some View {
        withHaptics(withLifecycle(screen))
    }

    // MARK: - Layout

    private var screen: some View {
        GeometryReader { proxy in
            let side: CGFloat = boardSide(in: proxy.size)
            let bottomInset: CGFloat = proxy.safeAreaInsets.bottom
            VStack(spacing: 12) {
                TalkPanelBoard(fen: session.fen, flipped: session.player == .black, light: light, theme: theme)
                    .frame(width: side, height: side)
                conversation(bottomInset: bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(motion, value: session.phase)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .frame(maxWidth: 600)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 10)
        }
    }

    /// The board takes a share of the height that leaves room for what each moment needs: the
    /// talk button, the keyboard, or Leo's verdicts. It never gets wider than the screen.
    private func boardSide(in size: CGSize) -> CGFloat {
        let fit: CGFloat = min(size.width - 32, Self.maxBoard, size.height * boardShare)
        return max(120, fit)
    }

    private var boardShare: CGFloat {
        switch session.phase {
        case .ready, .listening: return 0.5
        case .typing: return 0.54
        case .checking, .answered, .failed: return 0.38
        }
    }

    /// The verdict in focus while Leo checks or answers; before that, only the last move.
    private var light: TalkPanelLight {
        switch session.phase {
        case .checking, .answered:
            return TalkPanelLight(check: session.check, focus: session.focus, lastMove: session.lastMove)
        case .ready, .listening, .typing, .failed:
            return TalkPanelLight(check: nil, focus: nil, lastMove: session.lastMove)
        }
    }

    /// The talk scrolls under the dock, so the glass has something to show through it.
    private func conversation(bottomInset: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                TalkPanelConversation(session: session, theme: theme, select: select,
                                      stopSpeaking: { session.stopSpeaking() })
                    .frame(maxWidth: Self.column)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                foot(bottomInset: bottomInset)
            }
            .onChange(of: session.transcript) { _, _ in
                followWords(reader)
            }
            .onChange(of: session.answer) { old, new in
                answerArrived(reader, old: old, new: new)
            }
            .onChange(of: session.phase) { _, new in
                phaseScrolled(reader, to: new)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            CoachAvatar(theme: theme, size: 36, tint: avatarTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Talk it through")
                    .font(theme.challengeFont(15, .semibold))
                    .lineLimit(1)
                Text(status)
                    .font(theme.challengeFont(11, .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            ChallengeBarButton(symbol: "xmark", label: "Close", action: close)
        }
        .padding(6)
        .padding(.leading, 2)
        .frame(height: 48)
        .glassPane(Capsule(style: .continuous))
        .animation(.snappy(duration: 0.25), value: status)
    }

    /// What Leo is doing, under the title. While he checks, the dock says so.
    private var status: String {
        switch session.phase {
        case .ready, .typing, .checking, .failed: return "Coach Leo"
        case .listening: return "Listening…"
        case .answered: return session.isSpeaking ? "Speaking…" : "Coach Leo"
        }
    }

    /// Leo's ring turns green when every idea held up and amber when something didn't.
    private var avatarTint: Color? {
        let showsVerdicts: Bool = session.phase == .checking || session.phase == .answered
        guard showsVerdicts, let check = session.check, check.understood else { return nil }
        switch TalkPanelMood(check) {
        case .allRight: return TalkPanelPalette.good
        case .wrong: return TalkPanelPalette.missed
        case .mixed: return nil
        }
    }

    // MARK: - The dock

    private func foot(bottomInset: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return footContent
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: Self.column)
            .glassPane(shape)
            .background {
                if theme.glows {
                    // Neon's dock glows in its accent, behind the glass, as on the game screen.
                    shape.fill(theme.challengeAccent.opacity(0.16))
                        .blur(radius: 18)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, bottomGap(bottomInset))
            .animation(motion, value: session.phase)
            .animation(motion, value: latched)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Right above the home indicator; a little off the edge on a phone without one, and off the
    /// keyboard while typing.
    private func bottomGap(_ inset: CGFloat) -> CGFloat {
        if fieldFocused { return 8 }
        return inset > 0 ? 0 : 8
    }

    @ViewBuilder
    private var footContent: some View {
        switch session.phase {
        case .ready, .listening:
            // One branch for both, so the press that starts listening is the same press that
            // ends it when the finger lifts.
            talkControls
        case .typing:
            typingControls
                .transition(.opacity)
        case .checking:
            checkingControls
                .transition(.opacity)
        case .answered:
            answeredControls
                .transition(.opacity)
        case .failed:
            failedControls
                .transition(.opacity)
        }
    }

    // MARK: Ready and listening

    private var talkControls: some View {
        let listening: Bool = session.phase == .listening
        let hintColor: Color = listening ? theme.challengeAccent : Color.secondary
        return VStack(spacing: 12) {
            Text(talkHint)
                .font(theme.talkFont(.footnote, listening ? .semibold : .regular))
                .foregroundStyle(hintColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
            if showsTalkButton {
                HStack(spacing: 12) {
                    talkSideButton
                        .frame(maxWidth: .infinity)
                    talkButton
                    // Balances the side button, so the talk button sits in the middle.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    session.beginTyping()
                } label: {
                    Label("Type your plan", systemImage: "keyboard")
                }
                .buttonStyle(TalkPanelButtonStyle(kind: .primary, theme: theme))
            }
        }
    }

    /// Without speech the keyboard is the way in; a listen already under way still shows.
    private var showsTalkButton: Bool {
        session.canListen || session.phase == .listening
    }

    private var talkHint: String {
        if session.phase == .listening {
            return latched ? "Tap to send" : "Release to send"
        }
        return showsTalkButton ? Self.holdHint : Self.typeOnlyHint
    }

    @ViewBuilder
    private var talkSideButton: some View {
        if session.phase == .listening {
            Button {
                cancelListening()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(TalkPanelButtonStyle(kind: .quiet, theme: theme, height: 44))
        } else {
            Button {
                session.beginTyping()
            } label: {
                // The words with the icon when they fit, the words alone, or the icon alone.
                ViewThatFits(in: .horizontal) {
                    Label("Type instead", systemImage: "keyboard")
                    Text("Type instead")
                    Image(systemName: "keyboard")
                }
            }
            .buttonStyle(TalkPanelButtonStyle(kind: .quiet, theme: theme, height: 44))
            .accessibilityLabel("Type instead")
        }
    }

    private var talkButton: some View {
        let listening: Bool = session.phase == .listening
        return TalkPanelTalkButton(session: session, listening: listening, pressed: pressing, theme: theme)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in
                        state = true
                    }
            )
            .onChange(of: pressing) { _, down in
                if down {
                    pressBegan()
                } else {
                    pressEnded()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(listening ? "Send to Leo" : "Talk to Leo")
            .accessibilityHint(listening ? "Sends what you said." : "Starts listening. Activate again to send.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggleListening()
            }
    }

    private func pressBegan() {
        pressedAt = Date()
        if session.phase == .listening {
            // Listening from a tap: this press sends.
            pressSends = true
            return
        }
        pressSends = false
        latched = false
        session.beginListening()
    }

    private func pressEnded() {
        let held: TimeInterval = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
        pressedAt = nil
        if pressSends {
            pressSends = false
            latched = false
            session.endListening()
            return
        }
        if held < Self.tapLength {
            // A quick tap keeps listening until the next tap. Before the first listen it also
            // lets listening start once the microphone is allowed.
            latched = true
            return
        }
        latched = false
        session.endListening()
    }

    /// VoiceOver's double tap: start listening, or send.
    private func toggleListening() {
        if session.phase == .listening {
            latched = false
            session.endListening()
        } else {
            latched = true
            session.beginListening()
        }
    }

    private func cancelListening() {
        latched = false
        pressSends = false
        session.cancelListening()
    }

    // MARK: Typing

    private var typingControls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                cancelTyping()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75) }
                    .contentShape(Circle())
            }
            .buttonStyle(ChallengePressStyle())
            .accessibilityLabel("Cancel")
            field
            sendButton
        }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let edge: Double = fieldFocused ? 0.24 : 0.13
        return TextField("Your plan", text: draftBinding, prompt: Text("Tell Leo what you see"), axis: .vertical)
            .font(theme.talkFont(.body))
            .lineLimit(1...4)
            .submitLabel(.send)
            .focused($fieldFocused)
            .onSubmit {
                sendTyped()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background { shape.fill(Color.black.opacity(0.24)) }
            .overlay { shape.strokeBorder(Color.white.opacity(edge), lineWidth: 0.75) }
            .onChange(of: session.draft) { _, text in
                draftChanged(text)
            }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { session.draft }, set: { session.draft = $0 })
    }

    private var sendButton: some View {
        let ready: Bool = canSend
        return Button {
            sendTyped()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(width: 44, height: 44)
                .background(theme.challengeAccent, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75) }
                .contentShape(Circle())
        }
        .buttonStyle(ChallengePressStyle())
        .disabled(!ready)
        .opacity(ready ? 1 : 0.4)
        .accessibilityLabel("Send to Leo")
    }

    private var canSend: Bool {
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The field grows to four lines, so Return comes in as a new line: one at the end sends,
    /// and any others (from a paste) become spaces.
    private func draftChanged(_ text: String) {
        guard session.phase == .typing, text.contains("\n") else { return }
        let sends: Bool = text.hasSuffix("\n")
        let flat: String = text.replacingOccurrences(of: "\n", with: " ")
        session.draft = sends ? flat.trimmingCharacters(in: .whitespaces) : flat
        if sends {
            sendTyped()
        }
    }

    private func sendTyped() {
        guard canSend else { return }
        fieldFocused = false
        session.sendDraft()
    }

    private func cancelTyping() {
        fieldFocused = false
        session.talkAgain()
    }

    // MARK: Checking, answered, failed

    private var checkingControls: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.challengeAccent)
            Text("Leo is checking…")
                .font(theme.talkFont(.subheadline, .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var answeredControls: some View {
        let move: TalkMoveCheck? = playableMove
        // After a mistake or a blunder, talking it over again comes first.
        let playLeads: Bool = move.map { !Self.isWeak($0.grade) } ?? false
        let talkKind: TalkPanelButtonStyle.Kind = playLeads ? .quiet : .primary
        let playKind: TalkPanelButtonStyle.Kind = playLeads ? .primary : .quiet
        return HStack(spacing: 10) {
            Button {
                session.talkAgain()
            } label: {
                Label("Talk again", systemImage: session.canListen ? "mic.fill" : "keyboard")
            }
            .buttonStyle(TalkPanelButtonStyle(kind: talkKind, theme: theme))
            if let move, let uci = move.uci, let play {
                Button {
                    play(uci)
                } label: {
                    Text(Self.playTitle(move))
                }
                .buttonStyle(TalkPanelButtonStyle(kind: playKind, theme: theme))
            }
        }
    }

    /// The move they named, when it can be played: it's legal and the game takes moves.
    private var playableMove: TalkMoveCheck? {
        guard play != nil, let check = session.check, check.understood, let move = check.move,
              move.uci != nil, move.grade != .illegal else { return nil }
        return move
    }

    private static func isWeak(_ grade: TalkMoveCheck.Grade) -> Bool {
        grade == .mistake || grade == .blunder
    }

    private static func playTitle(_ move: TalkMoveCheck) -> String {
        if let san = move.san, !san.isEmpty { return "Play \(san)" }
        return "Play this move"
    }

    private var failedControls: some View {
        Button {
            session.talkAgain()
        } label: {
            Label("Try again", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(TalkPanelButtonStyle(kind: .primary, theme: theme))
    }

    // MARK: - Following the talk

    private func select(_ target: TalkFocus) {
        withAnimation(motion) {
            session.focus = target
        }
    }

    /// Keeps the live words in view while they come in.
    private func followWords(_ reader: ScrollViewProxy) {
        guard session.phase == .listening else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            reader.scrollTo(TalkPanelConversation.liveID, anchor: .bottom)
        }
    }

    /// Leo's answer comes into view, unless his verdicts are there to read first.
    private func answerArrived(_ reader: ScrollViewProxy, old: String?, new: String?) {
        guard old == nil, new != nil, session.check?.understood != true else { return }
        scroll(reader, to: TalkPanelConversation.answerID, anchor: .bottom)
    }

    private func phaseScrolled(_ reader: ScrollViewProxy, to phase: TalkSession.Phase) {
        switch phase {
        case .checking:
            scroll(reader, to: TalkPanelConversation.liveID, anchor: .top)
        case .failed:
            scroll(reader, to: TalkPanelConversation.problemID, anchor: .bottom)
        case .ready, .listening, .typing, .answered:
            break
        }
    }

    /// Scrolls once this update is done: the view it scrolls to may only arrive in it.
    private func scroll(_ reader: ScrollViewProxy, to id: String, anchor: UnitPoint) {
        let animation: Animation = motion
        Task { @MainActor in
            withAnimation(animation) {
                reader.scrollTo(id, anchor: anchor)
            }
        }
    }

    // MARK: - Lifecycle and haptics

    private func withLifecycle(_ content: some View) -> some View {
        content
            .background {
                ThemeBackdrop(theme: theme)
                    .ignoresSafeArea()
            }
            .tint(theme.challengeAccent)
            .preferredColorScheme(.dark)
            // A swipe down mid-sentence shouldn't close the panel.
            .interactiveDismissDisabled(session.phase == .listening)
            .onAppear {
                session.open()
            }
            .onDisappear {
                session.close()
            }
            .onChange(of: session.phase) { old, new in
                phaseChanged(from: old, to: new)
            }
    }

    private func phaseChanged(from old: TalkSession.Phase, to new: TalkSession.Phase) {
        if new != .listening {
            latched = false
        }
        if new == .typing {
            // The field arrives in this same update; focus it once it's on screen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                if session.phase == .typing {
                    fieldFocused = true
                }
            }
        } else if old == .typing {
            fieldFocused = false
        }
    }

    // One modifier per statement, each closure typed, so the type checker has an easy time.
    private func withHaptics(_ content: some View) -> some View {
        let on: Bool = hapticsOn
        let phase: TalkSession.Phase = session.phase
        let check: TalkCheck? = session.check
        let listening = content.sensoryFeedback(SensoryFeedback.impact(weight: .medium), trigger: phase) {
            (old: TalkSession.Phase, new: TalkSession.Phase) -> Bool in
            on && Self.enters(.listening, from: old, to: new)
        }
        let failing = listening.sensoryFeedback(SensoryFeedback.error, trigger: phase) {
            (old: TalkSession.Phase, new: TalkSession.Phase) -> Bool in
            on && Self.enters(.failed, from: old, to: new)
        }
        return failing.sensoryFeedback(trigger: check) { (old: TalkCheck?, new: TalkCheck?) -> SensoryFeedback? in
            Self.feedback(from: old, to: new, enabled: on)
        }
    }

    /// The phase became `phase` just now.
    private static func enters(_ phase: TalkSession.Phase, from old: TalkSession.Phase,
                               to new: TalkSession.Phase) -> Bool {
        new == phase && old != phase
    }

    /// A tap of success when every idea held up, a warning when something didn't.
    private static func feedback(from old: TalkCheck?, to new: TalkCheck?, enabled: Bool) -> SensoryFeedback? {
        guard enabled, old == nil, let new else { return nil }
        switch TalkPanelMood(new) {
        case .allRight: return .success
        case .wrong: return .warning
        case .mixed: return .impact(weight: .light)
        }
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)
    }
}

// MARK: - Pieces of the dock

/// The big round talk button. While listening it grows, glows, and a ring follows the voice.
private struct TalkPanelTalkButton: View {
    /// Its voice level is read here rather than in the panel, so only the button redraws as it moves.
    let session: TalkSession
    let listening: Bool
    let pressed: Bool
    let theme: BoardTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var scaledSize: CGFloat = 64

    var body: some View {
        let accent: Color = theme.challengeAccent
        let size: CGFloat = min(max(scaledSize, 60), 76)
        let glow: Double = listening ? 0.6 : 0.28
        let radius: CGFloat = listening ? 18 : 8
        let lift: CGFloat = listening ? 0 : 3
        ZStack {
            Circle()
                .fill(accent.opacity(0.18))
                .scaleEffect(haloScale)
                .opacity(listening ? 1 : 0)
            Circle()
                .strokeBorder(accent.opacity(0.8), lineWidth: 2)
                .scaleEffect(ringScale)
                .opacity(listening ? 1 : 0)
            Circle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .overlay { Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75) }
                .shadow(color: accent.opacity(glow), radius: radius, y: lift)
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
        }
        .frame(width: size, height: size)
        .scaleEffect(buttonScale)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: listening)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: pressed)
        .animation(levelAnimation, value: session.level)
    }

    /// How loud the voice is, from 0 to 1.
    private var clampedLevel: CGFloat {
        CGFloat(min(max(session.level, 0), 1))
    }

    /// The ring breathes with the voice; with Reduce Motion it holds still.
    private var ringScale: CGFloat {
        guard listening else { return 1 }
        if reduceMotion { return 1.2 }
        return 1.14 + 0.3 * clampedLevel
    }

    private var haloScale: CGFloat {
        guard listening else { return 1 }
        if reduceMotion { return 1.3 }
        return 1.22 + 0.42 * clampedLevel
    }

    private var buttonScale: CGFloat {
        if listening { return 1.08 }
        return pressed ? 0.94 : 1
    }

    private var levelAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

/// A full-width capsule on the dock: filled with the accent, or quiet. Quiet ones have no glass
/// of their own: they sit on the dock's.
private struct TalkPanelButtonStyle: ButtonStyle {
    enum Kind {
        case primary, quiet
    }

    let kind: Kind
    let theme: BoardTheme
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        TalkPanelButtonBody(configuration: configuration, kind: kind, theme: theme, height: height)
    }
}

private struct TalkPanelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TalkPanelButtonStyle.Kind
    let theme: BoardTheme
    let height: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = Capsule(style: .continuous)
        let pressed: Bool = configuration.isPressed
        let style: Font.TextStyle = height >= 48 ? .body : .subheadline
        configuration.label
            .font(theme.talkFont(style, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: height)
            .background { surface(shape) }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(alpha(pressed: pressed))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: pressed)
    }

    @ViewBuilder
    private func surface(_ shape: Capsule) -> some View {
        switch kind {
        case .primary:
            shape.fill(theme.challengeAccent)
                .overlay { shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75) }
        case .quiet:
            shape.fill(Color.white.opacity(0.09))
                .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75) }
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color.black.opacity(0.88)
        case .quiet: return Color.primary
        }
    }

    private func alpha(pressed: Bool) -> Double {
        if !isEnabled { return 0.45 }
        return pressed ? 0.88 : 1
    }
}
