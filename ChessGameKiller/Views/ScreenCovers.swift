import UIKit

/// The screens opened over the home or the game each belong to the view that opened them, and
/// only one can be up at a time. A link from outside (a friend's challenge, the Today's Move
/// reminder, the game on the Lock Screen) brings its own screen forward: the game screen closes
/// the ones it owns and asks the rest to close too (the rivals' hall on Home, Review game and
/// Highlights on a finished game's panel). Before this, the link's screen waited unseen behind
/// whatever was up and popped out whenever that was closed (audit, 2026-11-12).
@MainActor
enum ScreenCovers {
    /// Posted when every screen over the home or the game should close.
    static let closeAll = Notification.Name("ChessGameKiller.closeScreenCovers")

    static func close() {
        NotificationCenter.default.post(name: closeAll, object: nil)
    }

    /// A sheet or a cover is up over the app, whoever opened it.
    static var anyUp: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    /// Waits for whatever is opening or closing to finish (a moment, a second and a half at
    /// most), so the next screen isn't presented over one that is still sliding away.
    static func settled() async {
        try? await Task.sleep(for: .milliseconds(60))
        var waited = 0
        while ChallengePresenter.isTransitioning, waited < 30 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
    }
}
