import XCTest

/// The tap helper's own checks.
///
/// A row counts as touchable while it sits under the status bar at the top of the screen, or over
/// the Home indicator at the bottom, and a tap there may never reach it. Two tap tests failed
/// once each with nothing wrong in the app (2026-11-27), one of them on a tap that landed 42
/// points from the top. Each test here parks a row in one of those strips on purpose, writes down
/// what a plain tap does there ("TAPNOTE"), and then checks that the helper's tap opens the row.
///
/// A row that can't be parked is skipped by name, never passed quietly.
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

    /// Over the Home indicator: "Every opening" for a free player, behind the Openings door.
    func testATapOverTheBottomEdgeStillOpens() throws {
        openDoor("Openings", Self.free)
        let every = buttons(startingWith: "Every opening")
        let row = every.firstMatch
        // Only its top 30 points on the screen: what shows is in the Home indicator's strip.
        let sliver = screenHeight - 30
        guard park(row, { $0.minY }, at: sliver, slack: 12) else {
            throw XCTSkip("Every opening could not be parked over the bottom edge")
        }
        let frame = row.frame
        let counted = row.isHittable
        var opened = false
        if counted {
            row.tap()
            opened = waitTouchable(buttons("Close"), patience: 12) != nil
        }
        print("TAPNOTE Over the bottom edge: frame \(frame), counted as touchable: \(counted), a plain tap opened it: \(opened)")
        if opened {
            close(buttons("Close"), backTo: every, "the Premium offer")
            return
        }

        guard park(row, { $0.minY }, at: sliver, slack: 12) else {
            throw XCTSkip("Every opening could not be parked over the bottom edge a second time")
        }
        tap(every, "Every opening from over the bottom edge")
        expectPremiumOffer(after: "The helper's tap on a row over the bottom edge")
        close(buttons("Close"), backTo: every, "the Premium offer")
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
