import ChessKit
import XCTest
@testable import ChessGameKiller

/// The home's masterpiece of the day: every classic game plays its finish, and the day picks one.
final class HomeMasterpieceTests: XCTestCase {

    func testEveryClassicGamePlaysItsFinish() throws {
        let games = GrandmasterContent.shared.games
        XCTAssertFalse(games.isEmpty)
        for game in games {
            let masterpiece = try XCTUnwrap(HomeMasterpiece(game), game.id)
            XCTAssertEqual(masterpiece.moves.count, HomeMasterpiece.finish, game.id)
            XCTAssertEqual(masterpiece.frames.count, HomeMasterpiece.finish + 1, game.id)
            // The finish starts from a real position.
            XCTAssertNotNil(PositionDraft(fen: masterpiece.frames[0]), game.id)
            XCTAssertFalse(masterpiece.title.isEmpty)
            XCTAssertFalse(masterpiece.story.isEmpty)
        }
    }

    func testNamesComeFromTheBlurb() throws {
        let games = GrandmasterContent.shared.games
        let opera = try XCTUnwrap(games.first { $0.id == "opera" }.flatMap(HomeMasterpiece.init))
        XCTAssertEqual(opera.title, "The Opera Game")
        XCTAssertEqual(opera.players, "Morphy v Duke Karl & Count Isouard · 1858")
        XCTAssertTrue(opera.story.hasPrefix("Rapid development"))
        let reti = try XCTUnwrap(games.first { $0.id == "reti-tartakower" }.flatMap(HomeMasterpiece.init))
        XCTAssertEqual(reti.title, "Réti – Tartakower")
    }

    func testTheSameGameAllDayAndANewOneTomorrow() throws {
        let games = GrandmasterContent.shared.games
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 7)))
        let evening = morning.addingTimeInterval(8 * 3600)
        let tomorrow = morning.addingTimeInterval(24 * 3600)
        let first = try XCTUnwrap(HomeMasterpiece.of(morning, games: games, calendar: calendar))
        XCTAssertEqual(HomeMasterpiece.of(evening, games: games, calendar: calendar)?.game.id, first.game.id)
        XCTAssertNotEqual(HomeMasterpiece.of(tomorrow, games: games, calendar: calendar)?.game.id, first.game.id)
    }
}
