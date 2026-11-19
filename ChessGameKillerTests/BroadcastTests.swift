import ChessKit
import SceneKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The King's hall: the phone on its side against the Ashen King. The script that picks each
/// figure's film, where things sit on a sideways phone, the films in the bundle, and the rival's
/// move waiting for his hand. Its picture is saved to SNAPSHOT_DIR as broadcast-*.png.
@MainActor
final class BroadcastTests: XCTestCase {
    // MARK: The films

    func testEveryFilmTheScriptAsksForIsInTheApp() {
        for clip in BroadcastScript.allClips {
            XCTAssertNotNil(Bundle.main.url(forResource: clip.resource, withExtension: "mp4"), "\(clip.resource).mp4 is missing")
        }
        XCTAssertNotNil(BroadcastStage.plate, "The still plate is missing")
        XCTAssertNotNil(Bundle.main.url(forResource: BroadcastScript.skyFilm, withExtension: "mp4"), "The dragons' film is missing")
        for mask in ["broadcast-knight-mask", "broadcast-knight-strip", "broadcast-knight-strip-wide", "broadcast-sky-mask"] {
            XCTAssertNotNil(Bundle.main.path(forResource: mask, ofType: "png"), "\(mask).png is missing")
        }
    }

    func testEveryFilmTheCubsForestAsksForIsInTheApp() {
        for clip in BroadcastScript.clips(in: .cub) {
            XCTAssertNotNil(Bundle.main.url(forResource: clip.resource, withExtension: "mp4"), "\(clip.resource).mp4 is missing")
            XCTAssertTrue(clip.resource.hasPrefix("broadcast-cub-"), clip.resource)
        }
        XCTAssertNotNil(BroadcastStage.still(for: .cub), "The forest's still is missing")
        for mask in BroadcastHall.cub.masks {
            XCTAssertNotNil(Bundle.main.path(forResource: mask, ofType: "png"), "\(mask).png is missing")
        }
    }

    // MARK: The script

    func testAQuietMoveIsANearOrAFarReach() {
        let near = BroadcastScript.playerMoved(uci: "e2e4", color: .white, captured: nil, endsGame: false)
        XCTAssertEqual(near.reach, .knight("near"))
        XCTAssertNil(near.storm)
        XCTAssertEqual(near.kingWaits, 2.6, "The King waits for the challenger's hand to set the piece down")
        let far = BroadcastScript.playerMoved(uci: "f3g5", color: .white, captured: nil, endsGame: false)
        XCTAssertEqual(far.reach, .knight("far"))
        // Black's own side of the board is the high ranks.
        XCTAssertEqual(BroadcastScript.playerMoved(uci: "e7e5", color: .black, captured: nil, endsGame: false).reach, .knight("near"))
        XCTAssertEqual(BroadcastScript.playerMoved(uci: "d5d4", color: .black, captured: nil, endsGame: false).reach, .knight("far"))
    }

    func testACaptureBringsTheStormThatFitsWhatTheKingLost() {
        let cases: [(Piece.Kind, String)] = [(.pawn, "pawn"), (.knight, "piece"), (.bishop, "piece"), (.rook, "piece"), (.queen, "queen")]
        for (kind, storm) in cases {
            let cue = BroadcastScript.playerMoved(uci: "e4d5", color: .white, captured: kind, endsGame: false)
            XCTAssertEqual(cue.reach, .knight("strike-\(storm)"), "\(kind)")
            XCTAssertEqual(cue.then, .knight("pleased-\(storm)"), "\(kind)")
            XCTAssertEqual(cue.storm, .king("loss-\(storm)"), "\(kind)")
            XCTAssertEqual(cue.kingWaits, BroadcastScript.stormDelay + BroadcastScript.stormSettles, accuracy: 0.001)
        }
    }

    func testACaptureThatEndsTheGameBringsNoStorm() {
        let cue = BroadcastScript.playerMoved(uci: "h5f7", color: .white, captured: .pawn, endsGame: true)
        XCTAssertEqual(cue.reach, .knight("strike"))
        XCTAssertNil(cue.storm)
        XCTAssertNil(cue.then)
    }

    func testTheKingStrikesWhenHeCapturesAndIsPleasedAfter() {
        let capture = BroadcastScript.kingMoves(uci: "d8d5", color: .black, captures: true)
        XCTAssertEqual(capture.reach, .king("strike"))
        XCTAssertEqual(capture.then, .king("pleased"))
        XCTAssertEqual(BroadcastScript.kingMoves(uci: "g8f6", color: .black, captures: false).reach, .king("near"))
        XCTAssertEqual(BroadcastScript.kingMoves(uci: "f6e4", color: .black, captures: false).reach, .king("far"))
    }

    func testEveryReachSaysWhenTheHandSetsThePieceDown() {
        for clip in BroadcastScript.allClips where ["near", "far", "strike"].contains(where: clip.name.hasPrefix) {
            XCTAssertTrue((2.0...3.0).contains(clip.touch ?? 0), "\(clip.resource)")
        }
        XCTAssertNil(BroadcastClip.king("lean").touch)
        XCTAssertNil(BroadcastClip.knight("pleased-pawn").touch)
    }

    /// The strip of table in the challenger's mask shows his film's table, which the storm's
    /// light doesn't reach: it must be gone before the first flash (28 frames into a storm).
    func testTheTableStripIsGoneBeforeTheStormLightsTheTable() throws {
        for loss in BroadcastLoss.allCases {
            let strip = try XCTUnwrap(loss.strike.strip)
            let gone = try XCTUnwrap(strip.to) + 0.18
            XCTAssertLessThan(gone, BroadcastScript.stormDelay + 28.0 / 24.0, "\(loss)")
        }
        XCTAssertNil(BroadcastClip.knight("think").strip)
        XCTAssertNil(BroadcastClip.king("far").strip, "The King's film is never masked")
        XCTAssertEqual(BroadcastClip.knight("lose").strip, BroadcastClip.Strip(wide: true, from: 0, to: nil))
    }

    func testTheEndings() {
        let won = BroadcastScript.ending(playerWon: true)
        XCTAssertEqual(won?.king, .king("lose"))
        XCTAssertEqual(won?.knight, .knight("win"))
        let lost = BroadcastScript.ending(playerWon: false)
        XCTAssertEqual(lost?.king, .king("win"))
        XCTAssertEqual(lost?.knight, .knight("lose"))
        XCTAssertNil(BroadcastScript.ending(playerWon: nil), "A draw has no ending film")
        XCTAssertTrue(BroadcastClip.king("win").holds)
        XCTAssertFalse(BroadcastClip.king("lean").holds)
    }

    func testIdleFilmsAreOnesTheFigureCanBeCutFrom() {
        var script = BroadcastScript()
        var nods = 0
        var last: BroadcastClip?
        var lastKnight: BroadcastClip?
        var knightFilms = Set<BroadcastClip>()
        for _ in 0..<24 {
            let king = script.idle(.king)
            let knight = script.idle(.knight)
            XCTAssertNotEqual(knight, lastKnight, "The challenger never does the same thing twice running")
            lastKnight = knight
            knightFilms.insert(knight)
            XCTAssertFalse(king.isReach || king.holds)
            XCTAssertFalse(knight.isReach || knight.holds)
            XCTAssertEqual(king.figure, .king)
            XCTAssertEqual(knight.figure, .knight)
            if king.name == "nod" {
                nods += 1
                XCTAssertNotEqual(last?.name, "nod", "The King never nods twice running")
            }
            last = king
        }
        XCTAssertGreaterThan(nods, 0)
        XCTAssertGreaterThanOrEqual(knightFilms.count, 7, "The challenger has plenty to do while he waits")
    }

    func testTheChallengerWincesAtALostPieceInAFilmThatCanBeCut() {
        let wince = BroadcastScript.wince
        XCTAssertEqual(wince.figure, .knight)
        XCTAssertFalse(wince.isReach || wince.holds)
        XCTAssertNil(wince.strip, "He stays inside his own shape")
        XCTAssertTrue(BroadcastScript.allClips.contains(wince))
    }

    func testTheDragonsStandAsideOnlyWhereTheSkyIsTheKings() {
        for name in ["loss-pawn", "loss-piece", "loss-queen", "win", "lose"] {
            XCTAssertTrue(BroadcastClip.king(name).ownsSky, name)
        }
        for name in ["lean", "nod", "near", "far", "strike", "pleased"] {
            XCTAssertFalse(BroadcastClip.king(name).ownsSky, name)
        }
        XCTAssertFalse(BroadcastClip.knight("lose").ownsSky, "The challenger's films never reach the sky")
        XCTAssertEqual(BroadcastScript.skyShare, 352.0 / 1080.0, accuracy: 0.0001)
    }

    func testARivalCaptureIsSeenBeforeItIsPlayed() {
        let game = GameModel()
        for move in ["e2e4", "d7d5"] { XCTAssertTrue(game.playEngineMove(move)) }
        XCTAssertTrue(BroadcastScript.captures(uci: "e4d5", in: game))
        XCTAssertFalse(BroadcastScript.captures(uci: "e4e5", in: game))
        // En passant: the pawn lands on an empty square.
        for move in ["e4e5", "f7f5"] { XCTAssertTrue(game.playEngineMove(move)) }
        XCTAssertTrue(BroadcastScript.captures(uci: "e5f6", in: game))
        XCTAssertFalse(BroadcastScript.captures(uci: "g1f3", in: game))
    }

    // MARK: The Cub's forest

    func testOnlyTheCubAndTheAshenKingHaveAScene() {
        XCTAssertEqual(BroadcastHall(.grandmaster), .ashenKing)
        XCTAssertEqual(BroadcastHall(.beginner), .cub)
        for level in MatchController.Level.allCases where level != .grandmaster && level != .beginner {
            XCTAssertNil(BroadcastHall(level), "\(level)")
        }
    }

    func testTheCubIsUpsetWhenHeLosesAPiece() {
        let cue = BroadcastScript.playerMoved(uci: "e4d5", color: .white, captured: .queen, endsGame: false, in: .cub)
        XCTAssertEqual(cue.reach, .knight("strike", in: .cub))
        XCTAssertEqual(cue.then, .knight("pleased", in: .cub))
        XCTAssertEqual(cue.storm, .king("upset", in: .cub), "No storm in the forest: the Cub's face answers")
        let touch = try? XCTUnwrap(cue.reach.touch)
        XCTAssertEqual(cue.stormAfter, touch ?? -1, accuracy: 0.001, "He is upset as the piece goes down")
        XCTAssertEqual(cue.kingWaits, (touch ?? 0) + BroadcastScript.upsetSettles, accuracy: 0.001)
        let quiet = BroadcastScript.playerMoved(uci: "e2e4", color: .white, captured: nil, endsGame: false, in: .cub)
        XCTAssertEqual(quiet.reach, .knight("near", in: .cub))
        XCTAssertNil(quiet.storm)
        XCTAssertEqual(BroadcastScript.kingMoves(uci: "d8d5", color: .black, captures: true, in: .cub).then, .king("pleased", in: .cub))
    }

    func testEveryForestReachSaysWhenTheHandSetsThePieceDown() {
        for clip in BroadcastScript.clips(in: .cub) where ["near", "far", "strike"].contains(clip.name) {
            XCTAssertTrue((2.0...3.0).contains(clip.touch ?? 0), clip.resource)
            XCTAssertNil(clip.strip, "The forest's mask already holds his side of the table")
        }
        XCTAssertFalse(BroadcastClip.king("win", in: .cub).ownsSky, "No dragons in the forest")
    }

    func testTheCubsEndingHoldsBothPlayers() {
        let won = BroadcastScript.ending(playerWon: true, in: .cub)
        XCTAssertEqual(won?.king, .king("lose", in: .cub))
        XCTAssertNil(won?.knight, "The knight's film stands aside")
        XCTAssertEqual(BroadcastScript.ending(playerWon: false, in: .cub)?.king, .king("win", in: .cub))
        XCTAssertNil(BroadcastScript.ending(playerWon: nil, in: .cub))
        XCTAssertEqual(BroadcastHall.cub.result(playerWon: true), "The Cub is beaten")
    }

    func testTheForestsIdlesNeverRepeatAndItsBreathIsTenSeconds() {
        var script = BroadcastScript(hall: .cub)
        var last: [BroadcastClip.Figure: BroadcastClip] = [:]
        for _ in 0..<12 {
            for figure in [BroadcastClip.Figure.king, .knight] {
                let clip = script.idle(figure)
                XCTAssertEqual(clip.hall, .cub)
                XCTAssertNotEqual(clip, last[figure])
                XCTAssertFalse(clip.isReach || clip.holds)
                last[figure] = clip
            }
        }
        XCTAssertEqual(BroadcastClip.king("think", in: .cub).handover, 232.0 / 24.0, accuracy: 0.001)
        XCTAssertEqual(BroadcastClip.king("lean", in: .cub).handover, BroadcastScript.handover, accuracy: 0.001)
        XCTAssertEqual(BroadcastClip.king("think").handover, BroadcastScript.handover, accuracy: 0.001)
    }

    func testTheForestsBoardStaysBetweenTheHeads() {
        for size in [CGSize(width: 874, height: 402), CGSize(width: 956, height: 440), CGSize(width: 667, height: 375)] {
            let layout = BroadcastLayout(size: size, hall: .cub)
            for aspect in [CGFloat(1.01), 1.3] {
                let board = layout.boardFrame(aspect: aspect)
                XCTAssertEqual(board.midX, size.width / 2, accuracy: 0.5)
                XCTAssertLessThanOrEqual(board.width, 490 * layout.scale + 0.5, "Clear of the Cub's fox hood")
                XCTAssertLessThanOrEqual(board.maxY, layout.y(460) + 0.5)
                XCTAssertGreaterThan(board.width / 9, 18, "Squares a finger can find")
            }
        }
    }

    // MARK: The layout

    func testThePictureFillsASidewaysPhoneAndKeepsItsSides() {
        for size in [CGSize(width: 874, height: 402), CGSize(width: 956, height: 440), CGSize(width: 667, height: 375)] {
            let layout = BroadcastLayout(size: size)
            let scene = layout.sceneFrame
            XCTAssertEqual(scene.width / scene.height, 16.0 / 9.0, accuracy: 0.001)
            XCTAssertEqual(scene.minX, 0, accuracy: 0.5, "The dragons at the sides stay in the picture")
            XCTAssertEqual(scene.width, size.width, accuracy: 0.5)
            XCTAssertLessThanOrEqual(scene.minY, 0.5)
            XCTAssertGreaterThanOrEqual(scene.maxY, size.height - 0.5)
        }
    }

    func testTheBoardSitsBetweenTheTwoHeadsAboveTheTable() {
        for size in [CGSize(width: 874, height: 402), CGSize(width: 956, height: 440), CGSize(width: 667, height: 375)] {
            let layout = BroadcastLayout(size: size)
            for aspect in [CGFloat(1.01), 1.3] {
                let board = layout.boardFrame(aspect: aspect)
                XCTAssertEqual(board.midX, size.width / 2, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(board.minY, 8)
                XCTAssertEqual(board.width / board.height, aspect, accuracy: 0.01)
                // Clear of the challenger's head and the King's hand, and of the pieces on the table.
                XCTAssertLessThanOrEqual(board.width, 640 * layout.scale + 0.5)
                XCTAssertLessThanOrEqual(board.maxY, layout.y(575) + 0.5)
                XCTAssertGreaterThan(board.width / 9, 20, "Squares a finger can find, even on the smallest phone")
            }
        }
    }

    // MARK: The rival's move waits for his hand

    func testTheRivalsMoveLandsWhenTheStageSaysSo() async throws {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        var asked: [String] = []
        var release = false
        match.rivalStage = { uci in
            asked.append(uci)
            while !release, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        match.start(.init(opponent: .computer, playerColor: .white, level: .grandmaster))
        match.tap(.e2)
        match.tap(.e4)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(asked.count, 1, "The stage is handed the move the rival chose")
        XCTAssertEqual(match.game.plyCount, 1, "The move waits for the King's hand")
        release = true
        let deadline = ContinuousClock.now + .seconds(5)
        while match.game.plyCount < 2, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(match.game.plyCount, 2)
        XCTAssertEqual(match.game.lastPlayed?.uci, asked.first)
    }

    func testANewGameDropsAMoveStillBeingActedOut() async throws {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        var release = false
        match.rivalStage = { _ in
            while !release, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        match.start(.init(opponent: .computer, playerColor: .white, level: .grandmaster))
        match.tap(.e2)
        match.tap(.e4)
        try await Task.sleep(for: .milliseconds(600))
        match.rivalStage = nil
        match.start(.init(opponent: .computer, playerColor: .white, level: .grandmaster))
        release = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(match.game.plyCount, 0, "The old game's move never lands in the new one")
    }

    // MARK: Turning the phone

    func testAScreenOverTheGameKeepsThePhoneUpright() {
        // Review game, opened on a finished game against the Ashen King: turning the phone
        // swapped the game for the hall beneath and closed the review with it.
        AppOrientation.allowLandscape(true)
        XCTAssertTrue(AppOrientation.allowsLandscape)
        AppOrientation.cover("review", up: true)
        XCTAssertFalse(AppOrientation.allowsLandscape, "The phone stays upright while Review game is up")
        AppOrientation.cover("review", up: true)
        AppOrientation.cover("review", up: false)
        XCTAssertTrue(AppOrientation.allowsLandscape, "Closed, the hall is a turn away again")
        AppOrientation.cover("think", up: true)
        AppOrientation.allowLandscape(false)
        AppOrientation.cover("think", up: false)
        XCTAssertFalse(AppOrientation.allowsLandscape, "Away from the Ashen King nothing turns")
    }

    // MARK: The picture

    /// The hall on a sideways iPhone, Tilted and Flat, over the still plate (the films don't
    /// play under test), with clocks running.
    func testPictureOfTheHall() throws {
        let defaults = UserDefaults.standard
        let keys = ["boardTheme", "sculpted3D", "matchRival", BoardTilt.storageKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(BoardTheme.ID.gilded.rawValue, forKey: "boardTheme")
        defaults.set(true, forKey: "sculpted3D")
        defaults.set(false, forKey: "matchRival")
        for tilt in [BoardTilt.tilted, .flat] {
            defaults.set(tilt.rawValue, forKey: BoardTilt.storageKey)
            let match = MatchController(engine: nil, sounds: nil)
            match.start(MatchController.Setup(level: .grandmaster, timeControl: .blitz5))
            for move in Showcase.moves.prefix(10) { _ = match.game.playEngineMove(move) }
            try picture(BroadcastView(match: match, theme: .named(.gilded)), "broadcast-\(tilt.rawValue)")
            let cub = MatchController(engine: nil, sounds: nil)
            cub.start(MatchController.Setup(level: .beginner, timeControl: .blitz5))
            for move in Showcase.moves.prefix(10) { _ = cub.game.playEngineMove(move) }
            try picture(BroadcastView(match: cub, theme: .named(.gilded)), "broadcast-cub-\(tilt.rawValue)")
        }
    }

    private func picture(_ view: some View, _ name: String) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        // An iPhone 17 Pro on its side.
        window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        window.layoutIfNeeded()
        // SceneKit draws with Metal, which drawHierarchy leaves out: the 3D board is covered
        // with a picture of itself first.
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
