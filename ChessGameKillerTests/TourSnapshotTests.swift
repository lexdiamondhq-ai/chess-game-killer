import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The screens no other test pictures, at iPhone size, so the whole app can be looked over in
/// one run: Settings from top to foot, the rivals' hall, the You panel on the board home, a
/// lesson, Puzzles and Puzzle Rush, an opening line, Guess the Move, Today's Move before it is
/// solved, a game in Rewind on the default look and the coach's deep review of it, Your games
/// and How it works.
/// Saved to SNAPSHOT_DIR as tour-*.png, in the tone the run asked for (see SnapshotTone).
@MainActor
final class TourSnapshotTests: XCTestCase {
    private let theme = BoardTheme.named(.gilded)
    /// Leo stays quiet while the lesson is pictured.
    private static let keys = ["coachVoiceMuted", PieceSet.storageKey, "boardTheme"]
    private var saved: [Any?] = []

    override func setUp() async throws {
        try await super.setUp()
        let defaults = UserDefaults.standard
        saved = Self.keys.map { defaults.object(forKey: $0) }
        defaults.set(true, forKey: "coachVoiceMuted")
    }

    override func tearDown() async throws {
        let defaults = UserDefaults.standard
        for (key, value) in zip(Self.keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try await super.tearDown()
    }

    func testSettingsFromTopToFoot() throws {
        let window = try show(SettingsSheet(), wait: 3)
        try save(window, "tour-settings-1")
        for step in 1...5 {
            scroll(window, to: CGFloat(step) * 640)
            try save(window, "tour-settings-\(step + 1)")
        }
        window.isHidden = true
    }

    /// Pieces sits under Light or dark and above the boards, and the preview at the top follows
    /// a pick as it is made: first the pieces, then the board under them, then a board that plays flat.
    func testTheSettingsPreviewFollowsThePiecesAndTheBoard() throws {
        let defaults = UserDefaults.standard
        defaults.set(PieceSet.stone.rawValue, forKey: PieceSet.storageKey)
        defaults.set(BoardTheme.ID.gilded.rawValue, forKey: "boardTheme")
        let window = try show(SettingsSheet(), wait: 3)
        scroll(window, to: 150)
        try save(window, "settings-pieces-1-stone")
        defaults.set(PieceSet.porcelain.rawValue, forKey: PieceSet.storageKey)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        try save(window, "settings-pieces-2-porcelain")
        defaults.set(BoardTheme.ID.midnight.rawValue, forKey: "boardTheme")
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        try save(window, "settings-pieces-3-porcelain-on-midnight")
        defaults.set(BoardTheme.ID.classic.rawValue, forKey: "boardTheme")
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        try save(window, "settings-pieces-4-flat-board")
        window.isHidden = true
    }

    func testTheRivalsHall() throws {
        let window = try show(RivalsHall(begin: { _ in }, close: {}), wait: 3)
        try save(window, "tour-rivals-hall")
        window.isHidden = true
    }

    /// A rival's film over the hall once it has ended: its last frame, its words and Face, and
    /// I to V under them.
    func testTheRivalsHallFilmEnded() throws {
        let window = try show(RivalsHall(ended: .club, begin: { _ in }, close: {}), wait: 3)
        try save(window, "tour-rivals-hall-ended")
        window.isHidden = true
    }

    func testTheYouPanelOnTheBoardHome() throws {
        let window = try show(HomeSample.home(showsYou: true), wait: 3)
        try save(window, "tour-home-you")
        window.isHidden = true
    }

    func testALesson() throws {
        let sample = TrainSample(settled: true)
        let lesson = try XCTUnwrap(TrainingLibrary.shared?.lessons.first)
        let window = try show(LessonScreen(lesson: lesson, theme: theme).environment(sample.training), wait: 3)
        try save(window, "tour-lesson")
        window.isHidden = true
    }

    func testPuzzlesAndPuzzleRush() throws {
        let sample = TrainSample(settled: true)
        let shots: [(PuzzlesView.Mode, String)] = [(.rated, "tour-puzzles-rated"), (.rush, "tour-puzzles-rush")]
        for (mode, name) in shots {
            let view = PuzzlesView(theme: theme, startMode: mode)
                .environment(sample.puzzles)
                .environment(sample.training)
            let window = try show(view, wait: 5)
            try save(window, name)
            window.isHidden = true
        }
    }

    func testAnOpeningLine() throws {
        let sample = TrainSample(settled: true)
        let line = try XCTUnwrap(GrandmasterContent.shared.openings.first { $0.name == "Italian Game" })
        let view = NavigationStack { OpeningLineView(line: line, theme: theme) }
            .tint(theme.trainingAccent)
            .screenScheme(theme)
            .environment(sample.repertoire)
            .environment(sample.training)
        let window = try show(view, wait: 4)
        try save(window, "tour-opening-line")
        window.isHidden = true
    }

    func testGuessTheMove() throws {
        let sample = TrainSample(settled: true)
        let game = try XCTUnwrap(GrandmasterContent.shared.games.first)
        let view = GuessTheMoveView(game: game, theme: theme)
            .screenScheme(theme)
            .environment(sample.training)
        let window = try show(view, wait: 4)
        try save(window, "tour-guess-the-move")
        window.isHidden = true
    }

    func testTodaysMoveBeforeSolving() throws {
        var record = DailyRecord()
        record.streak = Streak(current: 6, best: 9, lastDay: Trainer.dayString(.now.addingTimeInterval(-86_400)))
        record.seeded = true
        let view = DailyMoveView(theme: theme, morePuzzles: {}, stats: nil)
            .environment(DailyStore(state: record))
            .environment(PuzzleStore())
            .environment(TrainingStore(library: TrainingLibrary.shared))
        let window = try show(view, wait: 3)
        try save(window, "tour-daily-move")
        window.isHidden = true
    }

    func testRewindAndYourGames() throws {
        let vault = GameVault()
        vault.record(RewindSample.game(date: .now.addingTimeInterval(-86_400)))
        var won = RewindSample.game()
        won.result = .win
        vault.record(won)
        let game = try show(RewindView(game: won, theme: theme, engine: nil).environment(vault), wait: 3)
        try save(game, "tour-rewind")
        game.isHidden = true
        let games = try show(RewindGamesView(theme: theme).environment(vault), wait: 2.5)
        try save(games, "tour-your-games")
        games.isHidden = true
    }

    /// The coach's deep review inside Rewind: waiting for it, then at a mistake, the board on the
    /// position before the move with the better one drawn.
    func testTheDeepReview() throws {
        let vault = GameVault()
        let game = RewindSample.game()
        vault.record(game)
        let waiting = try show(
            RewindView(game: game, theme: theme, engine: nil, reviews: DeepReviewTestTransport([.hang]),
                       reviewStore: DeepReviewSample.store(), reviewVoice: DeepReviewTestSpeaker(holds: true),
                       opensReview: true).environment(vault),
            wait: 2.5)
        try save(waiting, "tour-deep-review-waiting")
        waiting.isHidden = true

        // The voice holds on the first part, so the picture is of that part: the mistake.
        let review = DeepReview(coach: "leo", parts: Array(DeepReviewSample.review.parts.dropFirst(2)))
        let reading = try show(
            RewindView(game: game, theme: theme, engine: nil,
                       reviews: DeepReviewTestTransport([.event(.review(review)), .event(.done)]),
                       reviewStore: DeepReviewSample.store(), reviewVoice: DeepReviewTestSpeaker(holds: true),
                       opensReview: true).environment(vault),
            wait: 3)
        try save(reading, "tour-deep-review")
        reading.isHidden = true
    }

    func testHowItWorks() throws {
        let window = try show(NavigationStack { GuideView(theme: theme) {} }.screenScheme(theme), wait: 2.5)
        try save(window, "tour-guide-1")
        scroll(window, to: 700)
        try save(window, "tour-guide-2")
        window.isHidden = true
    }

    // MARK: Drawing

    private func show(_ view: some View, wait: TimeInterval) throws -> UIWindow {
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
