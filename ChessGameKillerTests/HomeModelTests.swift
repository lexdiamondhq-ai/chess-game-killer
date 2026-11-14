import ChessKit
import XCTest
@testable import ChessGameKiller

/// What the home shows, without drawing it: the clock card, the ladder, the scoresheet and the puzzle.
@MainActor
final class HomeModelTests: XCTestCase {

    // MARK: The clock card

    func testAFirstGameIsAgainstTheGentlestCrowd() {
        let match = MatchController(engine: nil, sounds: nil)
        let next = HomeUpNext.make(match: match, side: .white, level: nil, timeControl: .unlimited, hasPlayed: false)
        XCTAssertEqual(next.kind, .firstGame)
        XCTAssertEqual(next.level, .beginner)
        XCTAssertEqual(next.rival.name, "The Cub")
        XCTAssertFalse(next.inProgress)
        XCTAssertTrue(next.yourMove, "White moves first")
        XCTAssertEqual(next.moveNumber, 1)
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
        match.suspend()
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
        XCTAssertFalse(match.newGameForfeits, "Nothing played yet, so leaving costs nothing")
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
        // The home sends New game and the ladder to the New Game sheet, which asks first.
        XCTAssertTrue(match.newGameForfeits)
    }

    func testEveryRivalHasARatingAndAWayOfPlaying() {
        XCTAssertEqual(MatchController.Level.allCases.map(\.rating), [1000, 1200, 1600, 2000, 2500])
        XCTAssertEqual(MatchController.Level.club.spokenRating, "about 1600")
        XCTAssertEqual(MatchController.Level.grandmaster.spokenRating, "over 2500")
        XCTAssertEqual(Set(MatchController.Level.allCases.map(\.tagline)).count, 5)
    }

    // MARK: The ladder

    func testPointsAreWrittenTheWayAScoresheetDoes() {
        XCTAssertEqual(HomeLadder.points(0), "0")
        XCTAssertEqual(HomeLadder.points(0.5), "½")
        XCTAssertEqual(HomeLadder.points(2.5), "2½")
        XCTAssertEqual(HomeLadder.points(3), "3")
        // A game's result on the scoresheet: 1 for a win, ½ for a draw, 0 for a loss.
        XCTAssertEqual(HomeGameRow.score(.win), "1")
        XCTAssertEqual(HomeGameRow.score(.draw), "½")
        XCTAssertEqual(HomeGameRow.score(.loss), "0")
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
        // From 1200: five wins (four over stronger or equal rivals), a draw, three losses
        // to stronger rivals. About 1338; games on the same day may fall in either order.
        XCTAssertEqual(Double(ladder.yourRating ?? 0), 1338, accuracy: 3)
    }

    func testANewPlayerHasNoRatingYet() {
        let empty = HomeLadder(games: [])
        XCTAssertNil(empty.yourRating)
        XCTAssertEqual(empty.nextToBeat, .beginner)
        XCTAssertTrue(empty.rungs.allSatisfy { $0.standing == .notPlayed && $0.score == nil })
        XCTAssertNil(HomeLadder.elo([(1500, 1), (1500, 1)]), "Two games say too little")
        XCTAssertEqual(HomeLadder.elo([(1500, 1), (1500, 1), (1500, 0)]), 1259)
        XCTAssertEqual(HomeLadder.elo([(1000, 0), (1000, 0), (1000, 0)]), 1113, "Losing to a weaker rival costs most")
    }

    /// The count starts where the welcome's answer put the player (audit, 2026-11-09), so a club
    /// player's first number isn't a beginner's; an install that never answered starts at 1,200.
    func testTheRatingStartsWhereTheWelcomeSaid() {
        XCTAssertEqual(HomeLadder.elo([(1500, 1), (1500, 1), (1500, 0)], from: 1800), 1778)
        XCTAssertEqual(HomeLadder.elo([(1000, 0), (1000, 0), (1000, 0)], from: 1000), 943)
        let suite = "HomeLadderStart"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(HomeLadder.savedStart(defaults), 1200)
        WelcomeChoice(experience: .club, look: .gilded).apply(defaults)
        XCTAssertEqual(HomeLadder.savedStart(defaults), 1800)
        let club = HomeLadder(games: HomeSample.games(), start: HomeLadder.savedStart(defaults))
        let anyone = HomeLadder(games: HomeSample.games(), start: HomeLadder.startingRating)
        XCTAssertGreaterThan(club.yourRating ?? 0, anyone.yourRating ?? 0, "The same games count from higher up")
        XCTAssertEqual(club.gamesCounted, anyone.gamesCounted)
        defaults.removePersistentDomain(forName: suite)
    }

    /// Losing can never raise your rating, however strong the rival (Alex, 2026-11-09: the old
    /// performance formula made ten losses to Lionheart read 1,600).
    func testLosingToAStrongRivalNeverRaisesYourRating() {
        let losses = Array(repeating: (rating: 2000, score: 0.0), count: 10)
        XCTAssertEqual(HomeLadder.elo(losses), 1196)
        XCTAssertLessThanOrEqual(HomeLadder.elo(Array(repeating: (2500, 0.0), count: 5)) ?? .max, 1200)
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

    // MARK: Rooms

    /// Rooms holds only what the Today page doesn't (Alex, 2026-11-08): the ways to play a
    /// person, a new game on your own side and clock, and your games. Today's Move, Puzzles,
    /// Analyze and the coach are on Today, so they aren't repeated here. The rivals' hall is the
    /// fifth. Your Grudge is gone (Alex, 2026-11-11).
    func testRoomsHoldOnlyWhatTodayDoesNot() {
        let rooms = HomeShortcutKind.list(online: true)
        XCTAssertEqual(rooms, [.online, .friend, .newGame, .rivals, .games])
        XCTAssertLessThanOrEqual(rooms.count, 6, "Two even rows of three at most")
        XCTAssertEqual(Set(rooms.map(\.title)).count, rooms.count, "Each has a name of its own")
        for kind in rooms {
            XCTAssertFalse(kind.glyph.isEmpty, "\(kind.title) has an icon")
            XCTAssertFalse(kind.hint.isEmpty, "\(kind.title) says where it goes")
        }
    }

    /// Rooms on the Aurora home (Alex, 2026-11-14): New game, which also leads to a friend and to
    /// online, and the castle's three rooms. Your games left Rooms; it is in the You panel.
    func testRoomsAreNewGameAndTheCastleRooms() {
        XCTAssertEqual(HomeShortcutKind.rooms, [.newGame, .trophies, .famous, .dungeon])
        XCTAssertFalse(HomeShortcutKind.rooms.contains(.games))
        XCTAssertEqual(HomeShortcutKind.rooms.compactMap(\.castleRoom), CastleRoom.allCases)
        for kind in HomeShortcutKind.rooms {
            XCTAssertFalse(kind.hint.isEmpty, "\(kind.title) says where it goes")
        }
    }

    /// With no other players to reach, Online and A friend are left out and the rest keep their order.
    func testWithoutOtherPlayersRoomsKeepTheRest() {
        XCTAssertEqual(HomeShortcutKind.list(online: false), [.newGame, .rivals, .games])
    }

    /// The app has one home: a switch for an earlier home turned off before goes back to its default.
    func testEveryoneLandsOnTheOneHome() {
        let defaults = UserDefaults(suiteName: "HomeLayoutsTests")!
        defer { defaults.removePersistentDomain(forName: "HomeLayoutsTests") }
        for key in HomeLayouts.keys { defaults.set(false, forKey: key) }
        HomeLayouts.settle(defaults)
        XCTAssertTrue(HomeScreen.isOn(defaults))
        XCTAssertTrue(HomeStageLayout.isOn(defaults))
        XCTAssertTrue(HomeLayout.usesSheet(defaults))
    }

    /// The "3D pieces" switch left Settings: one turned off before goes back to its default, on.
    func testEveryoneLandsOnTheStoneBoard() {
        let defaults = UserDefaults(suiteName: "SculptedSettingTests")!
        defer { defaults.removePersistentDomain(forName: "SculptedSettingTests") }
        defaults.set(false, forKey: SculptedSetting.key)
        SculptedSetting.settle(defaults)
        XCTAssertNil(defaults.object(forKey: SculptedSetting.key))
    }

    // MARK: Helpers

    private func game(_ level: MatchController.Level, _ result: SavedGame.Result) -> SavedGame {
        let base = RewindSample.game()
        return SavedGame(id: UUID(), date: .now, opponent: level.rival.name, level: level.rawValue,
                         playerIsWhite: true, result: result, accuracy: 80,
                         positions: base.positions, moves: base.moves, moments: base.moments)
    }
}
