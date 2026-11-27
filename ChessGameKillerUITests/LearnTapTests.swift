import XCTest

/// Learn, on a player's first day: everything on the page that opens something.
final class LearnTapTests: TapTestCase {
    /// Learn as the Home's tab opens it (CI's pictures open it the same way, with `-showcaseOpen learn`).
    private func openLearn() {
        launch(["-showcaseOpen", "learn"])
        expectPage("Learn", after: "Opening Learn")
    }

    /// The Home's own Learn tab, touched.
    func testTheLearnTabOpensLearn() {
        launch()
        tap(buttons("Learn"), "The Learn tab on Home", scrolls: false)
        expectPage("Learn", after: "Tapping the Learn tab on Home")
    }

    /// The vine card opens the vine's own page, and Back comes home to Learn.
    func testTheVineOpens() {
        openLearn()
        tap(buttons(startingWith: "Your vine"), "The vine on Learn")
        expect(anything(labeled: "YOUR VINE"), "Tapping the vine on Learn did not open the vine's page")
        goBack(to: "Learn")
    }

    /// Each of the six doors opens its own page, and Back comes home to Learn.
    func testEveryDoorOpens() {
        openLearn()
        for door in ["Puzzles", "Lessons", "Openings", "Endgames", "Calculation", "Chess DNA"] {
            tap(buttons(startingWith: door + "."), "The \(door) door")
            expectPage(door, after: "Tapping the \(door) door")
            goBack(to: "Learn")
        }
    }

    /// Start on today's card opens today's session.
    func testStartOpensTodaysSession() {
        openLearn()
        let start = app.buttons.matching(NSPredicate(format: "label == 'Start' OR label == 'Train more'"))
        tap(start, "Start on today's card")
        expectSession(after: "Tapping Start on today's card")
    }
}
