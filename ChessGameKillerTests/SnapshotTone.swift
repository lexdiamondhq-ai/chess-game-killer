import Foundation
@testable import ChessGameKiller

/// Draws the tests' pictures in another tone when CI asks for one, so every screen can be
/// looked over in Dark (or Middle) as well as the Light that players start on.
///
/// The "iOS build and tests" workflow, run by hand with a tone, passes it as SNAPSHOT_TONE.
/// XCTest makes one of these when the test bundle loads (it is the bundle's principal class, see
/// project.yml), and it makes that tone the default for the run. A test that sets a tone itself
/// still gets the one it set. Without SNAPSHOT_TONE nothing changes.
@objc(SnapshotTone)
final class SnapshotTone: NSObject {
    override init() {
        super.init()
        guard let asked = ProcessInfo.processInfo.environment["SNAPSHOT_TONE"],
              let mode = HomeToneMode(rawValue: asked), mode != HomeToneMode.defaultMode else { return }
        UserDefaults.standard.register(defaults: [HomeToneMode.key: mode.rawValue])
        print("SNAPSHOT TONE \(mode.rawValue)")
    }
}
