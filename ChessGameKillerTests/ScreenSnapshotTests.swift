import SceneKit
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
        for key in ["boardTheme", "matchRival", "bigBoard", "sculpted3D"] { saved[key] = defaults.object(forKey: key) }
        defaults.set(false, forKey: "bigBoard")
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    func testGildedScreen() throws {
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "sculpted3D")
        try snapshot("gilded")
    }

    func testBigBoardGilded() throws {
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "sculpted3D")
        defaults.set(true, forKey: "bigBoard")
        try snapshot("bigboard-gilded")
    }

    /// The same set drawn flat, as small boards and the "3D pieces" switch show it.
    func testFlatScreens() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(false, forKey: "sculpted3D")
        for id in ["gilded", "portoro", "noir", "sculpted", "bordeaux", "midnight"] {
            defaults.set(id, forKey: "boardTheme")
            try snapshot("\(id)-flat")
        }
    }

    /// Every 3D look on the whole game screen.
    func testLookScreens() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "sculpted3D")
        for id in ["gilded", "portoro", "noir", "sculpted", "bordeaux", "midnight"] {
            defaults.set(id, forKey: "boardTheme")
            try snapshot("study-screen-\(id)")
        }
    }

    func testBigBoardNeon() throws {
        defaults.set("neon", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "bigBoard")
        try snapshot("bigboard-neon")
    }

    func testBigBoardFabergeTrayOpen() throws {
        defaults.set("faberge", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "bigBoard")
        try snapshot("bigboard-faberge-tray", trayOpen: true)
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

    private func snapshot(_ name: String, startsWithNewGame: Bool = false, trayOpen: Bool = false) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ContentView(startsWithNewGame: startsWithNewGame, trayOpen: trayOpen, startsAtHome: false))
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        if startsWithNewGame {
            window.rootViewController?.presentedViewController?.dismiss(animated: true)
            RunLoop.main.run(until: Date().addingTimeInterval(3))
        }
        window.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            // Metal content is drawn by SceneKit itself, so 3D boards are pictured separately.
            for view in Self.sceneViews(in: window) {
                view.snapshot().draw(in: view.convert(view.bounds, to: window))
            }
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.isHidden = true
    }

    private static func sceneViews(in view: UIView) -> [SCNView] {
        ((view as? SCNView).map { [$0] } ?? []) + view.subviews.flatMap { sceneViews(in: $0) }
    }
}
