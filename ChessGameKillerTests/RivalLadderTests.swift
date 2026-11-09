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

    func testPremiumOpensEveryRival() throws {
        let ladder = RivalLadder(beatenNames: [], allOpen: true)
        for level in MatchController.Level.allCases { XCTAssertTrue(ladder.isOpen(level)) }
        XCTAssertEqual(ladder.current, .beginner)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RivalLadderPremium"))
        defaults.removePersistentDomain(forName: "RivalLadderPremium")
        XCTAssertFalse(RivalLadder(defaults: defaults).isOpen(.grandmaster))
        defaults.set(true, forKey: Premium.activeKey)
        XCTAssertTrue(RivalLadder(defaults: defaults).isOpen(.grandmaster))
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

    /// The welcome picks the first rival from how much chess the player has played; every
    /// rival up to it is open, and the climb goes on one rival at a time from there.
    func testTheWelcomesPickOpensEveryRivalUpToIt() {
        let ladder = RivalLadder(beatenNames: [], start: .expert)
        XCTAssertTrue(ladder.isOpen(.beginner))
        XCTAssertTrue(ladder.isOpen(.casual))
        XCTAssertTrue(ladder.isOpen(.club))
        XCTAssertTrue(ladder.isOpen(.expert))
        XCTAssertFalse(ladder.isOpen(.grandmaster), "the Ashen King still waits for a win over the Lionheart")
        XCTAssertEqual(ladder.current, .expert, "the hall opens on the rival the welcome picked")

        let won = RivalLadder(beatenNames: ["the lionheart"], start: .expert)
        XCTAssertTrue(won.isOpen(.grandmaster))
        XCTAssertEqual(won.current, .grandmaster)
    }

    @MainActor
    func testTheWelcomeSavesItsPickForTheLadder() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RivalLadderStart"))
        defaults.removePersistentDomain(forName: "RivalLadderStart")
        XCTAssertFalse(RivalLadder(defaults: defaults).isOpen(.casual))

        WelcomeChoice(experience: .regular, look: .gilded).apply(defaults)
        var ladder = RivalLadder(defaults: defaults)
        XCTAssertTrue(ladder.isOpen(.club))
        XCTAssertFalse(ladder.isOpen(.expert))
        XCTAssertEqual(ladder.current, .club)
        XCTAssertEqual(NewGameSheet.savedSetup(defaults).level, .club, "the New Game sheet keeps the welcome's rival")

        // Replaying the welcome and picking less never locks a rival again.
        WelcomeChoice(experience: .new, look: .gilded).apply(defaults)
        ladder = RivalLadder(defaults: defaults)
        XCTAssertTrue(ladder.isOpen(.club))
        XCTAssertFalse(ladder.isOpen(.expert))
        defaults.removePersistentDomain(forName: "RivalLadderStart")
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
