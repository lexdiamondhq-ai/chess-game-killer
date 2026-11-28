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
