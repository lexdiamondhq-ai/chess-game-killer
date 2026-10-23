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
        for key in ["boardTheme", "matchRival", "bigBoard", "sculpted3D", "showBestMoves", "showSecondBest"] {
            saved[key] = defaults.object(forKey: key)
        }
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

    /// A king in check against Spark, a moment after the check: the red callout over the king,
    /// the ring on its square, the CHECK tag in the player's line, and Spark's remark written
    /// into its own line instead of a bubble. Flat and in 3D.
    func testCheckAndRivalRemark() throws {
        defaults.set(false, forKey: "matchRival")
        for (id, threeD) in [("midnight", false), ("gilded", true), ("faberge", false)] {
            defaults.set(id, forKey: "boardTheme")
            defaults.set(threeD, forKey: "sculpted3D")
            let match = MatchController(engine: nil, sounds: nil)
            match.chance = { 0 }
            // 1. f3 e5 2. Nc3 Qh4+: White blocks on g3 or walks.
            let position = try XCTUnwrap(Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/7q/2N2P2/PPPPP1PP/R1BQKBNR w KQkq - 2 3"))
            match.start(MatchController.Setup(opponent: .computer, playerColor: .white, level: .beginner), from: position)
            XCTAssertNotNil(match.game.checkedKing)
            XCTAssertNotNil(match.rivalLine)
            try snapshot("check-\(id)\(threeD ? "-3d" : "-flat")", match: match, wait: 1.4)
        }
    }

    /// The person mates on a flat board: the king falls, and a moment later the coach opens
    /// with the result and the game's summary.
    func testTheEndOfAGame() throws {
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "matchRival")
        defaults.set(false, forKey: "sculpted3D")
        let match = MatchController(engine: nil, sounds: nil)
        match.chance = { 0 }
        // A back-rank mate for Black, the person: Ra1.
        let position = try XCTUnwrap(Position(fen: "r5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1"))
        match.start(MatchController.Setup(opponent: .computer, playerColor: .black, level: .beginner), from: position)
        try snapshot("game-end-gilded-flat", match: match, wait: 1.5, then: {
            match.tap(.a8)
            match.tap(.a1)
        }, settle: 4)
        XCTAssertTrue(match.isOver)
    }

    /// Hints on and the king tapped, on the whole game screen: brackets on the pieces the
    /// coach would move, dots where the king can go, and a halo on castling, its best move.
    func testHintsOnTheGameScreen() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "showBestMoves")
        defaults.set(true, forKey: "showSecondBest")
        let fen = "r1bqk2r/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 6"
        for (id, threeD) in [("midnight", false), ("gilded", true)] {
            defaults.set(id, forKey: "boardTheme")
            defaults.set(threeD, forKey: "sculpted3D")
            let engine = FakeEngine(scripted: [fen: [
                EngineLine(moves: ["e1g1"], evaluation: .centipawns(40)),
                EngineLine(moves: ["c1g5"], evaluation: .centipawns(25)),
            ]])
            let match = MatchController(engine: engine, sounds: nil)
            let position = try XCTUnwrap(Position(fen: fen))
            match.start(MatchController.Setup(opponent: .computer, playerColor: .white, level: .beginner), from: position)
            match.tap(.e1)
            XCTAssertEqual(match.game.selected, .e1)
            try snapshot("hints-\(id)\(threeD ? "-3d" : "-flat")", match: match, wait: 2.5)
            XCTAssertEqual(match.hints.map(\.uci), ["e1g1", "c1g5"])
        }
    }

    /// `play` runs once the screen is up, so whatever the game screen does in answer to a
    /// move (a check, the end of the game) happens as it would for a person; then the picture
    /// waits `settle` seconds more.
    private func snapshot(_ name: String, startsWithNewGame: Bool = false, trayOpen: Bool = false,
                          match: MatchController? = nil, wait: TimeInterval = 3,
                          then play: (() -> Void)? = nil, settle: TimeInterval = 0) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ContentView(startsWithNewGame: startsWithNewGame, trayOpen: trayOpen, startsAtHome: false, match: match))
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        if startsWithNewGame {
            window.rootViewController?.presentedViewController?.dismiss(animated: true)
            RunLoop.main.run(until: Date().addingTimeInterval(3))
        }
        if let play {
            play()
            RunLoop.main.run(until: Date().addingTimeInterval(settle))
        }
        window.layoutIfNeeded()

        // SceneKit draws with Metal, which drawHierarchy leaves out: each 3D board is covered
        // with a picture of itself first, so what floats over it (the Check callout) still shows.
        let covers = Self.sceneViews(in: window).map { view in
            let cover = UIImageView(image: view.snapshot())
            cover.frame = view.bounds
            view.addSubview(cover)
            return cover
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        covers.forEach { $0.removeFromSuperview() }
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
