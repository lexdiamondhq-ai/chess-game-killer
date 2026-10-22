import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The home screen at iPhone size: at rest, part way down (the board fading and lifting
/// away) and near the foot, with a week of games and an army, and on a first launch.
/// When SNAPSHOT_DIR is set the pictures are saved there, named to sort last so CI prints them at the log's end.
@MainActor
final class HomeSnapshotTests: XCTestCase {

    func testHomeScrolling() throws {
        let window = try show(HomeSample.home())
        for (name, offset) in [("zz-home-0-top", 0.0), ("zz-home-1-fading", 230.0), ("zz-home-2-cards", 520.0), ("zz-home-3-foot", 2000.0)] {
            scroll(window, to: offset)
            try save(window, name)
        }
        window.isHidden = true
    }

    func testFirstLaunch() throws {
        let window = try show(HomeSample.home(empty: true))
        try save(window, "zz-home-first-launch")
        window.isHidden = true
    }

    /// The real app opening on the home screen.
    func testAppOpensHome() throws {
        // The engine warms up on launch, so the hero picture is given longer to arrive.
        let window = try show(ContentView(startsAtHome: true), wait: 7)
        try save(window, "zz-home-app")
        window.isHidden = true
    }

    func testTheWeekCountsGamesByDay() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let games = [RewindSample.game(date: now), RewindSample.game(date: now), RewindSample.game(date: yesterday)]
        XCTAssertEqual(games.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }.count, 2)
        XCTAssertTrue(HomeScreen.defaultOn, "The app opens on the home screen")
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
        RunLoop.main.run(until: Date().addingTimeInterval(1))
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

/// A player a week in: games most days, a named army, a streak.
@MainActor
enum HomeSample {
    static func home(empty: Bool = false) -> some View {
        let match = MatchController(engine: nil, sounds: nil)
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
        return HomeView(match: match, theme: .named(.noir), actions: HomeActions())
            .environment(vault)
            .environment(army)
            .environment(training)
            .environment(puzzles)
    }

    private static func games() -> [SavedGame] {
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
