import XCTest

/// Home's music, "The Long Winter", rests under a screen opened over Home and comes back with
/// Home. Alex heard nothing after Today's training (2026-11-28): the lesson handed the sound back
/// just after Home had started its music again, and the music stayed quiet.
///
/// A test can't listen, so the app is launched with `-musicProbe YES`: Home then carries a
/// hidden line that says whether the track is really moving on ("Home music playing").
final class HomeMusicTapTests: TapTestCase {
    private var probe: XCUIElement { app.staticTexts["homeMusicProbe"] }

    /// Today's training on Home: the coach's card under For today.
    private var todaysTraining: XCUIElementQuery { buttons(startingWith: "Coach ") }

    /// Fails unless Home says its music is going, within a few seconds.
    private func expectMusic(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        expect(probe, "Home's music line did not appear", file: file, line: line)
        let deadline = Date().addingTimeInterval(12)
        repeat {
            if probe.label == "Home music playing" { return }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        fail("Home's music was quiet \(when) (\(probe.label))", file: file, line: line)
    }

    private func launchHome() {
        launch(["-musicProbe", "YES"])
        expectTouchable(buttons("Learn"), "The app did not open on Home")
        expectMusic("when the app opened")
    }

    /// Home, then Today's training, then back: the music plays again.
    func testMusicComesBackAfterTodaysTraining() {
        launchHome()
        tap(todaysTraining, "Today's training on Home")
        expectSession(after: "Tapping Today's training on Home")
        // Long enough for Leo to start the lesson, which takes the sound.
        Thread.sleep(forTimeInterval: 3)
        endSession(backTo: buttons("Learn"), "Today's training")
        expectMusic("after coming back from Today's training")
    }

    /// Home, then Learn, then Done: the music plays again.
    func testMusicComesBackAfterLearn() {
        launchHome()
        tap(buttons("Learn"), "The Learn tab on Home", scrolls: false)
        expectPage("Learn", after: "Tapping the Learn tab on Home")
        tap(buttons("Done"), "Done on Learn", scrolls: false)
        expectTouchable(buttons("Learn"), "Done on Learn did not go back to Home")
        expectMusic("after coming back from Learn")
    }
}
