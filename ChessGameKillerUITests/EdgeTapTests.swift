import XCTest

/// The tap helper's own check.
///
/// A row counts as touchable while it sits under the status bar at the top of the screen, and a
/// tap there never reaches it: a tap test failed that way with nothing wrong in the app
/// (2026-11-27), on a tap that landed 42 points from the top. The test here parks a button there
/// on purpose, writes down what a plain tap does ("TAPNOTE": it opened nothing), and then checks
/// that the helper's tap opens the button.
///
/// The helper keeps taps out of the bottom strip as well (the Home indicator's). That one is a
/// precaution: taps 25 to 35 points from the bottom have worked, and a plain tap lower down has
/// not been checked (a test that tried it hung the test runner and was taken out).
///
/// A button that can't be parked is skipped by name, never passed quietly.
final class EdgeTapTests: TapTestCase {
    /// Under the top of the screen: Practice on a free player's Chess DNA.
    func testATapUnderTheTopEdgeStillOpens() throws {
        launch(Self.free + ["-showcaseDNA", "YES", "-showcaseOpen", "dna"])
        expectPage("Chess DNA", after: "Opening Chess DNA")
        let practice = buttons("Practice the opening rules")
        let button = practice.firstMatch
        // Its middle about 45 points from the top: under the status bar.
        guard park(button, { $0.midY }, at: 45, slack: 20) else {
            throw XCTSkip("Practice could not be parked under the top edge")
        }
        let frame = button.frame
        let counted = button.isHittable
        var opened = false
        if counted {
            button.tap()
            opened = sessionArrives(within: 20)
        }
        print("TAPNOTE Under the top edge: frame \(frame), counted as touchable: \(counted), a plain tap opened it: \(opened)")
        // Where a plain tap works there is nothing for the helper to save.
        if opened { return }

        // A tap on the status bar can send the page back to its top, so the button is parked again.
        guard park(button, { $0.midY }, at: 45, slack: 20) else {
            throw XCTSkip("Practice could not be parked under the top edge a second time")
        }
        tap(practice, "Practice from under the top edge")
        if !sessionArrives(within: 90) {
            fail("The helper's tap on a row under the top edge opened nothing")
        }
    }

    /// Waits for a training session: its intro, its lesson or its first position.
    private func sessionArrives(within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if ["End session", "Close lesson", "Skip the lesson", "Let's go"].contains(where: { buttons($0).firstMatch.exists }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return false
    }
}
