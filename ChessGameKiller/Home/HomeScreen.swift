import Foundation

/// Whether the app opens on the home screen. Off until Alex picks it; Settings has the switch.
enum HomeScreen {
    static let key = "homeScreen"
    static let defaultOn = false

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }
}
