import Foundation

/// Whether the app opens on the home screen (Alex picked it 2026-10-22). Settings has the switch.
enum HomeScreen {
    static let key = "homeScreen"
    static let defaultOn = true

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }
}
