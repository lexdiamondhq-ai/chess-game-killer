import XCTest

/// Real taps on the real app, on the simulator.
///
/// The unit tests draw every screen and check its numbers, but a picture can't tell whether a
/// tap opens anything: the vine on Learn was drawn right and did nothing when touched, from the
/// day it was built until it was tried on a phone (2026-11-27). These tests launch the app, tap
/// what a player taps, and fail unless the next screen arrives.
///
/// A failure says what was on the screen at that moment, so the log alone explains it.
class TapTestCase: XCTestCase {
    private(set) var app = XCUIApplication()

    /// How long a screen has to arrive. CI's simulator is slow, and a screen that never comes is the failure.
    static let patience: TimeInterval = 30

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Starts the app as a returning player: no welcome, no intro film, no tips.
    func launch(_ arguments: [String] = []) {
        let fresh = XCUIApplication()
        fresh.launchArguments = ["-welcomeSeen", "YES", "-introFilmSeen", "YES", "-tipsOff", "YES"] + arguments
        fresh.launch()
        app = fresh
    }

    // MARK: Finding

    // The Home stays in the accessibility tree under a screen opened over it, so a search can
    // match one of its buttons as well ("Sharpen your eye" under Chess DNA's "Sharpen"). Each
    // search is a query, and a tap goes to the first match that can really be touched.

    /// Buttons with exactly this label.
    func buttons(_ label: String) -> XCUIElementQuery {
        app.buttons.matching(Self.named(label))
    }

    /// Buttons whose label starts with these words.
    func buttons(startingWith words: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", words))
    }

    /// Buttons whose label ends with these words.
    func buttons(endingWith words: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", words))
    }

    /// Buttons with these words anywhere in their label.
    func buttons(containing words: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", words))
    }

    /// The navigation bar of the page with this title.
    func bar(_ title: String) -> XCUIElement {
        app.navigationBars.matching(Self.named(title)).firstMatch
    }

    /// Anything with exactly this label, whatever kind of element SwiftUI made it.
    func anything(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// By label or by identifier: a navigation bar carries its title as its identifier.
    private static func named(_ name: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR identifier == %@", name, name)
    }

    // MARK: Tapping

    /// Scrolls the page until one of the matches can be touched, then touches it.
    /// `scrolls` off waits for it where it is (the Home's own bar never needs a scroll).
    func tap(_ matches: XCUIElementQuery, _ name: String, scrolls: Bool = true,
             file: StaticString = #filePath, line: UInt = #line) {
        // A screen that is still arriving gets a moment before anything is dragged.
        let settled = Date().addingTimeInterval(scrolls ? 1.5 : Self.patience)
        var found = touchable(matches)
        while found == nil, Date() < settled {
            Thread.sleep(forTimeInterval: 0.3)
            found = touchable(matches)
        }
        if scrolls {
            // Further down the page first (rows in a lazy grid don't exist until they are near), then back up.
            var moves = 0
            while found == nil, moves < 8 {
                drag(from: 0.78, to: 0.30)
                moves += 1
                found = touchable(matches)
            }
            while found == nil, moves < 16 {
                drag(from: 0.30, to: 0.78)
                moves += 1
                found = touchable(matches)
            }
        }
        guard let found else {
            fail("\(name) can't be touched", file: file, line: line)
            return
        }
        found.tap()
    }

    /// The first match a finger could reach: on the screen, with nothing over it.
    private func touchable(_ matches: XCUIElementQuery) -> XCUIElement? {
        matches.allElementsBoundByIndex.first { $0.isHittable }
    }

    /// A slow drag up or down the middle of the screen, so the page scrolls without a fling.
    /// Under half a screen at a time, so nothing is carried past unseen.
    private func drag(from start: CGFloat, to end: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Back up the navigation stack, to the page with this title.
    func goBack(to title: String, file: StaticString = #filePath, line: UInt = #line) {
        let buttons = app.navigationBars.buttons
        let named = buttons.matching(Self.named(title)).firstMatch
        if named.waitForExistence(timeout: 5) {
            named.tap()
        } else if buttons.matching(Self.named("BackButton")).firstMatch.exists {
            buttons.matching(Self.named("BackButton")).firstMatch.tap()
        } else if buttons.firstMatch.exists {
            buttons.firstMatch.tap()
        } else {
            fail("There is no back button to \(title)", file: file, line: line)
        }
        expectPage(title, after: "Going back", file: file, line: line)
    }

    // MARK: Expecting

    /// Fails unless the page with this title in its navigation bar arrives.
    func expectPage(_ title: String, after action: String, file: StaticString = #filePath, line: UInt = #line) {
        if !bar(title).waitForExistence(timeout: Self.patience) {
            fail("\(action) did not open \(title)", file: file, line: line)
        }
    }

    /// Fails unless the element arrives.
    func expect(_ element: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: Self.patience) {
            fail(message, file: file, line: line)
        }
    }

    /// Fails unless one of these buttons arrives.
    func expectButton(among labels: [String], _ message: String, patience: TimeInterval = TapTestCase.patience,
                      file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(patience)
        repeat {
            if labels.contains(where: { buttons($0).firstMatch.exists }) { return }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        fail(message, file: file, line: line)
    }

    /// Fails unless a training session opened: its intro, its lesson or its first position.
    func expectSession(after action: String, patience: TimeInterval = TapTestCase.patience,
                       file: StaticString = #filePath, line: UInt = #line) {
        expectButton(among: ["End session", "Close lesson", "Skip the lesson", "Let's go"],
                     "\(action) did not start a session", patience: patience, file: file, line: line)
    }

    /// Fails unless a finished game opened in Rewind.
    func expectGame(after action: String, file: StaticString = #filePath, line: UInt = #line) {
        expectButton(among: ["Next move", "Previous move"], "\(action) did not open the game", file: file, line: line)
    }

    /// Waits for the element to leave the screen; false when it is still there at the end.
    func leaves(_ element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(Self.patience)
        repeat {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return false
    }

    // MARK: Failing

    /// Fails with what is on the screen, on one line, so the log says why without a second run.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTFail("\(message). ON SCREEN: \(screen())", file: file, line: line)
    }

    private func screen() -> String {
        let bars = app.navigationBars.allElementsBoundByIndex.map { $0.identifier }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(30).map { $0.label }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
        let all = "bars \(bars) | buttons \(buttons) | texts \(texts)"
        return String(all.replacingOccurrences(of: "\n", with: " ").prefix(2_400))
    }
}
