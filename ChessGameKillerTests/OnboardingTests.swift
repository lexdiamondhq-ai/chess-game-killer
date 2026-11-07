import XCTest
@testable import ChessGameKiller

/// The first run and the tips: the welcome shows once and saves what was picked, each tip
/// shows once at the moment it helps, and the banners explain the rule behind the news.
@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "OnboardingTests")
        defaults.removePersistentDomain(forName: "OnboardingTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "OnboardingTests")
        super.tearDown()
    }

    // MARK: Welcome

    func testWelcomeShowsOnceAndCanComeBack() {
        XCTAssertTrue(Welcome.shouldShow(defaults))
        Welcome.markSeen(defaults)
        XCTAssertFalse(Welcome.shouldShow(defaults))
        Welcome.reset(defaults)
        XCTAssertTrue(Welcome.shouldShow(defaults))
    }

    func testCIGamePicturesNeverShowTheWelcome() {
        defaults.set("game", forKey: "showcase")
        XCTAssertFalse(Welcome.shouldShow(defaults))
    }

    func testTheChoiceBecomesTheSettings() {
        let choice = WelcomeChoice(experience: .new, look: .midnight)
        choice.apply(defaults)
        XCTAssertEqual(defaults.integer(forKey: "setup.level"), MatchController.Level.beginner.rawValue)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "midnight")
        XCTAssertTrue(defaults.bool(forKey: "showBestMoves"), "New players see the best move")
        XCTAssertEqual(choice.setup(defaults).level, .beginner)

        WelcomeChoice(experience: .club, look: .gilded).apply(defaults)
        XCTAssertEqual(defaults.integer(forKey: "setup.level"), MatchController.Level.expert.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "showBestMoves"), "Everyone else plays a fair game")
    }

    func testEveryLevelLeadsToADifferentRival() {
        let levels = Experience.allCases.map(\.level)
        XCTAssertEqual(Set(levels).count, levels.count)
        XCTAssertEqual(levels.first, .beginner)
    }

    func testTheWelcomeOffersOnlyFreeLooks() {
        for look in Welcome.looks {
            XCTAssertTrue(BoardTheme.freeLooks.contains(look), "\(look) is locked for a new player")
        }
        XCTAssertEqual(Welcome.looks.first, .gilded, "The default look comes first")
    }

    // MARK: Your name

    func testTheNameIsTheOneFriendsSee() {
        XCTAssertEqual(YourName.key, ChallengeName.key)
        XCTAssertNil(YourName.current(defaults))
        YourName.save("  Alex   Medina ", defaults)
        XCTAssertEqual(YourName.current(defaults), "Alex Medina")
        YourName.save("   ", defaults)
        XCTAssertNil(YourName.current(defaults))
    }

    func testGreetingsTakeTheName() {
        XCTAssertEqual(YourName.address("Good evening", name: "Alex"), "Good evening, Alex")
        XCTAssertEqual(YourName.address("Welcome back. A few minutes a day is how strong players are made.", name: "Alex"),
                       "Welcome back, Alex. A few minutes a day is how strong players are made.")
        XCTAssertEqual(YourName.address("Hello again! You remember more than you think.", name: "Alex"),
                       "Hello again, Alex! You remember more than you think.")
        XCTAssertEqual(YourName.address("Talk me through your plan. I'll check every idea.", name: "Alex"),
                       "Talk me through your plan, Alex. I'll check every idea.")
        // Lines that don't open with a greeting, and no name, stay as they are.
        XCTAssertEqual(YourName.address("Small steps, every day.", name: "Alex"), "Small steps, every day.")
        XCTAssertEqual(YourName.address("Welcome back.", name: nil), "Welcome back.")
        XCTAssertEqual(YourName.address("Welcome back.", name: "  "), "Welcome back.")
        XCTAssertEqual(YourName.address("Hellothere.", name: "Alex"), "Hellothere.")
    }

    func testANamedPlayerGetsAGreetingWithTheirName() {
        let lines = ["Small steps, every day.", "Welcome back. Let's go."]
        for _ in 0..<10 {
            XCTAssertEqual(YourName.pick(lines, name: "Alex"), "Welcome back, Alex. Let's go.")
        }
        XCTAssertNotNil(YourName.pick(lines, name: nil))
    }

    // MARK: The tour

    func testTheTourComesBeforeTheQuestions() {
        XCTAssertEqual(WelcomeFlow.pages, TourPage.allCases.count + 3)
        XCTAssertEqual(TourPage.allCases.first, .hello)
    }

    func testTheTourBoardsMovePieces() {
        var position = TourPosition(fen: "4kb1r/p2rqppp/5n2/1B2p1B1/4P3/1Q6/PPP2PPP/2K4R w k - 0 14")
        let count = position.pieces.count
        position.move("b5", "d7")
        XCTAssertEqual(position.pieces.count, count - 1, "A capture takes the piece that stood there")
        XCTAssertTrue(position.pieces.contains { $0.square == .d7 && $0.kind == .bishop })
        let flat = TourBoardGeometry(width: 240, tilt: 0)
        XCTAssertEqual(flat.center(.a8), CGPoint(x: 15, y: 15))
        let tilted = TourBoardGeometry(width: 240, tilt: 0.5)
        XCTAssertLessThan(tilted.scale(row: 0), tilted.scale(row: 7), "The far rank is drawn smaller")
        XCTAssertEqual(tilted.point(0.5, 1).y, tilted.height, accuracy: 0.001)
        XCTAssertEqual(tilted.point(0.5, 0).y, 0, accuracy: 0.001)
    }

    // MARK: Tips

    func testEachTipShowsOnce() {
        XCTAssertEqual(TipBook.next(playerMoves: 1, lineReady: false, justUndid: false, bigBoard: false, defaults), .coachOrb)
        TipBook.markSeen(.coachOrb, defaults)
        XCTAssertNil(TipBook.next(playerMoves: 1, lineReady: false, justUndid: false, bigBoard: false, defaults))
        // Seeing ahead waits for a few moves and a line to show.
        XCTAssertNil(TipBook.next(playerMoves: 2, lineReady: true, justUndid: false, bigBoard: false, defaults))
        XCTAssertNil(TipBook.next(playerMoves: 4, lineReady: false, justUndid: false, bigBoard: false, defaults))
        XCTAssertEqual(TipBook.next(playerMoves: 4, lineReady: true, justUndid: false, bigBoard: false, defaults), .ghostVision)
        TipBook.resetAll(defaults)
        XCTAssertEqual(TipBook.next(playerMoves: 1, lineReady: false, justUndid: false, bigBoard: false, defaults), .coachOrb)
    }

    func testAnUndoIsExplainedFirst() {
        XCTAssertEqual(TipBook.next(playerMoves: 5, lineReady: true, justUndid: true, bigBoard: true, defaults), .undoHelp)
        TipBook.markSeen(.undoHelp, defaults)
        XCTAssertEqual(TipBook.next(playerMoves: 0, lineReady: false, justUndid: false, bigBoard: true, defaults), .bigBoard)
    }

    func testPicturesShowNoTipsUnlessAsked() {
        defaults.set(true, forKey: "tipsOff")
        XCTAssertNil(TipBook.next(playerMoves: 1, lineReady: true, justUndid: true, bigBoard: true, defaults))
    }

    func testTipsAreOneLine() {
        for tip in AppTip.allCases {
            XCTAssertLessThanOrEqual(tip.text.count, 80, "\(tip) is more than a line")
        }
    }

    // MARK: Rules on the banners

    func testBannersSayTheRuleBehindTheNews() {
        let grudge = ArmyNews(slot: .queen, rank: .veteran, name: "Vesper", kind: .grudge(rival: "Pulse", times: 3))
        XCTAssertEqual(grudge.rule, "Beat Pulse with Vesper making a capture for bonus XP.")
        let staked = ArmyNews(slot: .queen, rank: .veteran, name: "Vesper", kind: .staked(rival: "Pulse"))
        XCTAssertTrue(staked.rule?.contains("Pulse keeps Vesper") == true)
        XCTAssertNil(ArmyNews(slot: .queen, rank: .veteran, name: "Vesper").rule)
    }
}
