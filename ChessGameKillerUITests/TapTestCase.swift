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
    private var screenFrame = CGRect.zero
    /// The newest tap and where it landed, for a failure to say.
    private var lastTap = "none yet"

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
        screenFrame = .zero
        lastTap = "none yet"
    }

    /// A player with Premium, and one without it, whatever the simulator's account says.
    static let premium = ["-premium", "YES"]
    static let free = ["-premium", "NO"]

    /// Learn, as the Home's tab opens it (CI's pictures open it the same way, with `-showcaseOpen learn`).
    func openLearn(_ arguments: [String] = []) {
        launch(["-showcaseOpen", "learn"] + arguments)
        expectPage("Learn", after: "Opening Learn")
    }

    /// One of Learn's six doors, opened by its tile on Learn.
    func openDoor(_ door: String, _ arguments: [String] = []) {
        openLearn(arguments)
        tap(buttons(startingWith: door + "."), "The \(door) door")
        expectPage(door, after: "Tapping the \(door) door")
    }

    /// The vine's own page, opened by its card on Learn.
    ///
    /// The page is known by words it says and Learn does not ("3 leaves grown"). The card and
    /// the page both carry "YOUR VINE", so those words can't tell one from the other.
    func openVine(file: StaticString = #filePath, line: UInt = #line) {
        let grown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'grown'"))
        if grown.firstMatch.exists {
            fail("Learn already says what only the vine's page should", file: file, line: line)
        }
        tap(vineCard, "The vine on Learn", file: file, line: line)
        expect(grown.firstMatch, "Tapping the vine on Learn did not open the vine's page", file: file, line: line)
    }

    /// The vine's card on Learn.
    var vineCard: XCUIElementQuery { buttons(startingWith: "Your vine") }

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

    /// Texts with exactly this label.
    func texts(_ label: String) -> XCUIElementQuery {
        app.staticTexts.matching(Self.named(label))
    }

    /// Anything with exactly this label, whatever kind of element SwiftUI made it (a menu's button, say).
    func anythings(_ label: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
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
    /// `scrolls` off waits for it where it is (the Home's own bar never needs a scroll); on, the
    /// page may be dragged, so it is for rows on a page that scrolls.
    /// `at` touches a spot inside it instead of its middle: (0.9, 0.5) is near its right edge.
    func tap(_ matches: XCUIElementQuery, _ name: String, scrolls: Bool = true, at spot: CGVector? = nil,
             file: StaticString = #filePath, line: UInt = #line) {
        // A screen that is still arriving gets a moment before anything is dragged.
        let settled = Date().addingTimeInterval(scrolls ? 1.5 : Self.patience)
        var found = touchable(matches)
        while found == nil, Date() < settled {
            Thread.sleep(forTimeInterval: 0.3)
            found = touchable(matches)
        }
        if scrolls {
            if found == nil { found = hunted(matches) }
            // What sits in the strip at the top or the bottom of the screen is first brought inside.
            if let reached = found {
                found = broughtIn(matches, reached, name, at: spot) ?? hunted(matches)
            }
        }
        guard let found else {
            fail("\(name) can't be touched", file: file, line: line)
            return
        }
        lastTap = "\(name) \(place(found.frame, spot))"
        if let spot {
            found.coordinate(withNormalizedOffset: spot).tap()
        } else {
            found.tap()
        }
    }

    /// Drags the page until one of the matches can be touched: further down the page first (rows
    /// in a lazy grid don't exist until they are near), then back up.
    private func hunted(_ matches: XCUIElementQuery) -> XCUIElement? {
        for move in 0..<16 {
            if move < 8 {
                drag(from: 0.78, to: 0.30)
            } else {
                drag(from: 0.30, to: 0.78)
            }
            if let found = touchable(matches) { return found }
        }
        return nil
    }

    /// How much of the screen's height, at its top and at its bottom, a tap should stay out of:
    /// the status bar and the page's own bar, and the Home indicator's strip.
    static let topStrip: CGFloat = 0.15
    static let bottomStrip: CGFloat = 0.07

    /// A row can count as touchable while it sits under the status bar at the top of the screen,
    /// or over the Home indicator at the bottom, and a tap there may never reach it: a tap on
    /// "Practice" on Chess DNA landed 42 points from the top and opened nothing, with nothing
    /// wrong in the app (2026-11-27; `EdgeTapTests` parks a row there on purpose). So the page is
    /// moved until the tap lands in the middle part of the screen, as a thumb would move it. Each
    /// move is written down ("TAPNOTE"), so the log says when it was needed. Something pinned in a
    /// strip does not move, and is tapped where it is. Nil when the row can't be touched any more.
    private func broughtIn(_ matches: XCUIElementQuery, _ reached: XCUIElement, _ name: String,
                           at spot: CGVector?) -> XCUIElement? {
        let screen = screenRect
        guard screen.height > 200 else { return reached }
        let top = screen.minY + screen.height * Self.topStrip
        let bottom = screen.maxY - screen.height * Self.bottomStrip
        var element = reached
        var frame = reached.frame
        for _ in 0..<3 {
            let height = tapHeight(frame, spot)
            // How far the page has to go: down the screen (+) from under the top, up (-) from the bottom.
            let need: CGFloat
            if height < top {
                need = max(top - frame.minY, (top - height) * 2)
            } else if height > bottom {
                need = -max(frame.maxY - bottom, (height - bottom) * 2)
            } else {
                break
            }
            print("TAPNOTE Moved the page for \(name): its tap would land \(place(frame, spot)), its frame \(frame)")
            let far = min(max(abs(need) + 16, 48), screen.height * 0.4)
            let start: CGFloat = need > 0 ? 0.38 : 0.62
            drag(from: start, to: start + (need > 0 ? far : -far) / screen.height)
            guard let again = waitTouchable(matches, patience: 3) else { return nil }
            element = again
            let moved = again.frame
            if moved == frame { break } // Pinned, or the page is at its end: it goes no further.
            frame = moved
        }
        return element
    }

    /// Slides the page until this edge of the element rests at this height on the screen, give
    /// or take `slack`. False when it could not be put there. For the helper's own checks.
    func park(_ element: XCUIElement, _ edge: (CGRect) -> CGFloat, at target: CGFloat, slack: CGFloat) -> Bool {
        let screen = screenRect
        guard screen.height > 200 else { return false }
        for _ in 0..<12 {
            guard element.exists else { return false }
            // Too low on the screen (+): the page goes up. Too high (-): it comes down.
            let off = edge(element.frame) - target
            if abs(off) <= slack { return true }
            let far = min(max(abs(off), 24), screen.height * 0.35)
            let start: CGFloat = off > 0 ? 0.7 : 0.3
            drag(from: start, to: start + (off > 0 ? -far : far) / screen.height)
        }
        return false
    }

    /// The screen's height, in points.
    var screenHeight: CGFloat { screenRect.height }

    /// How far down the screen a tap on something with this frame lands: the spot asked for, or
    /// the middle of the part of it that is on the screen.
    private func tapHeight(_ frame: CGRect, _ spot: CGVector?) -> CGFloat {
        if let spot { return frame.minY + frame.height * spot.dy }
        let seen = frame.intersection(screenRect)
        return seen.isNull ? frame.midY : seen.midY
    }

    /// Where a tap lands, in words for the log: "at 201,849 on a 402x874 screen".
    private func place(_ frame: CGRect, _ spot: CGVector?) -> String {
        let across = frame.minX + frame.width * (spot?.dx ?? 0.5)
        let screen = screenRect
        return "at \(Int(across)),\(Int(tapHeight(frame, spot))) on a \(Int(screen.width))x\(Int(screen.height)) screen"
    }

    /// The screen, read once for each launch.
    private var screenRect: CGRect {
        if screenFrame.isEmpty { screenFrame = app.frame }
        return screenFrame
    }

    /// The first match a finger could reach: on the screen, with nothing over it.
    func touchable(_ matches: XCUIElementQuery) -> XCUIElement? {
        matches.allElementsBoundByIndex.first { $0.isHittable }
    }

    /// Waits for a match a finger could reach; nil when none came.
    func waitTouchable(_ matches: XCUIElementQuery, patience: TimeInterval = TapTestCase.patience) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(patience)
        repeat {
            if let found = touchable(matches) { return found }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return nil
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

    /// Fails unless one of the matches arrives where a finger could reach it.
    func expectTouchable(_ matches: XCUIElementQuery, _ message: String, patience: TimeInterval = TapTestCase.patience,
                         file: StaticString = #filePath, line: UInt = #line) {
        if waitTouchable(matches, patience: patience) == nil {
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

    // MARK: Rooms, sessions and the Premium offer

    /// Fails unless a training room opened over the page: a Close button that can be touched,
    /// and the room's name at its top when one is given (`RoomHeader`).
    func expectRoom(_ title: String? = nil, after action: String, patience: TimeInterval = TapTestCase.patience,
                    file: StaticString = #filePath, line: UInt = #line) {
        expectTouchable(buttons("Close"), "\(action) did not open its room", patience: patience, file: file, line: line)
        if let title, !texts(title).firstMatch.waitForExistence(timeout: 5) {
            fail("\(action) opened something other than \(title)", file: file, line: line)
        }
    }

    /// Fails unless the Premium offer came up: its plans, and a Close button that can be touched.
    func expectPremiumOffer(after action: String, file: StaticString = #filePath, line: UInt = #line) {
        expectTouchable(buttons("Close"), "\(action) did not open the Premium offer", file: file, line: line)
        if !buttons(startingWith: "Yearly").firstMatch.waitForExistence(timeout: 5) {
            fail("\(action) opened something other than the Premium offer", file: file, line: line)
        }
    }

    /// Touches what closes a screen, then waits for what opened it to be back under a finger.
    func close(_ closer: XCUIElementQuery, backTo opener: XCUIElementQuery, _ name: String,
               file: StaticString = #filePath, line: UInt = #line) {
        tap(closer, "The way out of \(name)", scrolls: false, file: file, line: line)
        expectTouchable(opener, "Closing \(name) did not come back to where it was opened", file: file, line: line)
    }

    /// Ends the session that is open (its lesson first, when it starts with one), then waits for
    /// what opened it to be back under a finger.
    func endSession(backTo opener: XCUIElementQuery, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let ways = app.buttons.matching(NSPredicate(format: "label == 'End session' OR label == 'Close lesson' OR label == 'Close'"))
        for attempt in 0..<3 {
            if attempt > 0, waitTouchable(opener, patience: 4) != nil { return }
            guard let way = waitTouchable(ways, patience: attempt == 0 ? Self.patience : 4) else { break }
            way.tap()
        }
        expectTouchable(opener, "Ending \(name) did not come back to where it was opened", file: file, line: line)
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

    /// Fails with the newest tap and what is on the screen, on one line, so the log says why
    /// without a second run.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTFail("\(message). LAST TAP: \(lastTap). ON SCREEN: \(screen())", file: file, line: line)
    }

    /// Prints what is on the screen without failing, on a line the CI log repeats ("TAPNOTE"):
    /// how a new test learns the words on a screen it can't see.
    func note(_ title: String) {
        print("TAPNOTE \(title): \(screen())")
    }

    /// The bars, then the newest buttons and texts in the tree, from one snapshot. The Home stays
    /// in the tree under a screen opened over it and comes first, so the last ones are the screen on top.
    private func screen() -> String {
        guard let tree = try? app.snapshot() else { return "the screen could not be read" }
        var bars: [String] = []
        var buttons: [String] = []
        var texts: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            switch node.elementType {
            case .navigationBar: bars.append(node.identifier)
            case .button where !node.label.isEmpty: buttons.append(node.label)
            case .staticText where !node.label.isEmpty: texts.append(node.label)
            default: break
            }
            node.children.forEach(walk)
        }
        walk(tree)
        let all = "bars \(bars) | buttons \(Array(buttons.suffix(45))) | texts \(Array(texts.suffix(30)))"
        return String(all.replacingOccurrences(of: "\n", with: " ").prefix(3_200))
    }
}
