import XCTest

/// Learn, on a player's first day: everything on the page that opens something.
final class LearnTapTests: TapTestCase {
    /// Start on today's card, whichever of its two names it has.
    private var start: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == 'Start' OR label == 'Train more'"))
    }

    /// The menu behind the three dots at the top of Learn.
    private var settings: XCUIElementQuery { anythings("Training settings") }

    /// Skip in the corner of Learn's film.
    private var skipFilm: XCUIElementQuery { buttons("Skip the film") }

    /// The first time Learn opens, its film plays over it, and Skip gives way to Learn.
    func testTheFilmPlaysTheFirstTimeLearnOpens() {
        launch(["-learnFilmSeen", "NO"])
        tap(buttons("Learn"), "The Learn tab on Home", scrolls: false)
        expectTouchable(skipFilm, "Learn's film did not play the first time Learn opened")
        if touchable(vineCard) != nil { fail("Learn can be touched through its film") }
        tap(skipFilm, "Skip on Learn's film", scrolls: false)
        expectPage("Learn", after: "Skipping Learn's film")
        expectTouchable(vineCard, "Skipping Learn's film did not leave Learn under a finger")
        if !leaves(skipFilm.firstMatch) { fail("Learn's film stayed after Skip") }
    }

    /// A player who has seen the film opens Learn without it; "Watch the film" in the menu plays
    /// it again, and Skip comes back to Learn.
    func testWatchTheFilmPlaysItAgain() {
        openLearn()
        expectTouchable(vineCard, "Learn did not open on its own page")
        if skipFilm.firstMatch.exists { fail("Learn's film played for a player who has seen it") }
        tap(settings, "The menu at the top of Learn", scrolls: false)
        tap(buttons("Watch the film"), "Watch the film in the menu", scrolls: false)
        expectTouchable(skipFilm, "Watch the film in the menu did not play the film")
        close(skipFilm, backTo: vineCard, "Learn's film")
    }

    /// The Home's own Learn tab, touched.
    func testTheLearnTabOpensLearn() {
        launch()
        tap(buttons("Learn"), "The Learn tab on Home", scrolls: false)
        expectPage("Learn", after: "Tapping the Learn tab on Home")
    }

    /// Done on Learn goes back to the Home, with its Learn tab under a finger again.
    func testDoneGoesBackHome() {
        openLearn()
        tap(buttons("Done"), "Done on Learn", scrolls: false)
        expectTouchable(buttons("Learn"), "Done on Learn did not go back to the Home")
    }

    /// The vine card opens the vine's own page, and Back comes home to Learn.
    func testTheVineOpens() {
        openLearn()
        openVine()
        note("The vine's page")
        goBack(to: "Learn")
        expectTouchable(vineCard, "Back from the vine's page did not come home to Learn")
    }

    /// Under the vine, a free player's "See Premium" opens the Premium offer, and Close comes back.
    func testTheVinePageOffersPremium() {
        openLearn(Self.free)
        openVine()
        let seePremium = buttons("See Premium")
        tap(seePremium, "See Premium under the vine")
        expectPremiumOffer(after: "Tapping See Premium under the vine")
        close(buttons("Close"), backTo: seePremium, "the Premium offer")
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
        tap(start, "Start on today's card")
        expectSession(after: "Tapping Start on today's card")
    }

    /// The coach's portrait opens a menu, and picking the other coach changes the coach. Then back again.
    func testTheCoachMenuSwitchesCoach() {
        openLearn()
        let leo = anythings("Your coach: Coach Leo")
        let vera = anythings("Your coach: Coach Vera")
        let startsWithLeo = waitTouchable(leo, patience: 10) != nil
        for toVera in [startsWithLeo, !startsWithLeo] {
            tap(toVera ? leo : vera, "The coach's portrait on Learn", scrolls: false)
            tap(buttons(toVera ? "Coach Vera" : "Coach Leo"), "The other coach in the menu", scrolls: false)
            expectTouchable(toVera ? vera : leo, "Picking the other coach in the menu did not change the coach")
        }
    }

    /// "Find my level" opens the level check from the menu, and from the line under Start while
    /// the player is new. Skip comes back to Learn both times.
    func testFindMyLevelOpensTheLevelCheck() {
        openLearn()
        let skip = buttons("Skip")
        tap(settings, "The menu at the top of Learn", scrolls: false)
        tap(buttons(startingWith: "Find my level"), "Find my level in the menu", scrolls: false)
        expectTouchable(skip, "Find my level in the menu did not open the level check")
        close(skip, backTo: settings, "the level check")

        let line = buttons(startingWith: "Already a strong player?")
        tap(line, "The level check line under Start")
        expectTouchable(skip, "The level check line under Start did not open the level check")
        close(skip, backTo: line, "the level check")
    }

    /// "Start training over" asks first, and erasing leaves Learn with today's session ready.
    func testStartTrainingOverAsksFirst() {
        openLearn()
        tap(settings, "The menu at the top of Learn", scrolls: false)
        tap(buttons("Start training over"), "Start training over in the menu", scrolls: false)
        tap(buttons("Erase training progress"), "Erase training progress, when asked", scrolls: false)
        expectTouchable(start, "Erasing training progress left Learn without a Start")
    }
}
