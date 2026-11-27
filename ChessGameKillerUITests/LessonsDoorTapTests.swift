import XCTest

/// Behind Learn's Lessons door, on a player's first day: the Traffic Light, the open unit's
/// lessons and practice, and a lesson that is Premium's.
final class LessonsDoorTapTests: TapTestCase {
    private var closeLesson: XCUIElementQuery { buttons("Close lesson") }

    /// The Traffic Light unfolds, and its Watch button plays the first lesson.
    func testTheTrafficLightPlaysItsLesson() {
        openDoor("Lessons")
        tap(buttons(startingWith: "The Traffic Light"), "The Traffic Light")
        let watch = buttons(startingWith: "Watch: ")
        tap(watch, "Watch under the Traffic Light")
        expectTouchable(closeLesson, "Tapping Watch under the Traffic Light did not open the lesson")
        close(closeLesson, backTo: watch, "the lesson")
    }

    /// A lesson in the open unit opens, and Practice on its skill starts a session.
    func testALessonOpensAndPracticeStarts() {
        openDoor("Lessons", Self.premium)
        let lesson = buttons(containing: ", lesson")
        tap(lesson, "A lesson in the open unit")
        expectTouchable(closeLesson, "Tapping a lesson did not open it")
        close(closeLesson, backTo: lesson, "the lesson")

        tapPractice()
        expectSession(after: "Tapping Practice on a skill")
        endSession(backTo: lesson, "the practice")
    }

    /// A free player who taps a Premium lesson gets the Premium offer, and Close comes back.
    func testAPremiumLessonOffersPremium() {
        openDoor("Lessons", Self.free)
        tap(buttons(startingWith: "Checkmate Patterns"), "The Checkmate Patterns unit")
        let locked = buttons(startingWith: "Checkmate in One, lesson")
        tap(locked, "A Premium lesson")
        expectPremiumOffer(after: "Tapping a Premium lesson as a free player")
        close(buttons("Close"), backTo: locked, "the Premium offer")
    }

    /// Practice on the first unit's skill. The skill's row is one element to assistive tech, so
    /// when the button isn't there by itself the finger goes where it is drawn: the row's right end.
    private func tapPractice() {
        if let alone = waitTouchable(buttons("Practice"), patience: 4) {
            alone.tap()
            return
        }
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Good captures' AND label CONTAINS 'Practice'"))
        tap(rows, "Practice on a skill", at: CGVector(dx: 0.88, dy: 0.5))
    }
}
