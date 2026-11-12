import SwiftUI
import UIKit

/// The app is laid out for an upright phone. One screen turns: the game against the Ashen
/// King, which on its side becomes his hall (`BroadcastView`). The app's Info.plist lists the
/// sideways orientations so that screen can have them; this keeps every other screen upright.
final class AppOrientation: NSObject, UIApplicationDelegate {
    /// The phone may turn sideways right now: the Ashen King's game is on screen with nothing over it.
    @MainActor private(set) static var allowsLandscape = false
    /// What the game screen last asked for.
    @MainActor private static var gameAllows = false
    /// Screens up over the game that the game screen can't see for itself, by name.
    @MainActor private static var covers: Set<String> = []

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowsLandscape ? .allButUpsideDown : .portrait
    }

    /// Lets the phone turn sideways, or no longer. When it no longer may and the phone is on
    /// its side, the screen turns upright again.
    @MainActor
    static func allowLandscape(_ allowed: Bool) {
        gameAllows = allowed
        apply()
    }

    /// A screen opened from inside the game screen (Review game, Highlights, Think with me) is
    /// up over the game, or has closed. The phone stays upright while one is up.
    @MainActor
    static func cover(_ name: String, up: Bool) {
        if up { covers.insert(name) } else { covers.remove(name) }
        apply()
    }

    @MainActor
    private static func apply() {
        let allowed = gameAllows && covers.isEmpty
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

extension View {
    /// For a screen opened over the game from inside the game screen. Against the Ashen King the
    /// phone may turn sideways, and turned, the game gives way to his hall: that took this screen
    /// away with it, mid-review (audit, 2026-11-12). While this screen is up the phone stays upright.
    func keepsPhoneUpright(_ name: String) -> some View {
        onAppear { AppOrientation.cover(name, up: true) }
            .onDisappear { AppOrientation.cover(name, up: false) }
    }
}
