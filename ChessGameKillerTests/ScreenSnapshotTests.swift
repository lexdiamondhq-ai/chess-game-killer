import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Draws the game screen at iPhone size and checks the board has room on it.
/// When SNAPSHOT_DIR is set (CI passes TEST_RUNNER_SNAPSHOT_DIR), the pictures are saved there.
@MainActor
final class ScreenSnapshotTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var saved: [String: Any?] = [:]

    override func setUp() async throws {
        for key in ["boardTheme", "matchRival"] { saved[key] = defaults.object(forKey: key) }
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    func testRivalBoardScreen() throws {
        defaults.removeObject(forKey: "boardTheme")
        defaults.set(true, forKey: "matchRival")
        try snapshot("rival-default")
    }

    func testNeonScreen() throws {
        defaults.set("neon", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        try snapshot("neon")
    }

    func testFabergeScreen() throws {
        defaults.set("faberge", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        try snapshot("faberge")
    }

    /// The way the app really opens: the New Game sheet first, then the game once it closes.
    func testRivalBoardAfterTheNewGameSheet() throws {
        defaults.removeObject(forKey: "boardTheme")
        defaults.set(true, forKey: "matchRival")
        try snapshot("rival-after-sheet", startsWithNewGame: true)
    }

    private func snapshot(_ name: String, startsWithNewGame: Bool = false) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ContentView(startsWithNewGame: startsWithNewGame))
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        if startsWithNewGame {
            window.rootViewController?.presentedViewController?.dismiss(animated: true)
            RunLoop.main.run(until: Date().addingTimeInterval(3))
        }
        window.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.isHidden = true
    }
}
