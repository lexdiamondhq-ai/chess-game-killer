import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// An engine that always names the same line, for Blunder Shield's puzzles.
private actor ShieldEngine: ChessEngine {
    let line: EngineLine

    init(_ line: EngineLine) {
        self.line = line
    }

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] { [line] }
    func chooseMove(fen: String, skill: Int, depth: Int?, thinkTimeMs: Int) async -> String? { line.firstMove }
}

@MainActor
final class BlunderShieldTests: XCTestCase {
    /// Black to move in the skewer puzzle: castling (e8g8) walks into Bf4; Qf6 stays safe.
    private let puzzle = ThinkSample.skewer
    private let safeLine = EngineLine(moves: ["e5f6", "e3f4"], evaluation: .centipawns(-40))

    private func mistake(id: String = "m1", best: String = "e5f6", played: String = "e8g8") -> GameMistake {
        GameMistake(id: id, fen: ThinkSample.skewer.fen, best: best, played: played, skill: "threats",
                    title: "Castled into a skewer", created: .now, due: .now)
    }

    // MARK: Positions

    func testAPuzzlesOpeningMoveIsTheBlunderAndTheEnginesMoveIsSafe() throws {
        let position = try XCTUnwrap(ShieldPosition(puzzle: puzzle, engineLine: safeLine))
        XCTAssertEqual(position.blunder, "e8g8")
        XCTAssertEqual(position.safe, "e5f6")
        XCTAssertEqual(position.mover, .black)
        XCTAssertEqual(position.source, .lichess)
    }

    func testAPuzzleIsTurnedDownWhenTheEngineAgreesWithTheBlunderOrThePositionIsLost() {
        XCTAssertNil(ShieldPosition(puzzle: puzzle, engineLine: EngineLine(moves: ["e8g8"], evaluation: .centipawns(10))))
        XCTAssertNil(ShieldPosition(puzzle: puzzle, engineLine: EngineLine(moves: ["e5f6"], evaluation: .centipawns(-400))))
        XCTAssertNil(ShieldPosition(puzzle: puzzle, engineLine: EngineLine(moves: ["e5f6"], evaluation: .mate(-3))))
        XCTAssertNil(ShieldPosition(puzzle: puzzle, engineLine: nil))
        XCTAssertNotNil(ShieldPosition(puzzle: puzzle, engineLine: EngineLine(moves: ["e5f6"], evaluation: .mate(4))))
    }

    func testAGameMistakeBecomesAPositionOfYourOwn() throws {
        let position = try XCTUnwrap(ShieldPosition(mistake: mistake()))
        XCTAssertEqual(position.safe, "e5f6")
        XCTAssertEqual(position.blunder, "e8g8")
        XCTAssertEqual(position.source, .yours)
        XCTAssertNil(ShieldPosition(mistake: mistake(played: "")))
        XCTAssertNil(ShieldPosition(mistake: mistake(played: "e5f6")))
        XCTAssertNil(ShieldPosition(mistake: mistake(played: "a1a8")))
    }

    func testTheCardsSayWhatAMoveDoes() {
        let fen = puzzle.fen
        XCTAssertEqual(ShieldOption.words(for: "e8g8", fen: fen), "castles")
        XCTAssertEqual(ShieldOption.words(for: "e5f6", fen: fen), "queen moves")
        XCTAssertEqual(ShieldOption.words(for: "e5g3", fen: fen), "queen takes with check")
        XCTAssertEqual(ShieldOption(uci: "e8g8", fen: fen, isSafe: false)?.san, "O-O")
        XCTAssertNil(ShieldOption(uci: "a1a8", fen: fen, isSafe: true))
    }

    // MARK: Rounds

    func testARoundCountsSafePicksAndTheLongestRun() {
        var round = ShieldRound()
        let outcomes: [ShieldOutcome] = [.safe, .safe, .blundered, .safe, .safe, .safe, .timedOut, .safe, .safe, .safe]
        for outcome in outcomes { round.add(outcome) }
        XCTAssertTrue(round.isFinished)
        XCTAssertEqual(round.safe, 8)
        XCTAssertEqual(round.longestRun, 3)
        round.add(.safe)
        XCTAssertEqual(round.outcomes.count, ShieldRound.length)
    }

    // MARK: Sessions

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testYourOwnMistakesComeFirstAndASafePickGrowsTheShield() async throws {
        let store = PuzzleStore(library: PuzzleLibrary(puzzles: [puzzle]))
        let session = BlunderShieldSession(mistakes: [mistake()], library: store.library, rating: 1400,
                                           engine: ShieldEngine(safeLine), store: store, sounds: nil, limit: 60)
        session.start()
        await waitFor { session.stage == .choosing }
        XCTAssertEqual(session.position?.source, .yours)
        XCTAssertEqual(session.options.count, 2)
        let safe = try XCTUnwrap(session.options.first(where: \.isSafe))
        session.pick(safe)
        XCTAssertEqual(session.stage, .revealed)
        XCTAssertEqual(session.outcome, .safe)
        XCTAssertEqual(session.shield, 1)
        XCTAssertEqual(store.progress.shieldBest, 1)
        XCTAssertEqual(session.arrows.count, 2)
        XCTAssertTrue(session.verdict.contains("In your game you played O-O"))

        // Then the puzzle, checked by the engine.
        session.next()
        await waitFor { session.stage == .choosing && session.position?.source == .lichess }
        XCTAssertEqual(session.position?.id, "lichess-\(puzzle.id)")
        let blunder = try XCTUnwrap(session.options.first { !$0.isSafe })
        session.pick(blunder)
        XCTAssertEqual(session.outcome, .blundered)
        XCTAssertEqual(session.shield, 0)
        XCTAssertEqual(session.best, 1)
        session.cancel()
    }

    func testTheRingRunningOutCountsAsAMiss() async {
        let session = BlunderShieldSession(mistakes: [mistake()], library: nil, rating: 1400, engine: nil,
                                           store: nil, sounds: nil, limit: 0.2)
        session.start()
        await waitFor { session.stage == .revealed }
        XCTAssertEqual(session.outcome, .timedOut)
        XCTAssertNil(session.picked)
        XCTAssertEqual(session.round.outcomes, [.timedOut])
        XCTAssertTrue(session.verdict.hasPrefix("Time's up"))
    }

    func testWhenPositionsRunOutTheRoundEnds() async {
        let session = BlunderShieldSession(mistakes: [mistake()], library: nil, rating: 1400, engine: nil,
                                           store: nil, sounds: nil, limit: 60)
        session.start()
        await waitFor { session.stage == .choosing }
        session.pick(session.options[0])
        session.next()
        await waitFor { session.stage == .summary }
        XCTAssertEqual(session.stage, .summary)
    }

    func testNothingToShowSaysSo() async {
        let session = BlunderShieldSession(mistakes: [], library: nil, rating: 1400, engine: nil,
                                           store: nil, sounds: nil)
        session.start()
        await waitFor { session.stage == .empty }
        XCTAssertEqual(session.stage, .empty)
    }

    func testTheBestShieldIsSavedWithPuzzleProgress() throws {
        var progress = PuzzleProgress()
        progress.shieldBest = 7
        let data = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(PuzzleProgress.self, from: data).shieldBest, 7)
        // An older file without it reads as zero.
        let old = try JSONDecoder().decode(PuzzleProgress.self, from: Data(#"{"rating": 1200}"#.utf8))
        XCTAssertEqual(old.shieldBest, 0)
    }

    // MARK: Pictures

    /// The screen while choosing and after a pick, saved as train-shield-*.png when SNAPSHOT_DIR is set.
    func testShieldScreens() async throws {
        let theme = BoardTheme.named(.gilded)
        let store = PuzzleStore(library: PuzzleLibrary(puzzles: [puzzle]))
        let session = BlunderShieldSession(mistakes: [], library: store.library, rating: 1400,
                                           engine: ShieldEngine(safeLine), store: store, sounds: nil, limit: 600)
        session.start()
        await waitFor { session.stage == .choosing }
        ThemeFont.use(theme)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: BlunderShieldView(theme: theme, session: session)
            .environment(store))
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(3))
        try save(window, "train-shield-choosing")
        session.pick(try XCTUnwrap(session.options.first { !$0.isSafe }))
        try await Task.sleep(for: .seconds(1.5))
        try save(window, "train-shield-revealed")
        session.cancel()
        window.isHidden = true
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
