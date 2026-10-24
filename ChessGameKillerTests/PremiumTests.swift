import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The free allowances, the locked features, lessons in sessions, rival boards, and pictures
/// of the Premium offer (premium-*.png).
@MainActor
final class PremiumTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "PremiumTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        return formatter.date(from: text)!
    }

    // MARK: The plan

    func testThePlanAsAgreed() {
        XCTAssertEqual(PremiumFeature.ghostVision.free, .perDay(3))
        XCTAssertNil(PremiumFeature.ghostVision.premium)
        XCTAssertEqual(PremiumFeature.talk.free, .perWeek(3))
        XCTAssertEqual(PremiumFeature.talk.premium, .perDay(10))
        XCTAssertEqual(PremiumFeature.scan.free, .perWeek(3))
        XCTAssertEqual(PremiumFeature.scan.premium, .perDay(3))
        XCTAssertEqual(PremiumFeature.ratedPuzzle.free, .perDay(15))
        XCTAssertEqual(PremiumFeature.puzzleRush.free, .perDay(1))
        XCTAssertEqual(PremiumFeature.fullRewind.free, .perDay(1))
        for locked in [PremiumFeature.lessons, .puzzleCycles, .puzzleReview, .trainingRooms, .allOpenings,
                       .masterGames, .boardLooks, .coachProfile] {
            XCTAssertTrue(locked.isLocked, locked.rawValue)
        }
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(feature.limitLine.isEmpty)
            XCTAssertFalse(feature.title.isEmpty)
        }
    }

    // MARK: Counting

    func testADayAllowanceRunsOutAndComesBackTomorrow() {
        let ledger = AllowanceLedger(defaults: defaults, calendar: calendar())
        let morning = date("2026-10-24T09:00:00-05:00")
        let allowance = PremiumFeature.Allowance.perDay(3)
        XCTAssertTrue(ledger.take(.ghostVision, allowance: allowance, now: morning))
        XCTAssertTrue(ledger.take(.ghostVision, allowance: allowance, now: morning))
        XCTAssertTrue(ledger.take(.ghostVision, allowance: allowance, now: morning))
        XCTAssertFalse(ledger.take(.ghostVision, allowance: allowance, now: morning))
        XCTAssertEqual(ledger.remaining(.ghostVision, allowance: allowance, now: morning), 0)
        let lateNight = date("2026-10-24T23:59:00-05:00")
        XCTAssertFalse(ledger.take(.ghostVision, allowance: allowance, now: lateNight))
        let tomorrow = date("2026-10-25T00:01:00-05:00")
        XCTAssertEqual(ledger.remaining(.ghostVision, allowance: allowance, now: tomorrow), 3)
        XCTAssertTrue(ledger.take(.ghostVision, allowance: allowance, now: tomorrow))
    }

    func testAWeekAllowanceLastsTheWeek() {
        let ledger = AllowanceLedger(defaults: defaults, calendar: calendar())
        let allowance = PremiumFeature.Allowance.perWeek(3)
        let monday = date("2026-10-19T10:00:00-05:00")
        for _ in 0..<3 { XCTAssertTrue(ledger.take(.talk, allowance: allowance, now: monday)) }
        let friday = date("2026-10-23T10:00:00-05:00")
        XCTAssertFalse(ledger.take(.talk, allowance: allowance, now: friday))
        let nextWeek = date("2026-10-27T10:00:00-05:00")
        XCTAssertTrue(ledger.take(.talk, allowance: allowance, now: nextWeek))
        XCTAssertEqual(ledger.remaining(.talk, allowance: allowance, now: nextWeek), 2)
    }

    func testTheSameKeyCountsOnce() {
        let ledger = AllowanceLedger(defaults: defaults, calendar: calendar())
        let now = date("2026-10-24T12:00:00-05:00")
        let allowance = PremiumFeature.Allowance.perDay(1)
        XCTAssertTrue(ledger.take(.fullRewind, key: "game-1", allowance: allowance, now: now))
        XCTAssertTrue(ledger.take(.fullRewind, key: "game-1", allowance: allowance, now: now))
        XCTAssertFalse(ledger.take(.fullRewind, key: "game-2", allowance: allowance, now: now))
        XCTAssertTrue(ledger.alreadyUsed(.fullRewind, key: "game-1", allowance: allowance, now: now))
    }

    func testFeaturesCountSeparately() {
        let ledger = AllowanceLedger(defaults: defaults, calendar: calendar())
        let now = date("2026-10-24T12:00:00-05:00")
        XCTAssertTrue(ledger.take(.puzzleRush, allowance: .perDay(1), now: now))
        XCTAssertTrue(ledger.take(.endgameDrill, allowance: .perDay(1), now: now))
        XCTAssertFalse(ledger.take(.puzzleRush, allowance: .perDay(1), now: now))
    }

    // MARK: Free, Premium and unlimited

    func testAFreePlayerRunsOutOfGhostVision() {
        let premium = Premium(defaults: defaults, isPremium: false)
        XCTAssertEqual(premium.remaining(.ghostVision), 3)
        XCTAssertTrue(premium.use(.ghostVision, key: "fen-a"))
        XCTAssertTrue(premium.use(.ghostVision, key: "fen-a"), "the same position again is free")
        XCTAssertTrue(premium.use(.ghostVision, key: "fen-b"))
        XCTAssertTrue(premium.use(.ghostVision, key: "fen-c"))
        XCTAssertFalse(premium.canUse(.ghostVision))
        XCTAssertTrue(premium.canUse(.ghostVision, key: "fen-b"))
        XCTAssertFalse(premium.use(.ghostVision, key: "fen-d"))
    }

    func testPremiumHasNoLimitWhereNothingIsSpent() {
        let premium = Premium(defaults: defaults, isPremium: true)
        for _ in 0..<50 { XCTAssertTrue(premium.use(.ghostVision)) }
        XCTAssertNil(premium.remaining(.ghostVision))
        XCTAssertNil(premium.remaining(.ratedPuzzle))
        XCTAssertTrue(premium.opens(.lessons))
        XCTAssertTrue(premium.opens(.boardLooks))
    }

    func testPremiumStillCapsTheFeaturesThatCostMoney() {
        let premium = Premium(defaults: defaults, isPremium: true)
        XCTAssertEqual(premium.remaining(.talk), 10)
        for _ in 0..<10 { XCTAssertTrue(premium.use(.talk)) }
        XCTAssertFalse(premium.use(.talk))
        for _ in 0..<3 { XCTAssertTrue(premium.use(.scan)) }
        XCTAssertFalse(premium.use(.scan))
    }

    func testLockedFeaturesStayShutForFreePlayers() {
        let premium = Premium(defaults: defaults, isPremium: false)
        XCTAssertFalse(premium.opens(.lessons))
        XCTAssertFalse(premium.use(.puzzleCycles))
        XCTAssertFalse(premium.canUse(.trainingRooms))
        XCTAssertEqual(premium.remaining(.masterGames), 0)
        XCTAssertTrue(premium.opens(.ghostVision), "a counted feature isn't locked")
    }

    func testUnlimitedOpensEverything() {
        let premium = Premium(defaults: defaults, isPremium: false, unlimited: true)
        for _ in 0..<20 { XCTAssertTrue(premium.use(.talk)) }
        XCTAssertTrue(premium.opens(.coachProfile))
        XCTAssertNil(premium.remaining(.scan))
    }

    func testTheAppIsUnlimitedUnderTest() {
        XCTAssertTrue(Premium.shared.unlimited)
    }

    func testPremiumIsRememberedForTheNextLaunch() {
        defaults.set(true, forKey: Premium.activeKey)
        XCTAssertTrue(Premium(defaults: defaults).isPremium)
    }

    // MARK: Lessons, looks

    func testFreePlayersGetTheFirstFiveLessons() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let order = library.course.units.flatMap(\.lessons)
        XCTAssertEqual(library.freeLessonIDs, Array(order.prefix(5)))
        XCTAssertTrue(library.isFreeLesson(order[0]))
        if order.count > 5 { XCTAssertFalse(library.isFreeLesson(order[5])) }
    }

    func testSessionsLeaveOutLessonsAFreePlayerCantWatch() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let skills = library.course.units.flatMap(\.skills).compactMap { library.skill($0) }
        let locked = try XCTUnwrap(skills.first { !library.isFreeLesson($0.lesson) && library.lesson($0.lesson) != nil })
        var open = TrainingPlanner(library: library, progress: TrainingProgress(), seed: 1)
        XCTAssertNotNil(open.practice(locked).lesson)
        var shut = TrainingPlanner(library: library, progress: TrainingProgress(), seed: 1)
        shut.lessonsOpen = false
        XCTAssertNil(shut.practice(locked).lesson)
        XCTAssertFalse(shut.practice(locked).items.isEmpty, "the drills still come")
        let free = try XCTUnwrap(skills.first { library.isFreeLesson($0.lesson) && library.lesson($0.lesson) != nil })
        XCTAssertNotNil(shut.practice(free).lesson)
    }

    func testRivalBoardsOpenOnceTheRivalIsBeaten() {
        let premium = Premium(defaults: defaults, isPremium: false)
        XCTAssertTrue(RivalBoardsEarned.opens(.gilded, premium: premium, defaults: defaults))
        XCTAssertTrue(RivalBoardsEarned.opens(.midnight, premium: premium, defaults: defaults))
        XCTAssertFalse(RivalBoardsEarned.opens(.faberge, premium: premium, defaults: defaults))
        XCTAssertFalse(RivalBoardsEarned.opens(.spark, premium: premium, defaults: defaults))
        RivalBoardsEarned.note([Self.game(against: "Spark", result: .win), Self.game(against: "Drift", result: .loss)],
                               defaults: defaults)
        XCTAssertTrue(RivalBoardsEarned.opens(.spark, premium: premium, defaults: defaults))
        XCTAssertFalse(RivalBoardsEarned.opens(.drift, premium: premium, defaults: defaults))
        XCTAssertTrue(RivalBoardsEarned.opens(.drift, premium: Premium(defaults: defaults, isPremium: true), defaults: defaults))
    }

    private static func game(against rival: String, result: SavedGame.Result) -> SavedGame {
        SavedGame(id: UUID(), date: .now, opponent: rival, level: 1, playerIsWhite: true, result: result,
                  accuracy: nil, positions: [], moves: [], moments: [])
    }

    // MARK: Pictures

    func testOfferPictures() throws {
        let saved = UserDefaults.standard.object(forKey: "boardTheme")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "boardTheme") } else { UserDefaults.standard.removeObject(forKey: "boardTheme") }
        }
        UserDefaults.standard.set("gilded", forKey: "boardTheme")
        try snapshot("premium-offer", PremiumOfferView(feature: nil))
        try snapshot("premium-offer-ghost", PremiumOfferView(feature: .ghostVision))
        UserDefaults.standard.set("midnight", forKey: "boardTheme")
        try snapshot("premium-offer-midnight", PremiumOfferView(feature: .ratedPuzzle))
        let card = ZStack {
            ThemeBackdrop(theme: .gilded).ignoresSafeArea()
            PremiumLimitCard(feature: .talk, accent: BoardTheme.gilded.accent ?? PremiumStyle.gold)
                .padding(20)
        }
        .preferredColorScheme(.dark)
        try snapshot("premium-limit-card", card)
    }

    private func snapshot(_ name: String, _ view: some View, wait: TimeInterval = 1.2) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.isHidden = true
    }
}
