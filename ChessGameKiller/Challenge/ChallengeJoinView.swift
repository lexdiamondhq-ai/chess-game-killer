import ChessKit
import SwiftUI

/// A friend's challenge, opened from its link: who sent it, the clock and side in plain words,
/// the fair-play promise, and Accept. Taken, cancelled, expired and unknown games say so plainly.
struct ChallengeJoinView: View {
    let invite: ChallengeInvite
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @AppStorage(ChallengeName.key) private var name = ""
    @AppStorage("haptics") private var hapticsOn = true
    /// Asked for only when the player has never given one.
    @State private var asksForName = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .animation(.snappy(duration: 0.3), value: invite.stage)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChallengeTopBar(title: "Challenge", theme: theme, close: { center.dismiss() }) {
                Color.clear
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onAppear {
            asksForName = ChallengeName.clean(name).isEmpty
        }
        .sensoryFeedback(.error, trigger: invite.joinProblem) { _, new in hapticsOn && new != nil }
    }

    @ViewBuilder
    private var content: some View {
        switch invite.stage {
        case .loading:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Opening the challenge…")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        case .ready(let state):
            ready(state)
        case .unavailable(let title, let detail):
            notice(symbol: "hourglass", title: title, detail: detail)
        case .failed(let text):
            notice(symbol: "wifi.exclamationmark", title: "Can't open the challenge", detail: text)
        }
    }

    private func ready(_ state: FriendGameState) -> some View {
        let mySeat = state.creator.opposite
        return VStack(spacing: 22) {
            VStack(spacing: 12) {
                ChallengeAvatar(name: invite.host, theme: theme, size: 72, online: state[state.creator].online)
                Text("\(invite.host) challenged you")
                    .font(theme.challengeFont(27, .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(ChallengeInviteText.clockWords(state.clock)) · You play \(mySeat.name)")
                    .font(theme.challengeFont(16, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)

            // A smaller board when the name is asked for, so the name field shows above the buttons.
            if let draft = PositionDraft(fen: Position.standard.fen) {
                let side: CGFloat = asksForName ? 168 : 228
                PositionBoard(draft: draft, theme: theme, flipped: mySeat == .black)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if asksForName {
                VStack(alignment: .leading, spacing: 10) {
                    ChallengeSectionTitle(title: "Your name")
                    ChallengeNameField(name: $name, theme: theme)
                    Text("\(invite.host) sees this name.")
                        .font(theme.challengeFont(12))
                        .foregroundStyle(.tertiary)
                }
            }

            FairPlayCard(theme: theme)
        }
    }

    private func notice(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.challengeAccent)
                .frame(width: 68, height: 68)
                .challengeGlass(Circle())
            Text(title)
                .font(theme.challengeFont(22, .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(theme.challengeFont(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    // MARK: The bar at the foot

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch invite.stage {
            case .ready:
                if let problem = invite.joinProblem {
                    Text(problem)
                        .font(theme.challengeFont(13))
                        .foregroundStyle(ChallengeColors.urgent)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                Button {
                    Task { await invite.accept(name: name) }
                } label: {
                    ZStack {
                        Text("Accept")
                            .opacity(invite.isJoining ? 0 : 1)
                        if invite.isJoining {
                            ProgressView()
                                .tint(Color.black.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                .disabled(invite.isJoining)
                Button("Not now") {
                    center.dismiss()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
            case .failed:
                Button("Try again") {
                    Task { await invite.load() }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                Button("Close") {
                    center.dismiss()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
            case .unavailable:
                Button("Challenge someone yourself") {
                    center.compose()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                Button("Close") {
                    center.dismiss()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
            case .loading:
                Button("Cancel") {
                    center.dismiss()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background { ChallengeBarBackground() }
        .animation(.snappy(duration: 0.25), value: invite.joinProblem)
    }
}
