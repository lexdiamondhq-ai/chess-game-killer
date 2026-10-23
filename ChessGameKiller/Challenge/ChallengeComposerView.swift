import ChessKit
import SwiftUI

/// Making a challenge: your name, the clock and your side, then the link to send by text or email.
/// Below, a code to join someone else's game, and the friend games on this phone.
struct ChallengeComposerView: View {
    let composer: ChallengeComposer
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @AppStorage(ChallengeName.key) private var name = ""
    @AppStorage("challenge.clock") private var control: TimeControl = .rapid10
    @AppStorage("challenge.side") private var side: SideChoice = .white
    @AppStorage("haptics") private var hapticsOn = true
    @State private var joining = false
    @State private var code = ""
    @State private var codeProblem: String?
    @State private var copied = false
    @FocusState private var focus: Field?

    private enum Field {
        case code
    }

    /// The clocks a friend game offers, as on the server.
    static let clocks: [TimeControl] = [.blitz3Plus2, .blitz5, .rapid10, .rapid15Plus10, .unlimited]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let created = composer.created {
                    createdContent(created)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .animation(.snappy(duration: 0.35), value: composer.created?.code)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChallengeTopBar(title: composer.created == nil ? "Challenge a friend" : "Send the link", theme: theme,
                            close: { center.dismiss() }) {
                Color.clear
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sensoryFeedback(.success, trigger: composer.created?.code) { _, new in hapticsOn && new != nil }
        .sensoryFeedback(.selection, trigger: control) { _, _ in hapticsOn }
        .sensoryFeedback(.selection, trigger: side) { _, _ in hapticsOn }
    }

    // MARK: Before the challenge exists

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Play a friend")
                    .font(theme.challengeFont(30, .bold))
                Text("Send a link by text or email. Your friend plays in the app, or right in the browser.")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Your name")
                ChallengeNameField(name: $name, theme: theme)
                Text("Your friend sees this name.")
                    .font(theme.challengeFont(12))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Clock")
                HStack(spacing: 8) {
                    ForEach(Self.clocks) { clock in
                        ChallengeChip(title: clock.name, isOn: control == clock, theme: theme) {
                            control = clock
                        }
                        .accessibilityLabel(clock == .unlimited ? "No clock" : clock.detail)
                    }
                }
                Text(control.detail)
                    .font(theme.challengeFont(12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.snappy(duration: 0.2), value: control)
            }

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "You play")
                ChallengeSidePicker(side: $side, theme: theme)
            }

            FairPlayCard(theme: theme)

            joinRow

            FriendGamesList(theme: theme)
        }
    }

    @ViewBuilder
    private var joinRow: some View {
        if joining {
            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Join a game")
                HStack(spacing: 10) {
                    TextField("Code", text: $code, prompt: Text("Code or link"))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .challengeGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .focused($focus, equals: .code)
                        .onSubmit(join)
                    Button("Join", action: join)
                        .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme, height: 50))
                        .frame(width: 92)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let codeProblem {
                    Text(codeProblem)
                        .font(theme.challengeFont(12))
                        .foregroundStyle(ChallengeColors.urgent)
                        .transition(.opacity)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation(.snappy) { joining = true }
                focus = .code
            } label: {
                (Text("Have a code? ").foregroundStyle(.secondary)
                    + Text("Join a game").fontWeight(.semibold).foregroundStyle(theme.challengeAccent))
                    .font(theme.challengeFont(15))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChallengePressStyle())
        }
    }

    private func join() {
        guard let found = ChallengeLink.code(fromText: code) else {
            withAnimation(.snappy) { codeProblem = "A code has 6 letters and numbers, like 7KQ 2XM." }
            return
        }
        codeProblem = nil
        focus = nil
        center.open(code: found)
    }

    // MARK: Once it exists

    private func createdContent(_ created: FriendGame) -> some View {
        let invite = ChallengeInviteContent(game: created, name: name)
        return VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Your challenge is ready")
                    .font(theme.challengeFont(26, .bold))
                    .multilineTextAlignment(.center)
                Text("Send the link to your friend. The game starts as soon as they open it.")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            codeCard(created, invite: invite)

            HStack(spacing: 10) {
                ShareTile(title: "Text", symbol: "message.fill", theme: theme) {
                    ChallengeSharing.shared.text(invite) { sent in sentInvite(sent) }
                }
                ShareTile(title: "Email", symbol: "envelope.fill", theme: theme) {
                    ChallengeSharing.shared.mail(invite) { sent in sentInvite(sent) }
                }
                ShareTile(title: "More", symbol: "square.and.arrow.up", theme: theme) {
                    ChallengeSharing.shared.share(invite) { sent in sentInvite(sent) }
                }
                ShareTile(title: copied ? "Copied" : "Copy link", symbol: copied ? "checkmark" : "link",
                          isOn: copied, theme: theme) {
                    ChallengeSharing.copy(invite)
                    withAnimation(.snappy) { copied = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.snappy) { copied = false }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in hapticsOn && new }

            Text("The challenge stays open for 7 days. Find it under Friend games.")
                .font(theme.challengeFont(12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func codeCard(_ created: FriendGame, invite: ChallengeInviteContent) -> some View {
        VStack(spacing: 12) {
            Text("CODE")
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Text(ChallengeLink.spaced(created.code))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(created.code.map(String.init).joined(separator: " "))")
            Text(invite.url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(theme.challengeFont(13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.vertical, 2)
            HStack(spacing: 18) {
                Label(created.clock?.label ?? "No clock", systemImage: "stopwatch")
                HStack(spacing: 6) {
                    PieceImage(piece: Piece(.king, color: created.seat.color, square: .e1), theme: theme, size: 18)
                        .frame(width: 18, height: 18)
                    Text("You play \(created.seat.name)")
                }
            }
            .font(theme.challengeFont(14, .medium))
            .foregroundStyle(Color.primary.opacity(0.85))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .challengeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Sent: on to the board to wait there.
    private func sentInvite(_ sent: Bool) {
        guard sent else { return }
        composer.goToBoard()
    }

    // MARK: The bar at the foot

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let problem = composer.problem, composer.created == nil {
                Text(problem)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(ChallengeColors.urgent)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            if composer.created == nil {
                Button {
                    focus = nil
                    Task { await composer.create(name: name, clock: FriendClock(control), side: side) }
                } label: {
                    ZStack {
                        Label("Create challenge", systemImage: "paperplane.fill")
                            .opacity(composer.isCreating ? 0 : 1)
                        if composer.isCreating {
                            ProgressView()
                                .tint(Color.black.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                .disabled(composer.isCreating)
            } else {
                Button {
                    composer.goToBoard()
                } label: {
                    Label("Go to the board", systemImage: "checkerboard.rectangle")
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background { ChallengeBarBackground() }
        .animation(.snappy(duration: 0.25), value: composer.problem)
    }
}

/// One way to send the invite: an icon over its name, in glass.
private struct ShareTile: View {
    let title: String
    let symbol: String
    var isOn = false
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.challengeAccent)
                    .frame(height: 24)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(theme.challengeFont(12, .semibold))
                    .foregroundStyle(isOn ? theme.challengeAccent : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .challengeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel(title)
    }
}

/// A bar at the foot of a screen: frosted, with a hairline along its top.
struct ChallengeBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
