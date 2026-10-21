import SwiftUI

@main
struct ChessGameKillerApp: App {
    init() {
        LookIntroduction.applyOnce()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Noir replaced Sculpted as the default look. The first launch with it switches to it once;
/// the other looks stay in Settings, and anything picked after this is kept. (An install that
/// never had Sculpted also turns "Match rival" off, as Sculpted's introduction did.)
enum LookIntroduction {
    static let key = "noirIntroduced"
    /// Set by the Sculpted introduction, which also turned "Match rival" off.
    static let sculptedKey = "sculptedIntroduced"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(BoardTheme.ID.noir.rawValue, forKey: "boardTheme")
        if !defaults.bool(forKey: sculptedKey) {
            defaults.set(true, forKey: sculptedKey)
            defaults.set(false, forKey: "matchRival")
        }
    }
}
