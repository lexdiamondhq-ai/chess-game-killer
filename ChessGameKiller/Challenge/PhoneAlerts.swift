import Foundation
import UIKit
import UserNotifications

/// Phone alerts for games with friends (Alex picked "A, the essentials", 2026-11-20): someone
/// challenged you, your friend accepted, it's your move, and 6 hours left in a daily game.
/// The game server sends them through Apple (play/src/push.js); the app only asks the player
/// once, hands the server this phone's address, and opens the right game when one is tapped.
///
/// The iPhone asks "Allow notifications?" the first time the player sends or gets a challenge,
/// when it's plain why. A player who already allowed the daily reminders isn't asked again:
/// their phone is signed up on the next launch.
@MainActor
enum PhoneAlerts {
    /// The phone address last given to the server, so it's sent again only when it changes.
    static let sentKey = "phoneAlerts.sentToken"

    /// Never during tests or CI's screenshots: the system prompt would cover the screen.
    private static var isQuiet: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UserDefaults.standard.string(forKey: "showcase") != nil
    }

    /// A challenge was sent or arrived: asks once, then signs the phone up.
    static func askIfNeeded() {
        guard !isQuiet else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if allowed { UIApplication.shared.registerForRemoteNotifications() }
            case .authorized, .provisional, .ephemeral:
                UIApplication.shared.registerForRemoteNotifications()
            default:
                break
            }
        }
    }

    /// At launch: a phone already allowed to show alerts is signed up (its address can change).
    static func refresh() {
        guard !isQuiet else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Apple gave the phone its address: the server keeps it with the player's private key.
    static func registered(_ deviceToken: Data, defaults: UserDefaults = .standard) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let sandbox = isSandbox
        let mark = "\(token)|\(sandbox)|\(OnlinePlayerKey.current(defaults))"
        guard defaults.string(forKey: sentKey) != mark else { return }
        Task {
            do {
                try await send(token: token, sandbox: sandbox, player: OnlinePlayerKey.current(defaults))
                defaults.set(mark, forKey: sentKey)
            } catch {
                // Tried again at the next launch.
            }
        }
    }

    /// A build from Xcode gets its alerts from Apple's test server, the App Store build from the real one.
    /// The server tries the other one too if this guess is wrong.
    static var isSandbox: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>") else { return false }
        return text[key.upperBound...].prefix(80).contains("development")
    }

    private static func send(token: String, sandbox: Bool, player: String) async throws {
        var request = URLRequest(url: ChallengeLink.serverURL.appending(path: "api/friends/phone"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["player": player, "phone": token, "sandbox": sandbox]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ChallengeError.badReply }
    }
}

/// A tapped alert opens its game. Before the app's screens are up to hear it, the code waits.
@MainActor
enum PhoneAlertLink {
    static let notification = Notification.Name("ChessGameKiller.openAlertGame")
    /// An alert came in while the app was open: look for new challenges now, not in 30 seconds.
    static let inboxNotification = Notification.Name("ChessGameKiller.checkInboxNow")
    /// A game code asked for before ChallengeHost was there to hear it.
    static var pending: String?

    /// The game code an alert carries, if it's one of ours.
    nonisolated static func code(in userInfo: [AnyHashable: Any]) -> String? {
        guard userInfo["aps"] != nil, let code = userInfo["code"] as? String, !code.isEmpty else { return nil }
        return code
    }

    static func open(_ code: String) {
        pending = code
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// The code waiting to open, taken once.
    static func take() -> String? {
        defer { pending = nil }
        return pending
    }
}

extension AppOrientation {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        MainActor.assumeIsolated { PhoneAlerts.refresh() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PhoneAlerts.registered(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No alerts on this phone (a simulator, or no network): the app works the same without them.
    }
}
