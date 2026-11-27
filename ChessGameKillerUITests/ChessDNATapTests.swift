import XCTest

/// The Chess DNA page for a Premium player with eleven finished games (`-showcaseDNA YES`):
/// the card, the two lists, the games under them and the rows at the foot of the page.
final class ChessDNATapTests: TapTestCase {
    /// Learn opened on Chess DNA, as the Home's Chess DNA card opens it. `mistakes` saves the
    /// slips from those games as positions to fix (`-showcaseMistakes YES`).
    private func openChessDNA(mistakes: Bool = false) {
        launch(Self.premium + ["-showcaseDNA", "YES", "-showcaseOpen", "dna"] + (mistakes ? ["-showcaseMistakes", "YES"] : []))
        expectPage("Chess DNA", after: "Opening Chess DNA")
    }

    /// Back from Chess DNA is Learn, and the vine opens from there as well.
    func testBackFromChessDNAIsLearn() {
        openChessDNA()
        goBack(to: "Learn")
        tap(buttons(startingWith: "Your vine"), "The vine on Learn")
        expect(anything(labeled: "YOUR VINE"), "Tapping the vine on Learn did not open the vine's page")
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

    /// "Sharpen it" under a strength's games starts puzzles of that kind.
    func testSharpenItUnderAStrengthsGamesStartsPuzzles() throws {
        openChessDNA()
        tap(buttons(containing: "See them"), "See them on a strength")
        if !leaves(bar("Chess DNA")) {
            fail("Tapping See them on a strength did not open its games")
        }
        let sharpen = buttons("Sharpen it")
        guard sharpen.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("The sample player's first strength with games has no puzzles of its kind")
        }
        tap(sharpen, "Sharpen it under a strength's games")
        expectSession(after: "Tapping Sharpen it under a strength's games", patience: 90)
        endSession(backTo: sharpen, "the puzzles")
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

    /// "Train" on a thing to work on opens the room where that work is done, and Back comes home.
    func testTrainOpensItsRoom() throws {
        openChessDNA()
        let calculation = buttons("Train calculation")
        let endgames = buttons("Train endgames")
        let toCalculation = calculation.firstMatch.waitForExistence(timeout: 5)
        guard toCalculation || endgames.firstMatch.exists else {
            throw XCTSkip("The sample player has nothing to train in Endgames or Calculation")
        }
        tap(toCalculation ? calculation : endgames, "Train on a thing to work on")
        expectPage(toCalculation ? "Calculation" : "Endgames", after: "Tapping Train on a thing to work on")
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
