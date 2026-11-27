import XCTest

/// Behind Learn's Endgames door: the next endgame, and one picked from the list.
final class EndgamesDoorTapTests: TapTestCase {
    /// Play opens the next endgame, and a row in the list opens that one. Close comes back each time.
    func testPlayAndARowOpenAnEndgame() {
        openDoor("Endgames", Self.premium)
        let play = buttons("Play")
        tap(play, "Play on the next endgame")
        expectRoom(after: "Tapping Play on the next endgame")
        close(buttons("Close"), backTo: play, "the endgame")

        // "White to play and win" in each row's words.
        let row = buttons(containing: " to play and ")
        tap(row, "An endgame in the list")
        expectRoom(after: "Tapping an endgame in the list")
        close(buttons("Close"), backTo: row, "the endgame")
    }
}
