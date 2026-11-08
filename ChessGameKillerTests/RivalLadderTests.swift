import XCTest
@testable import ChessGameKiller

/// The rivals' hall: the Cub is always open, every other rival opens only once the rival before
/// it is beaten, and every rival has its film's media.
final class RivalLadderTests: XCTestCase {
    func testNewPlayerFacesOnlyTheCub() {
        let ladder = RivalLadder(beatenNames: [])
        XCTAssertTrue(ladder.isOpen(.beginner))
        XCTAssertFalse(ladder.isOpen(.casual))
        XCTAssertFalse(ladder.isOpen(.club))
        XCTAssertFalse(ladder.isOpen(.expert))
        XCTAssertFalse(ladder.isOpen(.grandmaster))
        XCTAssertEqual(ladder.current, .beginner)
    }

    func testBeatingTheCubOpensTheHunterOnly() {
        let ladder = RivalLadder(beatenNames: ["the cub"])
        XCTAssertTrue(ladder.isOpen(.casual))
        XCTAssertFalse(ladder.isOpen(.club))
        XCTAssertEqual(ladder.current, .casual)
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

    func testAWinOverTheLionheartUnderAnyNameOpensTheAshenKing() {
        XCTAssertTrue(RivalLadder(beatenNames: ["the lionheart"]).isOpen(.grandmaster))
        XCTAssertTrue(RivalLadder(beatenNames: ["the dragonlord"]).beaten(MatchController.Level.grandmaster.rival))
    }

    func testTheHallOpensOnTheFirstRivalNotYetBeaten() {
        let ladder = RivalLadder(beatenNames: ["the cub", "the hunter"])
        XCTAssertEqual(ladder.current, .club)
    }

    func testEachRivalsIntroIsRememberedOnceSeen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RivalIntrosTests"))
        defaults.removePersistentDomain(forName: "RivalIntrosTests")
        XCTAssertFalse(RivalIntros.seen(.casual, defaults: defaults))
        RivalIntros.mark(.casual, defaults: defaults)
        RivalIntros.mark(.casual, defaults: defaults)
        XCTAssertTrue(RivalIntros.seen(.casual, defaults: defaults))
        XCTAssertFalse(RivalIntros.seen(.club, defaults: defaults))
        XCTAssertEqual(defaults.stringArray(forKey: RivalIntros.key), ["1200s"])
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
