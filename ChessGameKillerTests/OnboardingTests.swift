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
