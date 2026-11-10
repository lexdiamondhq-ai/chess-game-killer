import UIKit

/// The app is laid out for an upright phone. One screen turns: the game against the Ashen
/// King, which on its side becomes his hall (`BroadcastView`). The app's Info.plist lists the
/// sideways orientations so that screen can have them; this keeps every other screen upright.
final class AppOrientation: NSObject, UIApplicationDelegate {
    /// Set while the Ashen King's game is on screen with nothing over it.
    @MainActor private(set) static var allowsLandscape = false

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowsLandscape ? .allButUpsideDown : .portrait
    }

    /// Lets the phone turn sideways, or no longer. When it no longer may and the phone is on
    /// its side, the screen turns upright again.
    @MainActor
    static func allowLandscape(_ allowed: Bool) {
        guard allowsLandscape != allowed else { return }
        allowsLandscape = allowed
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !allowed {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
    }
}
