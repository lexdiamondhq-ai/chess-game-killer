import SwiftUI

@main
struct ChessGameKillerApp: App {
    init() {
        LookIntroduction.applyOnce()
        HintsIntroduction.applyOnce()
    }

    var body: some Scene {
        WindowGroup {
            // The unit tests run inside the app. Its own screen (the 3D home board, the welcome
            // chime, Stockfish warming up) would share the simulator's CPU, main thread and engine
            // with the tests and make their timings flaky, so the test host shows an empty window.
            // Tests that need the app's screens build their own windows on this scene.
            if Self.isUnitTestHost {
                Color.clear
            } else {
                ContentView()
            }
        }
    }

    /// Whether the app was launched to host the unit tests: XCTest sets these in its environment.
    static let isUnitTestHost: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }()
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
