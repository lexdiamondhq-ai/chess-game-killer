import XCTest
@testable import ChessGameKiller

/// The rivals' hall: the first three rivals are always open, the Lionheart and the Dragonlord
/// open only once the rival before them is beaten, and every rival has its film's media.
final class RivalLadderTests: XCTestCase {
    func testNewPlayerFacesTheFirstThree() {
        let ladder = RivalLadder(beatenNames: [])
        XCTAssertTrue(ladder.isOpen(.beginner))
        XCTAssertTrue(ladder.isOpen(.casual))
        XCTAssertTrue(ladder.isOpen(.club))
        XCTAssertFalse(ladder.isOpen(.expert))
        XCTAssertFalse(ladder.isOpen(.grandmaster))
        XCTAssertEqual(ladder.current, .beginner)
    }

    func testBeatingTheBerserkerOpensTheLionheart() {
        let ladder = RivalLadder(beatenNames: ["the berserker"])
        XCTAssertTrue(ladder.isOpen(.expert))
        XCTAssertFalse(ladder.isOpen(.grandmaster))
    }

    func testAWinUnderTheFormerNameCounts() {
        let ladder = RivalLadder(beatenNames: ["the 1600s", "the 2000s"])
        XCTAssertTrue(ladder.isOpen(.expert))
        XCTAssertTrue(ladder.isOpen(.grandmaster))
    }

    func testTheHallOpensOnTheFirstRivalNotYetBeaten() {
        let ladder = RivalLadder(beatenNames: ["the cub", "the hunter"])
        XCTAssertEqual(ladder.current, .club)
    }

    func testEveryRivalHasItsFilmCardAndTheme() {
        for film in RivalFilm.all {
            XCTAssertNotNil(film.filmURL, "\(film.rival.name) film")
            XCTAssertNotNil(film.themeURL, "\(film.rival.name) theme")
            XCTAssertNotNil(film.cardImage, "\(film.rival.name) card")
            XCTAssertLessThan(film.beat, 8)
        }
        XCTAssertNil(RivalFilm.of(.beginner).previous)
        XCTAssertEqual(RivalFilm.of(.grandmaster).previous?.name, "The Lionheart")
    }
}
