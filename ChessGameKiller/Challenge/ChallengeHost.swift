import SwiftUI

/// Shows Challenge a friend over the whole app: opens challenge links (from Messages, Mail or
/// Safari) and covers the screen with the composer, an invite or a game while one is up.
/// Applied once, at the app's root, inside the environment that holds the `ChallengeCenter`.
struct ChallengeHost: ViewModifier {
    @Environment(ChallengeCenter.self) private var center: ChallengeCenter?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            // A challenge a friend sent by username, over the app until it's opened or let go.
            .overlay(alignment: .top) {
                if let center, !center.isPresenting, let note = center.friends.inbox.first {
                    FriendInviteBanner(note: note, theme: BoardTheme.named(themeID)) {
                        center.friends.dismiss(note)
                        center.open(code: note.code)
                    } close: {
                        center.friends.dismiss(note)
                    }
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(note.id)
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.2), value: center?.friends.inbox.first?.id)
            // Looks for challenges sent by username while the app is open: now, then every 30 seconds.
            .task(id: scenePhase) {
                guard scenePhase == .active, let center, !center.holdsStill else { return }
                while !Task.isCancelled {
                    await center.friends.checkInbox(force: true)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            // A tapped phone alert opens its game (PhoneAlerts), even when it launched the app.
            .onReceive(NotificationCenter.default.publisher(for: PhoneAlertLink.notification)) { _ in
                if let code = PhoneAlertLink.take() { center?.open(code: code) }
            }
            .task {
                if let code = PhoneAlertLink.take() { center?.open(code: code) }
            }
            .onReceive(NotificationCenter.default.publisher(for: PhoneAlertLink.inboxNotification)) { _ in
                Task { await center?.friends.checkInbox(force: true) }
            }
            .onOpenURL { url in
                // The Today's Move widget opens the game screen's daily puzzle, and the game on the
                // Lock Screen opens that game; every other link is a challenge.
                if DailyLink.matches(url) {
                    DailyLink.open()
                } else if LiveGameLink.matches(url) {
                    LiveGameLink.open()
                } else {
                    center?.open(url)
                }
            }
            // Universal links, once the server serves the association file.
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { center?.open(url) }
            }
            .onChange(of: center?.isPresenting == true, initial: true) { _, presenting in
                present(presenting)
            }
            .fullScreenCover(isPresented: $shown, onDismiss: {
                // Closed some other way than its own buttons: the screens go too.
                if center?.isPresenting == true { center?.dismiss() }
            }) {
                if let center {
                    ChallengeScreens()
                        .environment(center)
                }
            }
    }

    /// Covers the screen once whatever was opening or closing (the New Game sheet, say) has finished.
    private func present(_ presenting: Bool) {
        guard presenting else {
            shown = false
            return
        }
        guard !shown else { return }
        Task { @MainActor in
            await ScreenCovers.settled()
            if center?.isPresenting == true { shown = true }
        }
    }
}

extension View {
    /// Challenge a friend's links and screens, for the app's root view.
    func challengeHost() -> some View {
        modifier(ChallengeHost())
    }
}

/// The screens of Challenge a friend, in the home's colors like the other screens around a board.
struct ChallengeScreens: View {
    @Environment(ChallengeCenter.self) private var center
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    /// The screen last shown: it stays drawn while the cover slides away, so closing never shows an empty page.
    @State private var last: ChallengeCenter.Screen?

    var body: some View {
        let theme = BoardTheme.named(themeID)
        let shown = center.screen ?? last
        ZStack {
            TrainingBackdrop(theme: theme)
            screen(shown, theme)
                .id(shown?.key)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: shown?.key)
        .tint(theme.challengeAccent)
        .screenScheme(theme)
        .onChange(of: center.screen?.key, initial: true) {
            if let screen = center.screen { last = screen }
        }
    }

    @ViewBuilder
    private func screen(_ shown: ChallengeCenter.Screen?, _ theme: BoardTheme) -> some View {
        switch shown {
        case .composer(let composer)?:
            ChallengeComposerView(composer: composer, theme: theme)
        case .invite(let invite)?:
            ChallengeJoinView(invite: invite, theme: theme)
        case .game(let game)?:
            ChallengeGameView(game: game, theme: theme)
        case .online(let lobby)?:
            OnlineLobbyView(lobby: lobby, theme: theme)
        case nil:
            Color.clear
        }
    }
}
