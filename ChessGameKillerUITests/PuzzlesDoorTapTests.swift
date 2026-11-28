import XCTest

/// Behind Learn's Puzzles door: each way to play opens its own screen and closes back to the door.
final class PuzzlesDoorTapTests: TapTestCase {
    /// Play opens rated puzzles, and Puzzle Rush opens the Rush.
    func testPlayAndRushOpen() {
        openDoor("Puzzles", Self.premium)
        let closePuzzles = buttons("Close puzzles")

        let play = buttons("Play")
        tap(play, "Play on rated puzzles")
        expectTouchable(closePuzzles, "Tapping Play on rated puzzles did not open the puzzles")
        close(closePuzzles, backTo: play, "the puzzles")

        let rush = buttons(startingWith: "Puzzle Rush")
        tap(rush, "Puzzle Rush")
        expectTouchable(closePuzzles, "Tapping Puzzle Rush did not open the Rush")
        expect(texts("Puzzle Rush").firstMatch, "Tapping Puzzle Rush opened something other than the Rush")
        close(closePuzzles, backTo: rush, "the Rush")
    }

    /// Blunder Shield opens for a free player, a move card can be picked, and Close comes back.
    func testBlunderShieldOpensAndAPickCounts() {
        openDoor("Puzzles", Self.free)
        let row = buttons(startingWith: "Blunder Shield")
        tap(row, "Blunder Shield")
        expectRoom("Blunder Shield", after: "Tapping Blunder Shield")
        // The engine finds the first position; then the two move cards are up and the ring runs.
        let card = buttons("Shield move")
        expectTouchable(card, "Blunder Shield never put its two move cards up")
        tap(card, "A Blunder Shield move card", scrolls: false)
        expectTouchable(buttons("Next position"), "Picking a Blunder Shield move did not reveal the answer")
        let timedOut = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Time's up")).firstMatch
        if timedOut.exists { fail("The pick on a Blunder Shield card did not count: the ring ran out instead") }
        close(buttons("Close"), backTo: row, "Blunder Shield")
    }

    /// With Premium, Cycles and Review open their rooms.
    func testCyclesAndReviewOpenWithPremium() {
        openDoor("Puzzles", Self.premium)
        for room in ["Cycles", "Review"] {
            let row = buttons(startingWith: room)
            tap(row, room)
            expectRoom(room, after: "Tapping \(room)")
            close(buttons("Close"), backTo: row, room)
        }
    }

    /// Without Premium, Cycles and Review show the Premium offer, and Close comes back.
    func testCyclesAndReviewOfferPremium() {
        openDoor("Puzzles", Self.free)
        for room in ["Cycles", "Review"] {
            let row = buttons(startingWith: room)
            tap(row, room)
            expectPremiumOffer(after: "Tapping \(room) as a free player")
            close(buttons("Close"), backTo: row, "the Premium offer")
        }
    }
}
