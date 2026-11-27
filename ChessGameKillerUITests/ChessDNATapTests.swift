import XCTest

/// The Chess DNA page for a Premium player with eleven finished games (`-showcaseDNA YES`):
/// the card, the two lists and the games under them.
final class ChessDNATapTests: TapTestCase {
    /// Learn opened on Chess DNA, as the Home's Chess DNA card opens it.
    private func openChessDNA() {
        launch(["-premium", "YES", "-showcaseDNA", "YES", "-showcaseOpen", "dna"])
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
        tap(buttons(containing: "See your Chess DNA"), "The Chess DNA card")
        expectPage("Your Chess DNA", after: "Tapping the Chess DNA card")
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
        expectSession(after: "Tapping Practice on the thing to work on")
    }

    /// A recent game at the foot of the page opens in Rewind.
    func testARecentGameOpens() {
        openChessDNA()
        tap(buttons(containing: "accuracy"), "A recent game")
        expectGame(after: "Tapping a recent game")
    }
}
