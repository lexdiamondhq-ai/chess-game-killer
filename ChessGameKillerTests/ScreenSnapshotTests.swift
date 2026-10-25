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
        for key in ["boardTheme", "matchRival", "bigBoard", "sculpted3D", "showBestMoves", "showSecondBest", "rivalBanter"] {
            saved[key] = defaults.object(forKey: key)
        }
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

    /// Hints on and the king tapped, on the whole game screen: castling, the best move, in the
    /// spotlight (the rest of the board dimmed), dots where the king can go, and the move in
    /// words on your line. The runner-up is only in the coach panel.
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
            XCTAssertEqual(match.bestHint?.uci, "e1g1")
        }
    }

    /// Alex's game from 2026-10-24: his knight can take the queen. The spotlight lights the
    /// knight and the queen's square, and his line reads "Hint · Knight takes the queen".
    /// Before and after tapping the knight, on the 3D board and flat.
    func testSpotlightKnightTakesQueen() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(true, forKey: "showBestMoves")
        let fen = "2kr3r/ppp2pbp/5np1/nP1N4/2PNQ1P1/P3P2P/1BR2P2/4K2R b K - 0 20"
        let shots: [(id: String, threeD: Bool, tapped: Bool)] = [
            ("gilded", true, false), ("gilded", true, true), ("gilded", false, false), ("midnight", false, true),
        ]
        for shot in shots {
            defaults.set(shot.id, forKey: "boardTheme")
            defaults.set(shot.threeD, forKey: "sculpted3D")
            let engine = FakeEngine(scripted: [fen: [
                EngineLine(moves: ["f6e4"], evaluation: .centipawns(600)),
                EngineLine(moves: ["c8b8"], evaluation: .centipawns(-300)),
            ]])
            let match = MatchController(engine: engine, sounds: nil)
            let position = try XCTUnwrap(Position(fen: fen))
            match.start(MatchController.Setup(opponent: .computer, playerColor: .black, level: .beginner), from: position)
            if shot.tapped { match.tap(.f6) }
            let name = "spotlight-\(shot.id)\(shot.threeD ? "-3d" : "-flat")\(shot.tapped ? "-tapped" : "")"
            try snapshot(name, match: match, wait: 2.5)
            let best = try XCTUnwrap(match.bestHint)
            XCTAssertEqual(best.uci, "f6e4")
            XCTAssertEqual(HintWords.phrase(for: best, in: match.game), "Knight takes the queen")
        }
    }

    /// Ghost Vision held on the whole game screen: Bg5 h6 Bxf6 Qxf6 as see-through pieces,
    /// fainter each move, trails of dots and red corners on the two pieces taken. Then slid
    /// back to the second move, flat.
    func testGhostVisionOnTheGameScreen() throws {
        defaults.set(false, forKey: "matchRival")
        defaults.set(false, forKey: "showBestMoves")
        let fen = "r1bqk2r/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 6"
        let shots: [(id: String, threeD: Bool, focus: Int?)] = [("gilded", true, nil), ("gilded", false, nil), ("midnight", false, 1)]
        for shot in shots {
            defaults.set(shot.id, forKey: "boardTheme")
            defaults.set(shot.threeD, forKey: "sculpted3D")
            let engine = FakeEngine(scripted: [fen: [
                EngineLine(moves: ["c1g5", "h7h6", "g5f6", "d8f6"], evaluation: .centipawns(35)),
                EngineLine(moves: ["e1g1"], evaluation: .centipawns(25)),
            ]])
            let match = MatchController(engine: engine, sounds: nil)
            let position = try XCTUnwrap(Position(fen: fen))
            match.start(MatchController.Setup(opponent: .computer, playerColor: .white, level: .beginner), from: position)
            let name = "ghost-\(shot.id)\(shot.threeD ? "-3d" : "-flat")\(shot.focus.map { "-step\($0 + 1)" } ?? "")"
            try snapshot(name, match: match, wait: 2.5, vision: GhostVision(holding: true, focus: shot.focus))
            XCTAssertEqual(match.ghostLine?.steps.count, 4)
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
        match.start(MatchController.Setup(level: .club, timeControl: .rapid10))
        for move in Showcase.moves { _ = match.game.playEngineMove(move) }
        return match
    }

    /// `play` runs once the screen is up, so whatever the game screen does in answer to a
    /// move (a check, the end of the game) happens as it would for a person; then the picture
    /// waits `settle` seconds more.
    private func snapshot(_ name: String, startsWithNewGame: Bool = false, trayOpen: Bool = false,
                          match: MatchController? = nil, coachOpen: Bool = false, size: CGSize? = nil,
                          wait: TimeInterval = 3, vision: GhostVision? = nil, then play: (() -> Void)? = nil, settle: TimeInterval = 0) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ContentView(
            startsWithNewGame: startsWithNewGame, trayOpen: trayOpen, startsAtHome: false,
            match: match ?? Self.gameInProgress(), coachOpen: coachOpen, vision: vision))
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
