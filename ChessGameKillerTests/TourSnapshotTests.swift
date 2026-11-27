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

    /// A game against a friend in the Rich finish (Alex's pick B, 2026-11-27): marble, gilded player
    /// cards with a glow on the side to move, gold crests, a gold rim on the flat board, the moves
    /// on glass and the dock's gold coins with React; then the React row open and a bubble sent.
    func testAFriendGame() throws {
        var state = FriendGameState.sample(moves: ["d2d4", "d7d5", "e2e4"], clock: nil, white: "Alex", black: "Chris")
        state.white.knowsReactions = true
        state.black.knowsReactions = true
        let api = FakeChallengeAPI()
        api.games[state.code] = state
        let game = OnlineGame(record: .sample(state, seat: .white), api: api, sounds: nil, initial: state)
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil)
        let view = ZStack {
            TrainingBackdrop(theme: theme)
            ChallengeGameView(game: game, theme: theme)
        }
        .tint(theme.challengeAccent)
        .screenScheme(theme)
        .environment(center)
        let window = try show(view, wait: 4)
        try save(window, "tour-friend-game-1")
        Task { await game.react(.nice) }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(game.bubbles[.white]?.reaction, .nice)
        XCTAssertEqual(api.actions.last?.action, .reactNice)
        try save(window, "tour-friend-game-2-bubble")
        window.isHidden = true
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

    /// The game-over card as a scoreboard (Alex's pick A, 2026-11-24): the score carved between
    /// the two sides, the numbers on one gold line, one gold Rematch and quiet words under it.
    func testTheGameOverScoreboard() throws {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping()
        XCTAssertTrue(match.playOwnMove("e2e4"))
        match.resign()
        XCTAssertTrue(match.isOver)
        let view = VStack {
            Spacer()
            CoachOrb(match: match, theme: theme, isExpanded: .constant(true),
                     newGame: nil, home: {}, showGames: {})
                .padding(.horizontal, 12)
        }
        .background(Color(red: 0.12, green: 0.09, blue: 0.06))
        let window = try show(view, wait: 2)
        try save(window, "tour-game-over-scoreboard")
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

    /// What Play on a rival opens: its film, then the same words and Face as the hall's ending.
    func testARivalsWelcome() throws {
        let window = try show(RivalWelcome(film: .of(.beginner), begin: {}, back: {}), wait: 3)
        try save(window, "tour-rival-welcome")
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

    /// Tapping the coach's "Blunder" verdict: the board before the move, the better move's arrow,
    /// and the piece glided there, see-through (Alex, 2026-11-24).
    func testTheMissedMoveAfterTappingTheVerdict() throws {
        let review = MoveReview(
            id: 1, grade: .blunder, played: "Bc4", best: "Rxe6", evaluation: nil,
            fenBefore: "r1bqk1nr/1p2b2p/2p1npp1/p5B1/P3R3/2NB4/1PP1QPPP/R5K1 w kq - 0 16",
            playedUCI: "d3c4", bestUCI: "e4e6"
        )
        let missed = try XCTUnwrap(MissedMove(review))
        XCTAssertEqual(missed.from, Square("e4"))
        XCTAssertEqual(missed.to, Square("e6"))
        XCTAssertEqual(missed.after[Square("e6")]?.piece(at: Square("e6")).kind, .rook)
        XCTAssertNil(missed.after[Square("e4")])
        let view = ZStack {
            Color.black.ignoresSafeArea()
            MissedMoveBoard(missed: missed, theme: theme, flipped: false, in3D: false, framing: .standing, close: {})
                .padding(.horizontal, 0)
                .padding(.bottom, 60)
        }
        let window = try show(view, wait: 2.6)
        try save(window, "tour-missed-move")
        window.isHidden = true
    }

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
