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

/// The sculpted 3D set replaced the old default look. The first launch with it switches to it
/// once, and lets computer games keep it rather than the rival's board. The older looks and
/// the "Match rival" switch stay in Settings, and anything picked after this is kept.
enum LookIntroduction {
    static let key = "sculptedIntroduced"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(BoardTheme.ID.sculpted.rawValue, forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
    }
}
