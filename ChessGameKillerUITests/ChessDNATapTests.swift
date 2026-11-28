import XCTest

/// The Chess DNA page for a Premium player with eleven finished games (`-showcaseDNA YES`):
/// the card, the two lists, the games under them and the rows at the foot of the page.
final class ChessDNATapTests: TapTestCase {
    /// Learn opened on Chess DNA, as the Home's Chess DNA card opens it. `mistakes` saves the
    /// slips from those games as positions to fix (`-showcaseMistakes YES`). `full` is the same
    /// player with a strength found in their moves and a second thing to work on
    /// (`-showcaseFull YES`).
    private func openChessDNA(mistakes: Bool = false, full: Bool = false) {
        launch(Self.premium + ["-showcaseDNA", "YES", "-showcaseOpen", "dna"]
            + (mistakes ? ["-showcaseMistakes", "YES"] : []) + (full ? ["-showcaseFull", "YES"] : []))
        expectPage("Chess DNA", after: "Opening Chess DNA")
    }

    /// Skip in the corner of Chess DNA's film.
    private var skipFilm: XCUIElementQuery { buttons("Skip the film") }

    /// The first time Chess DNA opens, its film fades in over it, and Skip gives way to the page.
    func testTheFilmPlaysTheFirstTimeChessDNAOpens() {
        launch(["-dnaFilmSeen", "NO"])
        tap(buttons("Learn"), "The Learn tab on Home", scrolls: false)
        expectPage("Learn", after: "Tapping the Learn tab on Home")
        tap(buttons(startingWith: "Chess DNA."), "The Chess DNA door")
        expectTouchable(skipFilm, "Chess DNA's film did not play the first time Chess DNA opened")
        tap(skipFilm, "Skip on Chess DNA's film", scrolls: false)
        expectPage("Chess DNA", after: "Skipping Chess DNA's film")
        if !leaves(skipFilm.firstMatch) { fail("Chess DNA's film stayed after Skip") }
    }

    /// A player who has seen the film opens Chess DNA without it; Watch the film plays it again,
    /// and Skip comes back to the page.
    func testWatchTheFilmPlaysItAgain() {
        openChessDNA()
        if skipFilm.firstMatch.exists { fail("Chess DNA's film played for a player who has seen it") }
        tap(buttons("Watch the film"), "Watch the film on Chess DNA", scrolls: false)
        expectTouchable(skipFilm, "Watch the film on Chess DNA did not play the film")
        tap(skipFilm, "Skip on Chess DNA's film", scrolls: false)
        expectPage("Chess DNA", after: "Skipping Chess DNA's film")
    }

    /// Back from Chess DNA is Learn, and the vine opens from there as well.
    func testBackFromChessDNAIsLearn() {
        openChessDNA()
        goBack(to: "Learn")
        openVine()
    }

    /// The card on top opens the whole profile.
    func testTheCardOpensYourChessDNA() {
        openChessDNA()
        note("Chess DNA, eleven games")
        tap(buttons(containing: "See your Chess DNA"), "The Chess DNA card")
        expectPage("Your Chess DNA", after: "Tapping the Chess DNA card")
        note("Your Chess DNA")
    }

    /// An opening under "Learn next" on the whole profile opens that opening's page.
    func testLearnNextOpensItsOpening() throws {
        openChessDNA()
        tap(buttons(containing: "See your Chess DNA"), "The Chess DNA card")
        expectPage("Your Chess DNA", after: "Tapping the Chess DNA card")
        // "Italian Game · White" at the start of each row.
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · White, ' OR label CONTAINS ' · Black, '"))
        guard pick.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("The sample player has nothing under Learn next")
        }
        tap(pick, "An opening under Learn next")
        if !leaves(bar("Your Chess DNA")) {
            fail("Tapping an opening under Learn next did not open it")
        }
        tap(buttons("Learn"), "Learn on the opening's page")
        expectTouchable(buttons("Test me"), "Tapping Learn left the opening's page")
        goBack(to: "Your Chess DNA")
    }

    /// "See them" on a strength shows the games it came from, and one of those opens.
    func testAStrengthShowsItsGames() {
        openChessDNA()
        tap(buttons(containing: "See them"), "See them on a strength")
        if !leaves(bar("Chess DNA")) {
            fail("Tapping See them on a strength did not open its games")
        }
        // "Win · 2 days ago" under the rival's name.
        tap(buttons(containing: " · "), "A game on the strength's page")
        expectGame(after: "Tapping a game on the strength's page")
    }

    /// A strength found in the player's moves (Forks) shows where, "Sharpen it" under them
    /// starts puzzles of that kind, and one of the moves opens its game.
    func testAStrengthInTheMovesSharpensAndShowsTheMove() {
        openChessDNA(full: true)
        note("Chess DNA, the fuller player")
        tap(buttons(startingWith: "Forks"), "See them on Forks")
        expectPage("Forks", after: "Tapping See them on Forks")
        let sharpen = buttons("Sharpen it")
        tap(sharpen, "Sharpen it under the forks")
        expectSession(after: "Tapping Sharpen it under the forks", patience: 90)
        endSession(backTo: sharpen, "the puzzles")

        // "Move 6 · Win · 2 days ago" under the rival's name.
        tap(buttons(containing: " · "), "A fork on the strength's page")
        expectGame(after: "Tapping a fork on the strength's page")
    }

    /// "Sharpen" on a strength starts puzzles of that kind.
    func testSharpenStartsPuzzles() {
        openChessDNA()
        tap(buttons(containing: "Sharpen"), "Sharpen on a strength")
        // The puzzles behind it are a pack of 115,000, and an unoptimized build reads it slowly.
        expectSession(after: "Tapping Sharpen on a strength", patience: 90)
    }

    /// The button on the first thing to work on starts practice.
    func testWorkOnThisStartsPractice() {
        openChessDNA()
        tap(buttons(startingWith: "Practice "), "Practice on the thing to work on")
        expectSession(after: "Tapping Practice on the thing to work on", patience: 90)
    }

    /// "Train" on a thing to work on in the middlegame opens Calculation, and Back comes home.
    func testTrainOpensItsRoom() {
        openChessDNA(full: true)
        tap(buttons("Train calculation"), "Train on the middlegame to work on")
        expectPage("Calculation", after: "Tapping Train on the middlegame to work on")
        goBack(to: "Chess DNA")
    }

    /// With positions saved from the player's games: the button on the thing to work on starts
    /// with them, and "Fix your mistakes" further down starts them too.
    func testSavedPositionsStartPractice() {
        openChessDNA(mistakes: true)
        note("Chess DNA, with saved positions")
        let practice = buttons(startingWith: "Practice ")
        tap(practice, "Practice on the thing to work on")
        expectSession(after: "Tapping Practice on the thing to work on, with positions saved", patience: 90)
        endSession(backTo: practice, "the practice")

        tap(buttons(startingWith: "Fix your mistakes"), "Fix your mistakes")
        expectSession(after: "Tapping Fix your mistakes")
    }

    /// A recent game at the foot of the page opens in Rewind.
    func testARecentGameOpens() {
        openChessDNA()
        tap(buttons(containing: "accuracy"), "A recent game")
        expectGame(after: "Tapping a recent game")
    }

    /// "All 11 games" opens the list of every game, and Done comes back.
    func testAllGamesOpensTheList() {
        openChessDNA()
        let all = buttons(startingWith: "All ")
        tap(all, "All games under the recent ones")
        expectPage("Your games", after: "Tapping All games")
        close(buttons("Done"), backTo: all, "the list of games")
    }

    /// The row for games played online opens the page that brings them in, and Back comes home.
    func testBringingInOnlineGamesOpens() {
        openChessDNA()
        tap(buttons(startingWith: "Bring in your online games"), "Bring in your online games")
        expectPage("Your online games", after: "Tapping Bring in your online games")
        goBack(to: "Chess DNA")
    }
}

/// The same page for a player without Premium: the card is the card alone, the first thing to
/// work on is free, and the rest is behind the Premium offer.
final class ChessDNAFreeTapTests: TapTestCase {
    /// "See Premium" opens the Premium offer, and the one free thing to work on starts practice.
    func testAFreePlayerIsOfferedPremiumAndCanPractice() {
        launch(Self.free + ["-showcaseDNA", "YES", "-showcaseOpen", "dna"])
        expectPage("Chess DNA", after: "Opening Chess DNA")
        note("Chess DNA, free player")
        let seePremium = buttons("See Premium")
        tap(seePremium, "See Premium on Chess DNA")
        expectPremiumOffer(after: "Tapping See Premium on Chess DNA")
        close(buttons("Close"), backTo: seePremium, "the Premium offer")

        let practice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Practice ' OR label BEGINSWITH 'Train '"))
        tap(practice, "The button on the thing to work on first")
        let deadline = Date().addingTimeInterval(90)
        repeat {
            let session = ["End session", "Close lesson", "Skip the lesson", "Let's go"].contains { buttons($0).firstMatch.exists }
            if session || bar("Endgames").exists || bar("Calculation").exists { return }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        fail("Tapping the button on the thing to work on first opened nothing")
    }
}
