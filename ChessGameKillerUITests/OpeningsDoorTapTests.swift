import XCTest

/// Behind Learn's Openings door: an opening down to one of its lines, and every opening.
final class OpeningsDoorTapTests: TapTestCase {
    /// An opening shows its lines, a line opens, Learn plays on its page, and Back comes all the
    /// way home. With Premium, "Every opening" opens the whole list.
    func testAnOpeningOpensDownToItsLine() {
        openDoor("Openings", Self.premium)
        tap(buttons(startingWith: "Italian Game"), "The Italian Game")
        expectPage("Italian Game", after: "Tapping the Italian Game")
        // "C50 · 1. e4 e5 …" under each line's name.
        tap(buttons(containing: " · "), "A line of the Italian Game")
        if !leaves(bar("Italian Game")) {
            fail("Tapping a line of the Italian Game did not open it")
        }
        tap(buttons("Learn"), "Learn on the line's page")
        expectTouchable(buttons("Test me"), "Tapping Learn left the line's page")
        goBack(to: "Italian Game")
        goBack(to: "Openings")

        tap(buttons(startingWith: "Every opening"), "Every opening")
        expectPage("Every opening", after: "Tapping Every opening")
        goBack(to: "Openings")
    }

    /// Without Premium, "Every opening" shows the Premium offer, and Close comes back.
    func testEveryOpeningOffersPremium() {
        openDoor("Openings", Self.free)
        let every = buttons(startingWith: "Every opening")
        tap(every, "Every opening")
        expectPremiumOffer(after: "Tapping Every opening as a free player")
        close(buttons("Close"), backTo: every, "the Premium offer")
    }
}
