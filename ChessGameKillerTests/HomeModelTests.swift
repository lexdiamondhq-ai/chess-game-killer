import ChessKit
import XCTest
@testable import ChessGameKiller

/// What the home shows, without drawing it: the clock card, the ladder, the scoresheet and the puzzle.
@MainActor
final class HomeModelTests: XCTestCase {

    // MARK: The clock card

    func testAFirstGameIsAgainstSpark() {
        let match = MatchController(engine: nil, sounds: nil)
        let next = HomeUpNext.make(match: match, side: .white, level: nil, timeControl: .unlimited, hasPlayed: false)
        XCTAssertEqual(next.kind, .firstGame)
        XCTAssertEqual(next.level, .beginner)
        XCTAssertEqual(next.rival.name, "Spark")
        XCTAssertFalse(next.inProgress)
        XCTAssertTrue(next.yourMove, "White moves first")
        XCTAssertEqual(next.moveNumber, 1)
        XCTAssertFalse(next.leavingCosts)
    }

    func testTheNextGameIsSetUpAsLastTime() {
        let match = MatchController(engine: nil, sounds: nil)
        let next = HomeUpNext.make(match: match, side: .black, level: .expert, timeControl: .rapid10, hasPlayed: true)
        XCTAssertEqual(next.kind, .ready)
        XCTAssertEqual(next.level, .expert)
        XCTAssertEqual(next.playerColor, .black)
        XCTAssertFalse(next.yourMove, "Playing Black, the rival moves first")
        XCTAssertEqual(next.sideToMove, .white)
        XCTAssertEqual(next.timeControl, .rapid10)
        let setup = next.setup(side: .black)
        XCTAssertEqual(setup.level, .expert)
        XCTAssertEqual(setup.playerColor, .black)
        XCTAssertEqual(setup.timeControl, .rapid10)

        // Played before but never picked a rival: Pulse, the New Game sheet's own default.
        let unpicked = HomeUpNext.make(match: match, side: .random, level: nil, timeControl: .unlimited, hasPlayed: true)
        XCTAssertEqual(unpicked.kind, .ready)
        XCTAssertEqual(unpicked.level, .club)
        XCTAssertTrue(unpicked.randomSide)
    }

    func testAGameUnderWayIsResumed() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: HomeSample.italianFEN))
        match.start(MatchController.Setup(playerColor: .black, level: .club, timeControl: .blitz5), from: position)
        match.suspendClock()
        let next = HomeUpNext.make(match: match, side: .white, level: .beginner, timeControl: .unlimited, hasPlayed: true)
        XCTAssertEqual(next.kind, .resume)
        XCTAssertTrue(next.inProgress)
        XCTAssertEqual(next.level, .club, "The game under way, not the saved choices")
        XCTAssertEqual(next.playerColor, .black)
        XCTAssertTrue(next.yourMove)
        XCTAssertEqual(next.sideToMove, .black)
        XCTAssertEqual(next.moveNumber, 5, "The move number comes from the position")
        XCTAssertEqual(next.timeControl, .blitz5)
        let yours = try XCTUnwrap(next.yourTime)
        XCTAssertLessThanOrEqual(yours, .seconds(300))
        XCTAssertGreaterThan(yours, .seconds(290))
        XCTAssertNotNil(next.theirTime)
        XCTAssertFalse(next.leavingCosts, "Nothing played yet, so leaving costs nothing")
    }

    func testLeavingALongerGameCountsAsALoss() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(MatchController.Setup(playerColor: .white, level: .casual))
        for move in ["e2e4", "e7e5", "g1f3", "b8c6"] {
            XCTAssertTrue(match.game.playEngineMove(move), "\(move) should be legal")
        }
        let next = HomeUpNext.make(match: match, side: .white, level: .casual, timeControl: .unlimited, hasPlayed: true)
        XCTAssertEqual(next.plies, 4)
        XCTAssertEqual(next.moveNumber, 3)
        XCTAssertTrue(next.leavingCosts)
    }

    func testEveryRivalHasARatingAndAWayOfPlaying() {
        XCTAssertEqual(MatchController.Level.allCases.map(\.rating), [800, 1100, 1500, 2000, 3000])
        XCTAssertEqual(MatchController.Level.club.spokenRating, "about 1500")
        XCTAssertEqual(MatchController.Level.grandmaster.spokenRating, "over 3000")
        XCTAssertEqual(Set(MatchController.Level.allCases.map(\.tagline)).count, 5)
    }

    // MARK: The ladder

    func testPointsAreWrittenTheWayAScoresheetDoes() {
        XCTAssertEqual(HomeLadder.points(0), "0")
        XCTAssertEqual(HomeLadder.points(0.5), "½")
        XCTAssertEqual(HomeLadder.points(2.5), "2½")
        XCTAssertEqual(HomeLadder.points(3), "3")
        // A game's result on the scoresheet: 1 for a win, ½ for a draw, 0 for a loss.
        XCTAssertEqual(HomeScoresheet.score(.win), "1")
        XCTAssertEqual(HomeScoresheet.score(.draw), "½")
        XCTAssertEqual(HomeScoresheet.score(.loss), "0")
    }

    func testTheLadderKeepsScoreAgainstEachRival() {
        let ladder = HomeLadder(games: HomeSample.games())
        XCTAssertEqual(ladder.rungs.map(\.level), MatchController.Level.allCases)
        let pulse = ladder.rungs[MatchController.Level.club.rawValue]
        XCTAssertEqual(pulse.wins, 3)
        XCTAssertEqual(pulse.losses, 1)
        XCTAssertEqual(pulse.draws, 1)
        XCTAssertEqual(pulse.score, "3½–1½")
        XCTAssertEqual(pulse.standing, .ahead)
        XCTAssertEqual(pulse.standingText, "You lead")
        XCTAssertEqual(ladder.rungs[MatchController.Level.expert.rawValue].standing, .behind)
        XCTAssertEqual(ladder.nextToBeat, .expert, "The gentlest rival you don't lead yet")
        XCTAssertEqual(ladder.gamesCounted, 9)
        // Average 1600, five wins and three losses over nine games: about 1689, so 1700.
        XCTAssertEqual(ladder.yourRating, 1700)
    }

    func testANewPlayerHasNoRatingYet() {
        let empty = HomeLadder(games: [])
        XCTAssertNil(empty.yourRating)
        XCTAssertEqual(empty.nextToBeat, .beginner)
        XCTAssertTrue(empty.rungs.allSatisfy { $0.standing == .notPlayed && $0.score == nil })
        XCTAssertNil(HomeLadder.performance([(1500, 1), (1500, 1)]), "Two games say too little")
        XCTAssertEqual(HomeLadder.performance([(1500, 1), (1500, 1), (1500, 0)]), 1650)
        XCTAssertEqual(HomeLadder.performance([(3000, 1), (3000, 1), (3000, 1)]), 3000, "Never above Singularity")
        XCTAssertEqual(HomeLadder.performance([(800, 0), (800, 0), (800, 0)]), 400)
    }

    func testUnfinishedGamesDoNotCount() {
        let games = [game(.club, .unfinished), game(.club, .unfinished), game(.club, .unfinished)]
        let ladder = HomeLadder(games: games)
        XCTAssertEqual(ladder.gamesCounted, 0)
        XCTAssertNil(ladder.yourRating)
        XCTAssertEqual(ladder.rungs[MatchController.Level.club.rawValue].standing, .notPlayed)
    }

    // MARK: The scoresheet

    func testTheScoresheetNamesTheDay() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: .now)!
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }
        XCTAssertEqual(HomeGameRow.day(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(HomeGameRow.day(daysAgo(1), now: now, calendar: calendar),
                       daysAgo(1).formatted(.dateTime.weekday(.abbreviated)), "A scoresheet dates games, so no Yesterday")
        XCTAssertEqual(HomeGameRow.day(daysAgo(3), now: now, calendar: calendar),
                       daysAgo(3).formatted(.dateTime.weekday(.abbreviated)))
        XCTAssertEqual(HomeGameRow.day(daysAgo(12), now: now, calendar: calendar),
                       daysAgo(12).formatted(.dateTime.month(.abbreviated).day()))

        let games = [daysAgo(0), daysAgo(1), daysAgo(6), daysAgo(7), daysAgo(30)].map { RewindSample.game(date: $0) }
        XCTAssertEqual(HomeGameRow.thisWeek(games, now: now, calendar: calendar), 3, "Today and the six days before")
        let rows = HomeGameRow.rows(games.shuffled(), limit: 4, now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.game.date), [daysAgo(0), daysAgo(1), daysAgo(6), daysAgo(7)], "Newest first")
    }

    // MARK: The puzzle

    func testThePuzzleIsTitledTheWayAChessColumnWouldBe() throws {
        func puzzle(_ themes: [String]) throws -> HomePuzzle {
            try XCTUnwrap(HomePuzzle(LichessPuzzle(id: "t", fen: Position.standard.fen, moves: ["e2e4", "e7e5"],
                                                   rating: 1500, themes: themes)))
        }
        let mateInTwo = try puzzle(["mateIn2", "short"])
        XCTAssertEqual(mateInTwo.solver, .black, "The opponent's move is played first")
        XCTAssertEqual(TrainingChess.sideToMove(mateInTwo.fen), .black)
        XCTAssertEqual(mateInTwo.title, "Black to play and mate in two.")
        XCTAssertEqual(try puzzle(["mateIn1"]).title, "Black to play and mate.")
        XCTAssertEqual(try puzzle(["crushing", "fork"]).title, "Black to play and win.")
        XCTAssertEqual(try puzzle(["equality", "endgame"]).title, "Black to play. Find the best move.")
        XCTAssertNil(HomePuzzle(LichessPuzzle(id: "bad", fen: Position.standard.fen, moves: ["e2e5"], rating: 1500, themes: [])))
    }

    /// Solve opens the very puzzle the home is showing, and the next one picked is a different one.
    func testPuzzlesServesThePuzzleTheHomeShows() {
        let pack = (0..<6).map { i in
            LichessPuzzle(id: "p\(i)", fen: Position.standard.fen, moves: ["e2e4", "e7e5"], rating: 1000 + i, themes: ["fork"])
        }
        let store = PuzzleStore(library: PuzzleLibrary(puzzles: pack))
        XCTAssertNil(store.upNext)
        store.prepareUpNext()
        let shown = store.upNext
        XCTAssertNotNil(shown)
        store.prepareUpNext()
        XCTAssertEqual(store.upNext, shown, "The puzzle shown stays until it is played")
        XCTAssertEqual(store.nextRated(), shown)
        XCTAssertNil(store.upNext)
        store.prepareUpNext()
        XCTAssertNotEqual(store.upNext, shown, "The next one is a different puzzle")

        // Changing theme drops the puzzle picked for the old one.
        store.theme = PuzzleTheme.choices[0]
        XCTAssertNil(store.upNext)
    }

    // MARK: Helpers

    private func game(_ level: MatchController.Level, _ result: SavedGame.Result) -> SavedGame {
        let base = RewindSample.game()
        return SavedGame(id: UUID(), date: .now, opponent: level.rival.name, level: level.rawValue,
                         playerIsWhite: true, result: result, accuracy: 80,
                         positions: base.positions, moves: base.moves, moments: base.moments)
    }
}
