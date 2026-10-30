import ChessKit
import SwiftUI
import UIKit
import XCTest
import simd
@testable import ChessGameKiller

/// The home screen at iPhone size: at rest, scrolled and at the foot; pulled down and with
/// the You panel open; on a first launch; in the real app; with a timed game under way as
/// Black; with friend games; and on other looks.
/// When SNAPSHOT_DIR is set the pictures are saved there, named to sort last so CI prints them at the log's end.
@MainActor
final class HomeSnapshotTests: XCTestCase {

    func testHomeScrolling() throws {
        let window = try show(HomeSample.home())
        // The page fits on about a screen: at rest, partway (the board turning in its window), and at its foot.
        for (name, offset) in [("zz-home-0-top", 0.0), ("zz-home-1-turning", 140.0), ("zz-home-2-cards", 260.0),
                               ("zz-home-3-foot", 2000.0)] {
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

    /// Holding the gold knight in the dock: the five rivals and the other ways to a game rise
    /// out of it over the veiled page, and the jewel wears a cross to close them.
    func testTheJewelsShortcuts() throws {
        let window = try show(HomeSample.home(showsShortcuts: true))
        try save(window, "zz-home-9-shortcuts")
        window.isHidden = true
    }

    func testFirstLaunch() throws {
        let window = try show(HomeSample.home(empty: true))
        try save(window, "zz-home-first-launch")
        window.isHidden = true
    }

    /// A timed game against Pulse, playing Black, left at move 5: the board window says so.
    func testGameUnderWayAsBlack() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: HomeSample.italianFEN))
        match.start(MatchController.Setup(playerColor: .black, level: .club, timeControl: .blitz5), from: position)
        match.suspend()
        let window = try show(HomeSample.home(match: match))
        try save(window, "zz-home-6-black-timed")
        window.isHidden = true
    }

    /// Play a person (Online, or A friend by link) sits right under the board window; further
    /// down, every game still going with a person, with a small board and whose move it is, your move first.
    func testCurrentGamesUnderTheClock() throws {
        let api = FakeChallengeAPI()
        let now = Date().timeIntervalSince1970 * 1000
        let yourMove = FriendGameState.sample(code: "7KQ2XM", moves: ["e2e4", "c7c5"], black: "Sam", now: now - 60_000)
        let theirMove = FriendGameState.sample(code: "P4HRWN", moves: ["d2d4", "g8f6", "c2c4"],
                                               clock: FriendClock(initial: 300, increment: 0), black: "Jordan",
                                               now: now - 600_000)
        var online = FriendGameState.sample(code: "R3ATED", moves: ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3"],
                                            clock: FriendClock(initial: 180, increment: 2), white: "Maya", black: "Alex",
                                            now: now - 30_000)
        online.rated = true
        online.ratings = .init(white: .init(rating: 1342), black: .init(rating: 1262))
        let waiting = FriendGameState.sample(code: "M8TQ3D", status: .waiting,
                                             clock: FriendClock(initial: 180, increment: 2), now: now - 3_600_000)
        let states = [yourMove, theirMove, online, waiting]
        for state in states {
            api.games[state.code] = state
        }
        let records = [FriendGame.sample(yourMove, seat: .white), FriendGame.sample(theirMove, seat: .white),
                       FriendGame.sample(online, seat: .black), FriendGame.sample(waiting, seat: .white)]
        let center = ChallengeCenter(api: api, store: ChallengeStore(games: records), sounds: nil)
        let window = try show(HomeSample.home().environment(center))
        scroll(window, to: 300)
        try save(window, "zz-home-8-friends")
        window.isHidden = true

        // With a game against the computer under way too.
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: HomeSample.italianFEN))
        match.start(MatchController.Setup(playerColor: .black, level: .club, timeControl: .blitz5), from: position)
        match.suspend()
        let all = try show(HomeSample.home(match: match).environment(center))
        scroll(all, to: 300)
        try save(all, "zz-home-8-current-all")
        all.isHidden = true

        let none = ChallengeCenter(api: FakeChallengeAPI(), store: ChallengeStore(), sounds: nil)
        let quiet = try show(HomeSample.home().environment(none))
        try save(quiet, "zz-home-8-friends-none-rest")
        scroll(quiet, to: 260)
        try save(quiet, "zz-home-8-friends-none")
        quiet.isHidden = true
    }

    /// Your move first, then theirs, then open challenges; the header counts the games waiting on you.
    func testCurrentGamesPutYourMoveFirst() {
        let now = Date().timeIntervalSince1970 * 1000
        let theirs = FriendGame.sample(.sample(code: "AAAAAA", moves: ["e2e4"], now: now), seat: .white)
        let open = FriendGame.sample(.sample(code: "BBBBBB", status: .waiting, now: now), seat: .white)
        var ratedState = FriendGameState.sample(code: "CCCCCC", moves: ["e2e4"], now: now)
        ratedState.rated = true
        ratedState.ratings = .init(white: .init(rating: 1300), black: .init(rating: 1200, provisional: true))
        let yours = FriendGame.sample(ratedState, seat: .black)
        let list = HomeCurrentGame.sorted([open, theirs, yours].map(HomeCurrentGame.friend))
        XCTAssertEqual(list.map(\.id), ["CCCCCC", "AAAAAA", "BBBBBB"])
        XCTAssertEqual(list.map(\.status), [.yourMove, .theirMove, .waiting])
        XCTAssertEqual(list[0].kind, .online)
        XCTAssertEqual(list[0].detail, "Online · 1300 · 10+0 · Move 1")
        XCTAssertTrue(list[0].flipped, "Playing Black, Black is at the bottom")
        XCTAssertEqual(list[1].detail, "Friend · 10+0 · Move 1")
        XCTAssertEqual(list[1].shortDetail, "Friend · 10+0")
        XCTAssertEqual(HomeCurrentGame.note(list), "1 needs your move")
        XCTAssertEqual(HomeCurrentGame.note([list[1]]), "Waiting on them")
        XCTAssertNil(HomeCurrentGame.note([]))
        XCTAssertNotNil(yours.fen)
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
        XCTAssertLessThan(walked.distance, rest.distance * 0.75, "and the camera comes closer")
        XCTAssertGreaterThan(pulled.elevation, rest.elevation, "Pulled down, the camera rises")
        // At the end of the walk White's king stands in the middle of the picture, looked at by the crown.
        let king = walked.normalized(SIMD3(0.5, 0.6, 3.5))
        XCTAssertLessThan(abs(king.x), 0.35)
        XCTAssertLessThan(abs(king.y), 0.5)
        let crown = walked.normalized(SIMD3(0.5, 1.15, 3.5))
        XCTAssertLessThan(abs(crown.x), 0.1)
        XCTAssertLessThan(abs(crown.y), 0.15)
    }

    /// Through the board window the pieces stand in its top and its foot is left for the words.
    /// The camera settles in from higher and further back, and turns as the page scrolls.
    func testTheWindowFramesThePieces() {
        let size = CGSize(width: 370, height: 247)
        let rest = HomeWindowBoard.camera(size: size, scrolled: 0, arrival: 0, black: false)
        // White's queen, the top of her crown: in the window, right of the middle, in its top half.
        let queen = rest.screenPoint(SIMD3(-0.5, 1.2, 3.5), in: size)
        XCTAssertGreaterThan(queen.x, size.width * 0.5)
        XCTAssertLessThan(queen.x, size.width * 0.95)
        XCTAssertGreaterThan(queen.y, 8, "The crown clears the window's top")
        XCTAssertLessThan(queen.y, size.height * 0.45, "and stands above the words at the foot")
        // The pieces' feet on White's back rank sit above the title too.
        let foot = rest.screenPoint(SIMD3(-0.5, 0, 3.5), in: size)
        XCTAssertLessThan(foot.y, size.height * 0.72)

        let start = HomeWindowBoard.camera(size: size, scrolled: 0, arrival: 1, black: false)
        XCTAssertGreaterThan(start.elevation, rest.elevation, "It settles in from above")
        XCTAssertGreaterThan(start.distance, rest.distance, "and from further back")
        let turned = HomeWindowBoard.camera(size: size, scrolled: 1, arrival: 0, black: false)
        XCTAssertGreaterThan(turned.azimuth - rest.azimuth, 0.3, "Scrolling turns the board")
        let black = HomeWindowBoard.camera(size: size, scrolled: 0, arrival: 0, black: true)
        XCTAssertLessThan(black.eye.z, 0, "Playing Black, the window looks from Black's side")
    }

    // MARK: Someone at the Table

    /// The rival's light hangs in the studio's rig, above the window and out of sight, and
    /// pools on the board right under the orb in the window's top, from either side.
    func testTheRivalsLightPoolsUnderTheOrb() {
        let size = CGSize(width: 370, height: 247)
        let orb = HomeRivalPresence.center(in: size)
        let light = HomeWindowBoard.presence(.orange, arrival: 0, leaning: false)
        let below = SIMD3<Float>(light.position.x, 0, light.position.z)
        for black in [false, true] {
            let camera = HomeWindowBoard.camera(size: size, scrolled: 0, arrival: 0, black: black)
            let turn = simd_quatf(angle: camera.azimuth, axis: SculptedCamera.up)
            let pool = camera.screenPoint(turn.act(below), in: size)
            XCTAssertEqual(pool.x, orb.x, accuracy: 30, "The light falls under the orb, across (black: \(black))")
            XCTAssertEqual(pool.y, orb.y, accuracy: 30, "and down (black: \(black))")
            let lamp = camera.screenPoint(turn.act(light.position), in: size)
            XCTAssertLessThan(lamp.y, 0, "The lamp itself hangs above the window")
        }
    }

    /// The light comes up as the camera settles in, and leans in while a game waits on your move.
    func testTheRivalsLightComesUpAsTheCameraSettles() {
        let arriving = HomeWindowBoard.presence(.orange, arrival: 1, leaning: false)
        let settled = HomeWindowBoard.presence(.orange, arrival: 0, leaning: false)
        let leaning = HomeWindowBoard.presence(.orange, arrival: 0, leaning: true)
        XCTAssertLessThan(arriving.strength, settled.strength * 0.5)
        XCTAssertEqual(settled.strength, 1, accuracy: 0.001)
        XCTAssertGreaterThan(leaning.strength, settled.strength)
        // In a game it stands farther off, so less of it reaches the middle of the board.
        XCTAssertLessThan(middle(SculptedPresence.game(.orange)), middle(settled) * 0.5, "Softer in a game, where the board is the point")
    }

    /// How much of a presence's light reaches the middle of the board: its strength, fading
    /// with distance until its reach (a simple stand-in for SceneKit's falloff).
    private func middle(_ presence: SculptedPresence) -> Float {
        let distance: Float = simd_length(presence.position)
        return presence.strength * max(0, 1 - distance / presence.reach)
    }

    /// In a game the rival's light is low behind its back rank, so its gleam on the polished
    /// board (where the eye sees the light mirrored) lands past the far edge, not on the squares
    /// in play, from either side of the board.
    func testTheRivalsLightInAGameGleamsPastTheFarEdge() {
        let light = SculptedPresence.game(.orange).position
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(SculptedCamera.Framing.standing.aspect), flipped: flipped)
            // The light turns with the camera (it hangs in the studio's rig).
            let turn = simd_quatf(angle: camera.azimuth, axis: SculptedCamera.up)
            let lamp: SIMD3<Float> = turn.act(light)
            // The gleam is where the line from the eye to the lamp's mirror image under the
            // board crosses the board.
            let mirrored = SIMD3<Float>(lamp.x, -lamp.y, lamp.z)
            let eye: SIMD3<Float> = camera.eye
            let part: Float = eye.y / (eye.y + lamp.y)
            let toMirror: SIMD3<Float> = mirrored - eye
            let gleam: SIMD3<Float> = eye + part * toMirror
            let across: Float = simd_length(SIMD2<Float>(gleam.x, gleam.z))
            XCTAssertGreaterThan(across, SculptedCamera.boardHalfWidth + 0.5, "The gleam lands past the board (flipped: \(flipped))")
            XCTAssertLessThan(lamp.y, SculptedCamera.tallest, "Lower than the king's cross, so it edges the pieces rather than lighting them")
        }
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
                     showsYou: Bool = false, showsShortcuts: Bool = false) -> some View {
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
        // Five days in a row up to yesterday, and two of today's three puzzles solved.
        var daily = DailyRecord()
        if !empty {
            daily.streak = Streak(current: 5, best: 9, lastDay: Trainer.dayString(.now.addingTimeInterval(-86_400)))
            daily.day = Trainer.dayString(.now)
            daily.puzzlesSolved = 2
        }
        daily.seeded = true
        return HomeView(match: game, theme: .named(theme), actions: HomeActions(), showsYou: showsYou,
                        showsShortcuts: showsShortcuts)
            .environment(DailyStore(state: daily))
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
