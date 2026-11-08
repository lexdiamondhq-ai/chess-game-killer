import Foundation

/// Whether the app opens on the home screen (Alex picked it 2026-10-22). Settings has the switch.
enum HomeScreen {
    static let key = "homeScreen"
    static let defaultOn = true

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }
}

/// The app has one home, the Aurora home (Alex, 2026-11-08). Settings no longer offers the
/// switches for the earlier homes, so a switch turned off before stays at its default from
/// now on: the home screen on, the stage home on, the board and sheet on.
enum HomeLayouts {
    static let keys = [HomeScreen.key, HomeStageLayout.key, HomeLayout.key]

    static func settle(_ defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
