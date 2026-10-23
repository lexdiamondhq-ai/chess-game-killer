import ChessKit
import SwiftUI
import UIKit
import XCTest
import simd
@testable import ChessGameKiller

/// The home screen at iPhone size: at rest, as the camera walks in, with the glass cards over
/// the board, down the ladder and at the foot; pulled down and with the You panel open; on a
/// first launch; in the real app; with a timed game under way as Black; and on other looks.
/// When SNAPSHOT_DIR is set the pictures are saved there, named to sort last so CI prints them at the log's end.
@MainActor
final class HomeSnapshotTests: XCTestCase {

    func testHomeScrolling() throws {
        let window = try show(HomeSample.home())
        for (name, offset) in [("zz-home-0-top", 0.0), ("zz-home-1-turning", 120.0), ("zz-home-1-closer", 230.0),
                               ("zz-home-2-cards", 520.0), ("zz-home-3-ladder", 900.0), ("zz-home-3-foot", 2000.0)] {
            scroll(window, to: offset)
            try save(window, name)
        }
        window.isHidden = true
    }

    /// Pulling the board down shows the cue; the You panel holds your rating, games and Settings.
    func testPullAndTheYouPanel() throws {
        let window = try show(HomeSample.home())
        scroll(window, to: -60)
        try save(window, "zz-home-4-pulling")
        window.isHidden = true

        let open = try show(HomeSample.home(showsYou: true))
        try save(open, "zz-home-5-you")
        open.isHidden = true
    }

    func testFirstLaunch() throws {
        let window = try show(HomeSample.home(empty: true))
        try save(window, "zz-home-first-launch")
        window.isHidden = true
    }

    /// A timed game against Pulse, playing Black, left at move 5: the clock card says so.
    func testGameUnderWayAsBlack() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: HomeSample.italianFEN))
        match.start(MatchController.Setup(playerColor: .black, level: .club, timeControl: .blitz5), from: position)
        match.suspendClock()
        let window = try show(HomeSample.home(match: match))
        try save(window, "zz-home-6-black-timed")
        scroll(window, to: 230)
        try save(window, "zz-home-6-black-closer")
        window.isHidden = true
    }

    /// The home takes its colors from the board look.
    func testOtherLooks() throws {
        for (look, name, offset) in [(BoardTheme.ID.midnight, "zz-home-7-midnight", 0.0),
                                     (.bordeaux, "zz-home-7-bordeaux", 520.0)] {
            let window = try show(HomeSample.home(theme: look))
            scroll(window, to: offset)
            try save(window, name)
            window.isHidden = true
        }
    }

    /// The real app opening on the home screen.
    func testAppOpensHome() throws {
        // The engine warms up on launch, so the hero picture is given longer to arrive.
        let window = try show(ContentView(startsAtHome: true), wait: 7)
        try save(window, "zz-home-app")
        window.isHidden = true
    }

    func testEveryGlyphIsInTheCatalog() {
        for name in Glyphs.all {
            XCTAssertNotNil(UIImage(named: name), "\(name) is missing from Assets.xcassets/Glyphs")
        }
        XCTAssertTrue(HomeScreen.defaultOn, "The app opens on the home screen")
    }

    // MARK: The camera

    func testTheCameraWalksInAsThePageScrolls() {
        let rest = HomeHeroCamera.camera(aspect: 0.8, progress: 0, pull: 0)
        let walked = HomeHeroCamera.camera(aspect: 0.8, progress: 1, pull: 0)
        let pulled = HomeHeroCamera.camera(aspect: 0.8, progress: 0, pull: 1)
        XCTAssertEqual(rest, HomeHeroCamera.camera(aspect: 0.8))
        XCTAssertGreaterThan(walked.azimuth - rest.azimuth, 0.8, "The board turns as the page scrolls")
        XCTAssertLessThan(walked.distance, rest.distance * 0.7, "and the camera comes closer")
        XCTAssertGreaterThan(pulled.elevation, rest.elevation, "Pulled down, the camera rises")
        // At the end of the walk White's king stands in the middle of the picture, looked at by the crown.
        let king = walked.normalized(SIMD3(0.5, 0.6, 3.5))
        XCTAssertLessThan(abs(king.x), 0.35)
        XCTAssertLessThan(abs(king.y), 0.5)
        let crown = walked.normalized(SIMD3(0.5, 1.15, 3.5))
        XCTAssertLessThan(abs(crown.x), 0.1)
        XCTAssertLessThan(abs(crown.y), 0.15)
    }

    /// Once the camera has come in, the whole crown, cross and all, stands between the status
    /// bar and the clock card, in the middle of the screen; at rest the board fills the top.
    func testTheCrownLandsBetweenTheStatusBarAndTheCard() {
        let screen = CGSize(width: 402, height: 874)
        let layout = HomeLayout(size: CGSize(width: 402, height: 874 - 62 - 34),
                                insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), cardHeight: 190)
        let cardTopThen = layout.cardTop - HomeWorld.arrival * layout.walk
        XCTAssertGreaterThan(layout.crownLook, layout.safeTop + 30)
        XCTAssertLessThan(layout.crownLook, cardTopThen - 30)
        XCTAssertLessThan(layout.restLook, layout.cardTop - 100, "At rest the board stands in the top of the screen")

        let camera = HomeHeroCamera.camera(aspect: Float(screen.width / screen.height),
                                           anchor: Float(1 - 2 * layout.crownLook / screen.height),
                                           progress: 1, pull: 0)
        let cross = camera.screenPoint(SIMD3(0.5, SculptedCamera.tallest, 3.5), in: screen)
        let collar = camera.screenPoint(SIMD3(0.5, 1.0, 3.5), in: screen)
        XCTAssertGreaterThan(cross.y, layout.safeTop + 8, "The cross clears the status bar")
        XCTAssertLessThan(collar.y, cardTopThen - 12, "The crown is clear of the card")
        XCTAssertEqual(cross.x, screen.width / 2, accuracy: 24, "The king stands in the middle")
    }

    func testTheHeroCameraLooksAtTheBoard() {
        let camera = HomeHeroCamera.camera(aspect: 402.0 / 520.0)
        let center = camera.normalized(SIMD3(0, 0, 0))
        XCTAssertLessThan(abs(center.x), 0.2)
        XCTAssertLessThan(abs(center.y), 0.4)
        // White's back rank stands in the picture, below Black's.
        let whiteQueen = camera.normalized(SIMD3(-0.5, 1.2, 3.5))
        let blackQueen = camera.normalized(SIMD3(-0.5, 1.2, -3.5))
        XCTAssertLessThan(abs(whiteQueen.x), 1)
        XCTAssertLessThan(whiteQueen.y, blackQueen.y)
    }

    /// Tilting keeps the eye where it is and puts the old look point where it was asked for.
    func testTiltingStandsTheBoardInTheTopOfTheScreen() {
        let level = HomeHeroCamera.camera(aspect: 402.0 / 874.0, progress: 0.4, pull: 0)
        let look = level.target
        for anchor: Float in [0.35, 0.45] {
            let tilted = HomeHeroCamera.camera(aspect: 402.0 / 874.0, anchor: anchor, progress: 0.4, pull: 0)
            XCTAssertLessThan(simd_distance(tilted.eye, level.eye), 0.001, "The eye stays put")
            XCTAssertEqual(tilted.azimuth, level.azimuth, accuracy: 0.0001)
            let point = tilted.normalized(look)
            XCTAssertEqual(point.x, 0, accuracy: 0.01)
            XCTAssertEqual(point.y, anchor, accuracy: 0.01, "The look point sits at the anchor")
        }
    }

    /// Playing Black, the walk happens on Black's side and ends on Black's king.
    func testPlayingBlackTheWalkEndsOnBlacksKing() {
        let white = HomeHeroCamera.camera(aspect: 0.8, progress: 1, pull: 0)
        let black = HomeHeroCamera.camera(aspect: 0.8, progress: 1, pull: 0, black: true)
        XCTAssertGreaterThan(white.eye.z, 0, "White's camera stands on White's side")
        XCTAssertLessThan(black.eye.z, 0, "Black's on Black's")
        let king = black.normalized(SIMD3(0.5, 0.6, -3.5))
        XCTAssertLessThan(abs(king.x), 0.35)
        XCTAssertLessThan(abs(king.y), 0.5)
        // The mirror: Black's picture is White's, seen across the middle of the board.
        let whiteKing = white.normalized(SIMD3(0.5, 0.6, 3.5))
        XCTAssertEqual(king.x, -whiteKing.x, accuracy: 0.02)
        XCTAssertEqual(king.y, whiteKing.y, accuracy: 0.02)
    }

    // MARK: Drawing

    private func show(_ view: some View, wait: TimeInterval = 3) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    private func scroll(_ window: UIWindow, to offset: CGFloat) {
        guard let scroll = Self.scrollViews(in: window).max(by: { $0.contentSize.height < $1.contentSize.height }) else { return }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: min(top + offset, bottom)), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}

/// A player a week in: games most days against most rivals, a training streak, a puzzle rating.
@MainActor
enum HomeSample {
    /// An Italian Game, Black to play its fifth move.
    static let italianFEN = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R b KQkq - 0 5"

    static func home(empty: Bool = false, theme: BoardTheme.ID = .gilded, match: MatchController? = nil,
                     showsYou: Bool = false) -> some View {
        let game = match ?? MatchController(engine: nil, sounds: nil)
        let vault = GameVault(games: empty ? [] : games())
        let army = empty ? ArmyStore() : ArmyStore(army: armyRecords())
        var progress = TrainingProgress()
        if !empty {
            progress.streak.current = 5
            progress.streak.best = 9
            progress.streak.lastDay = Trainer.dayString(.now, calendar: .current)
        }
        let training = TrainingStore(library: TrainingLibrary.shared, progress: progress)
        var puzzleProgress = PuzzleProgress()
        if !empty {
            puzzleProgress.rating = 1_412
            puzzleProgress.streak = 7
        }
        let puzzles = PuzzleStore(progress: puzzleProgress)
        return HomeView(match: game, theme: .named(theme), actions: HomeActions(), showsYou: showsYou)
            .environment(vault)
            .environment(army)
            .environment(training)
            .environment(puzzles)
    }

    static func games() -> [SavedGame] {
        let calendar = Calendar.current
        let plan: [(daysAgo: Int, level: MatchController.Level, result: SavedGame.Result, accuracy: Int)] = [
            (0, .club, .win, 88), (0, .club, .loss, 74), (1, .expert, .loss, 69), (2, .club, .win, 91),
            (2, .casual, .win, 94), (2, .club, .draw, 82), (3, .grandmaster, .loss, 63), (5, .club, .win, 86),
            (6, .beginner, .win, 97),
        ]
        return plan.map { item in
            let date = calendar.date(byAdding: .day, value: -item.daysAgo, to: .now)!
            let base = RewindSample.game(date: date)
            return SavedGame(id: UUID(), date: date, opponent: item.level.rival.name, level: item.level.rawValue,
                             playerIsWhite: true, result: item.result, accuracy: item.accuracy,
                             positions: base.positions, moves: base.moves, moments: base.moments)
        }
    }

    private static func armyRecords() -> ArmyStore.Army {
        var army = ArmyStore.Army()
        let named: [(ArmySlot, String, Int)] = [
            (.queen, "Seraphine", 420), (.kingsKnight, "Ghost", 260), (.queensBishop, "Abbot", 150),
            (.kingsRook, "Bastion", 120), (.ePawn, "Pip", 90),
        ]
        func record(xp: Int, name: String? = nil) -> PieceRecord {
            var record = PieceRecord()
            record.games = 9
            record.xp = xp
            record.name = name
            return record
        }
        for slot in ArmySlot.allCases { army.records[slot] = record(xp: 20) }
        for (slot, name, xp) in named { army.records[slot] = record(xp: xp, name: name) }
        return army
    }
}
