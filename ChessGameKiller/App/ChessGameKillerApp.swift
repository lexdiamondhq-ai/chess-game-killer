import SwiftUI

@main
struct ChessGameKillerApp: App {
    /// Challenge a friend: the links, the live games and the screens they open.
    @State private var challenges = ChallengeCenter.live()

    init() {
        LookIntroduction.applyOnce()
        HintsIntroduction.applyOnce()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .challengeHost()
                .environment(challenges)
        }
    }
}

/// Gilded, the black-and-gold set, replaced Noir as the default look. The first launch with it
/// switches to it once; the other looks stay in Settings, and anything picked after this is kept.
/// (An install that never had Sculpted also turns "Match rival" off, as Sculpted's introduction did.)
enum LookIntroduction {
    static let key = "gildedIntroduced"
    /// Set by the Sculpted introduction, which also turned "Match rival" off.
    static let sculptedKey = "sculptedIntroduced"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(BoardTheme.ID.gilded.rawValue, forKey: "boardTheme")
        if !defaults.bool(forKey: sculptedKey) {
            defaults.set(true, forKey: sculptedKey)
            defaults.set(false, forKey: "matchRival")
        }
    }
}

/// Move hints (the best-move arrows) are off unless the player turns them on: seeing your
/// best moves before you play spoils the game. This turns them off once for players who
/// had them on from before; switching them back on afterwards sticks.
enum HintsIntroduction {
    static let key = "hintsOffByDefault"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(false, forKey: "showBestMoves")
    }
}
