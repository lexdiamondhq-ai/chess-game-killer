import ChessKit
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
        for key in ["boardTheme", "matchRival", "bigBoard", "sculpted3D", "rivalBanter"] { saved[key] = defaults.object(forKey: key) }
        defaults.set(false, forKey: "bigBoard")
        // The rival's greeting would stand in for its line in every picture.
        defaults.set(false, forKey: "rivalBanter")
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
        try snapshot("rival-after-sheet", startsWithNewGame: true, match: MatchController(engine: nil, sounds: nil))
    }

    /// A king in check against Spark, a moment after the check: the red callout over the king,
    /// the ring on its square, the CHECK tag in the player's line, and Spark's remark written
    /// into its own line instead of a bubble. Flat and in 3D.
    func testCheckAndRivalRemark() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "rivalBanter")
        for (id, threeD) in [("midnight", false), ("gilded", true), ("faberge", false)] {
            defaults.set(id, forKey: "boardTheme")
            defaults.set(threeD, forKey: "sculpted3D")
            let match = MatchController(engine: nil, sounds: nil)
            match.chance = { 0 }
            // 1. f3 e5 2. Nc3 Qh4+: White blocks on g3 or walks.
            let position = try XCTUnwrap(Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/7q/2N2P2/PPPPP1PP/R1BQKBNR w KQkq - 2 3"))
            match.start(MatchController.Setup(opponent: .computer, playerColor: .white, level: .beginner), from: position, playSound: false)
            XCTAssertNotNil(match.game.checkedKing)
            XCTAssertNotNil(match.rivalLine)
            try snapshot("check-\(id)\(threeD ? "-3d" : "-flat")", match: match, wait: 1.4)
        }
    }

    /// The coach unfolded over a game in progress: the players fold into one line.
    func testCoachOpen() throws {
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(false, forKey: "sculpted3D")
        try snapshot("coach-open-gilded", coachOpen: true)
    }

    /// A 375 by 667 point window, about an iPhone SE, still under the island's safe area: tighter than any phone.
    func testSmallScreen() throws {
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(false, forKey: "sculpted3D")
        try snapshot("small-gilded-flat", size: CGSize(width: 375, height: 667))
    }

    /// A real game against Pulse on a 10-minute clock, seven moves in, with captures on both sides and you to move.
    private static func gameInProgress() -> MatchController {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(MatchController.Setup(level: .club, timeControl: .rapid10), playSound: false)
        for move in Showcase.moves { _ = match.game.playEngineMove(move) }
        return match
    }

    private func snapshot(_ name: String, startsWithNewGame: Bool = false, trayOpen: Bool = false,
                          match: MatchController? = nil, coachOpen: Bool = false, size: CGSize? = nil,
                          wait: TimeInterval = 3) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ContentView(
            startsWithNewGame: startsWithNewGame, trayOpen: trayOpen, startsAtHome: false,
            match: match ?? Self.gameInProgress(), coachOpen: coachOpen))
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
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
