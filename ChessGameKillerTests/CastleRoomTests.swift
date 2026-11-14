import ChessKit
import XCTest
@testable import ChessGameKiller

/// The castle's rooms behind Rooms (Alex, 2026-11-14): Trophy Hall, Famous Games, the Dungeon.
@MainActor
final class CastleRoomTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "castle-\(UUID().uuidString)"
        let made = UserDefaults(suiteName: name)!
        made.removePersistentDomain(forName: name)
        return made
    }

    // MARK: Films

    /// Each room's film plays once by itself; after that the room opens at once.
    func testAFilmIsSeenOnce() {
        let store = defaults()
        XCTAssertFalse(CastleRoom.dungeon.filmSeen(store))
        CastleRoom.dungeon.markFilmSeen(store)
        CastleRoom.dungeon.markFilmSeen(store)
        XCTAssertTrue(CastleRoom.dungeon.filmSeen(store))
        XCTAssertFalse(CastleRoom.famous.filmSeen(store))
        XCTAssertEqual(store.stringArray(forKey: CastleRoom.seenKey), ["dungeon"])
    }

    /// Every room's film and backdrop are in the app.
    func testEveryRoomHasItsFilm() {
        for room in CastleRoom.allCases {
            XCTAssertNotNil(room.filmURL, "room-\(room.slug)-film.mp4 is missing")
            XCTAssertNotNil(room.cardImage, "room-\(room.slug)-card.jpg is missing")
        }
    }

    // MARK: Famous Games

    /// Every story line sits on a move the game really has, and every classic game has a story.
    func testEveryStoryLineIsOnARealMove() {
        let games = GrandmasterContent.shared.games
        XCTAssertFalse(games.isEmpty)
        for game in games {
            let story = FamousGameStory.stories[game.id]
            XCTAssertNotNil(story, "\(game.id) has a story")
            for index in story?.moments.keys.sorted() ?? [] {
                XCTAssertTrue(game.moves.indices.contains(index), "\(game.id) line at \(index)")
            }
        }
    }

    /// The player plays the whole game by itself, and a step back lands on the move before.
    func testThePlayerStepsThroughTheGame() {
        let game = GrandmasterContent.shared.games.first { $0.id == "opera" }!
        let player = FamousGamePlayer(game: game)
        while !player.finished { player.stepForward(sound: false) }
        XCTAssertEqual(player.index, game.moves.count)
        XCTAssertEqual(player.board.moveCount, game.moves.count, "Every move was legal")
        player.stepBack()
        XCTAssertEqual(player.index, game.moves.count - 1)
        XCTAssertEqual(player.board.moveCount, game.moves.count - 1)
        player.restart()
        XCTAssertEqual(player.index, 0)
    }

    // MARK: The Dungeon

    /// The cells are the draws to hold, and the day picks one; the next day the next one.
    func testTheDayPicksTheCell() {
        let content = GrandmasterContent.shared
        let cells = DungeonCells.all(content)
        XCTAssertGreaterThan(cells.count, 3)
        XCTAssertTrue(cells.allSatisfy { $0.goal == .draw })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9))!
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let first = DungeonCells.today(day, cells: cells, calendar: calendar)
        XCTAssertEqual(first, DungeonCells.today(day.addingTimeInterval(3600), cells: cells, calendar: calendar))
        XCTAssertNotEqual(first, DungeonCells.today(next, cells: cells, calendar: calendar))
    }

    /// An escape counts once a day, and days in a row make a run.
    func testEscapesMakeARun() {
        let store = defaults()
        let study = DungeonCells.all(GrandmasterContent.shared)[0]
        let today = Date()
        XCTAssertEqual(DungeonCells.run(today, defaults: store), 0)
        DungeonCells.markEscaped(study, on: today.addingTimeInterval(-86_400), defaults: store)
        XCTAssertEqual(DungeonCells.run(today, defaults: store), 1, "Yesterday's escape still counts today")
        DungeonCells.markEscaped(study, on: today, defaults: store)
        DungeonCells.markEscaped(study, on: today, defaults: store)
        XCTAssertTrue(DungeonCells.escapedToday(today, defaults: store))
        XCTAssertEqual(DungeonCells.escapedCount(store), 2)
        XCTAssertEqual(DungeonCells.run(today, defaults: store), 2)
    }

    // MARK: Trophy Hall

    /// Wins are counted from rival games only, the best win is against the strongest rival,
    /// and the longest run of wins is found.
    func testTrophyHallReadsTheGames() {
        func game(_ result: SavedGame.Result, level: Int?, accuracy: Int?, day: Double, opponent: String = "The Cub") -> SavedGame {
            SavedGame(id: UUID(), date: Date(timeIntervalSince1970: day * 86_400), opponent: opponent, level: level,
                      playerIsWhite: true, result: result, accuracy: accuracy, positions: [], moves: [], moments: [])
        }
        let games = [
            game(.win, level: 0, accuracy: 80, day: 1),
            game(.win, level: 2, accuracy: 70, day: 2, opponent: "The Berserker"),
            game(.loss, level: 2, accuracy: 60, day: 3),
            game(.win, level: 0, accuracy: 91, day: 4),
            game(.win, level: nil, accuracy: 99, day: 5, opponent: "Friend"),
        ]
        let records = TrophyHallRecords(games: games, ladder: RivalLadder(beatenNames: ["the cub"]))
        XCTAssertEqual(records.wins, 3)
        XCTAssertEqual(records.bestAccuracy, 91)
        XCTAssertEqual(records.longestRun, 2)
        XCTAssertEqual(records.bestWins.first?.opponent, "The Berserker")
        XCTAssertEqual(records.rivals.filter { $0.beaten }.count, 1)
    }

    /// A win saved under a rival's old name hangs in the hall under today's name.
    func testABestWinWearsTheRivalsNameToday() {
        let old = SavedGame(id: UUID(), date: .now, opponent: "The 1600s", level: MatchController.Level.club.rawValue,
                            playerIsWhite: true, result: .win, accuracy: 88, positions: [], moves: [], moments: [])
        let records = TrophyHallRecords(games: [old], ladder: RivalLadder(beatenNames: ["the 1600s"]))
        XCTAssertEqual(records.bestWins.first?.opponent, "The Berserker")
    }

    /// An escape is kept under the day the cell was entered, not the day it was left.
    func testAnEscapeBelongsToTheDayItWasEntered() throws {
        let store = defaults()
        let entered = Date.now.addingTimeInterval(-86_400)
        let cell = try XCTUnwrap(DungeonCells.today(entered))
        DungeonCells.markEscaped(cell, on: entered, defaults: store)
        XCTAssertEqual(DungeonCells.escapes(store)[DungeonCells.dayKey(entered)], cell.id)
        XCTAssertFalse(DungeonCells.escapedToday(defaults: store))
    }
}
