import SwiftUI

/// Shows Challenge a friend over the whole app: opens challenge links (from Messages, Mail or
/// Safari) and covers the screen with the composer, an invite or a game while one is up.
/// Applied once, at the app's root, inside the environment that holds the `ChallengeCenter`.
struct ChallengeHost: ViewModifier {
    @Environment(ChallengeCenter.self) private var center: ChallengeCenter?
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                center?.open(url)
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
            try? await Task.sleep(for: .milliseconds(60))
            var waited = 0
            while ChallengePresenter.isTransitioning, waited < 30 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
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

/// The screens of Challenge a friend, in the player's chosen look.
struct ChallengeScreens: View {
    @Environment(ChallengeCenter.self) private var center
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded

    var body: some View {
        let theme = BoardTheme.named(themeID)
        ZStack {
            ThemeBackdrop(theme: theme)
            screen(theme)
                .id(center.screen?.key)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: center.screen?.key)
        .tint(theme.challengeAccent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func screen(_ theme: BoardTheme) -> some View {
        switch center.screen {
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
