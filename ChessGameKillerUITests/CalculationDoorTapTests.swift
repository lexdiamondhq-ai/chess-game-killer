import XCTest

/// Behind Learn's Calculation door: each of its five rooms.
final class CalculationDoorTapTests: TapTestCase {
    /// Opens each room by its row, checks its name at the top, and closes it.
    private func openAndClose(_ rooms: [String]) {
        for room in rooms {
            let row = buttons(startingWith: room)
            tap(row, room)
            expectRoom(room, after: "Tapping \(room)")
            close(buttons("Close"), backTo: row, room)
        }
    }

    /// Candidate moves and See ahead open their rooms.
    func testInYourHeadRoomsOpen() {
        openDoor("Calculation", Self.premium)
        openAndClose(["Candidate moves", "See ahead"])
    }

    /// Board scan and Coordinates open their rooms.
    func testBoardVisionRoomsOpen() {
        openDoor("Calculation", Self.premium)
        openAndClose(["Board scan", "Coordinates"])
    }

    /// Guess the Move lists its games, and one of them opens.
    func testGuessTheMoveOpensAGame() {
        openDoor("Calculation", Self.premium)
        tap(buttons(startingWith: "Guess the Move"), "Guess the Move")
        expectPage("Guess the Move", after: "Tapping Guess the Move")
        // "Italian Game · as White" under each game's name.
        let game = buttons(containing: " · as ")
        tap(game, "A game to guess")
        expectRoom(after: "Tapping a game to guess")
        close(buttons("Close"), backTo: game, "the game")
        goBack(to: "Calculation")
    }

    /// Without Premium, Candidate moves and Guess the Move show the Premium offer.
    func testPremiumRoomsOfferPremium() {
        openDoor("Calculation", Self.free)
        for room in ["Candidate moves", "Guess the Move"] {
            let row = buttons(startingWith: room)
            tap(row, room)
            expectPremiumOffer(after: "Tapping \(room) as a free player")
            close(buttons("Close"), backTo: row, "the Premium offer")
        }
    }
}
