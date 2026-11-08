import ChessKit
import XCTest
@testable import ChessGameKiller

/// Runs the real Stockfish bundled in the app.
final class StockfishTests: XCTestCase {

    func testNetworkFilesAreBundled() {
        XCTAssertTrue(StockfishEngine.hasNetworks, "Run scripts/fetch_nnue.sh (Xcode does it as a build phase)")
    }

    func testAnalyzesTheStartingPosition() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let start = Position.standard.fen
        let lines = await StockfishEngine.shared.analyze(fen: start, depth: 10, lines: 2)
        // Two lines nearly always; one when the second was left a depth behind on the same move.
        XCTAssertTrue((1...2).contains(lines.count), "\(lines.count) lines")
        for line in lines {
            let move = try XCTUnwrap(line.firstMove)
            XCTAssertNotNil(Notation.san(of: move, fen: start), "\(move) should be legal")
        }
        XCTAssertEqual(Set(lines.compactMap(\.firstMove)).count, lines.count, "a move shows up twice")
    }

    /// Analysis tells its lines as it deepens, so they can show before the search ends.
    func testAnalysisReportsAsItDeepens() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let start = Position.standard.fen
        let reports = Reports()
        let lines = await StockfishEngine.shared.analyze(fen: start, depth: 12, lines: 2, maxTimeMs: 5000) { found, depth in
            reports.add(depth: depth, count: found.count)
        }
        XCTAssertFalse(lines.isEmpty)
        let seen = reports.all
        XCTAssertGreaterThan(seen.count, 3, "it should report several depths before the end")
        XCTAssertEqual(seen.map(\.depth), seen.map(\.depth).sorted(), "depths only go up")
        XCTAssertTrue(seen.allSatisfy { (1...2).contains($0.count) })
    }

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [(depth: Int, count: Int)] = []
        func add(depth: Int, count: Int) { lock.withLock { reports.append((depth, count)) } }
        var all: [(depth: Int, count: Int)] { lock.withLock { reports } }
    }

    func testFindsMateInOne() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let backRank = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
        let lines = await StockfishEngine.shared.analyze(fen: backRank, depth: 8, lines: 1)
        XCTAssertEqual(lines.first?.firstMove, "a1a8")
        XCTAssertEqual(lines.first?.evaluation, .mate(1))
    }

    /// Spark's own search: noisy and a few moves deep, and still a legal move every time.
    func testChoosesALegalMoveAtLowSkill() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        let spark = MatchController.Level.beginner
        for _ in 0..<3 {
            let chosen = await StockfishEngine.shared.chooseMove(fen: fen, skill: spark.skill, depth: spark.depth,
                                                                 thinkTimeMs: spark.thinkTimeMs)
            let move = try XCTUnwrap(chosen)
            XCTAssertNotNil(Notation.san(of: move, fen: fen), "\(move) should be legal")
        }
    }

    /// Every stop gets its "bestmove", even while the main thread is too busy to look. The
    /// replies were read on the main thread in chunks, and a chunk that ended partway through
    /// the "bestmove" lost it: the search then waited out its grace and the next one the
    /// lost-answer wait, about 2.3 s for a move that takes milliseconds.
    func testEveryStopIsAnsweredWhileTheMainThreadIsBusy() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        let traces = Traces()
        StockfishEngine.trace = { traces.add($0) }
        defer { StockfishEngine.trace = nil }
        let start = Position.standard.fen
        for _ in 0..<8 {
            // A deep search with three lines says a lot, and nobody reads it for a while.
            let analysis = Task { await StockfishEngine.shared.analyze(fen: start, depth: 40, lines: 3, maxTimeMs: 5000) }
            await MainActor.run { Thread.sleep(forTimeInterval: 0.3) }
            let started = ContinuousClock.now
            let move = await StockfishEngine.shared.chooseMove(fen: start, skill: 20, depth: 2, thinkTimeMs: 1000)
            let elapsed = ContinuousClock.now - started
            XCTAssertNotNil(move)
            XCTAssertLessThan(elapsed, .milliseconds(1500), "the stop went unanswered")
            _ = await analysis.value
        }
        let lost = traces.all.filter { $0.hasPrefix("no answer to stop") || $0.hasPrefix("an ended search never answered") }
        XCTAssertEqual(lost, [], "every stop should be answered")
    }

    private final class Traces: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    /// A depth cap ends a search long before its time: the weaker rivals answer almost at once.
    func testACappedSearchEndsEarly() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        let fen = Position.standard.fen
        // An earlier test can leave Stockfish still busy with a search whose stop it never
        // answered, and a new search then waits behind it (see StockfishEngine.search). Short
        // searches first, until one comes back promptly, so the timed one starts on an idle engine.
        for _ in 0..<5 {
            let settling = ContinuousClock.now
            _ = await StockfishEngine.shared.chooseMove(fen: fen, skill: 10, depth: 1, thinkTimeMs: 100)
            if ContinuousClock.now - settling < .milliseconds(500) { break }
        }
        let started = ContinuousClock.now
        let chosen = await StockfishEngine.shared.chooseMove(fen: fen, skill: 10, depth: 5, thinkTimeMs: 5000)
        let elapsed = ContinuousClock.now - started
        XCTAssertNotNil(chosen)
        NSLog("TIMING capped depth=5 movetime=5000ms total=\(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(2), "Depth 5 from the start takes a few milliseconds")
    }

    /// How long the computer takes to answer a move at every level, with the real engine,
    /// while the coach is still busy on the player's turn (as in the app). Printed as
    /// TIMING lines in the CI log; the bound only catches a reply that hangs.
    @MainActor
    func testComputerRepliesQuicklyAtEveryLevel() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        StockfishEngine.trace = { NSLog("TIMING engine %@", $0) }
        defer { StockfishEngine.trace = nil }
        for level in MatchController.Level.allCases {
            let match = MatchController(engine: StockfishEngine.shared, sounds: nil)
            match.start(.init(opponent: .computer, playerColor: .white, level: level))
            // Let the hint search get going, so the reply has to stop it first.
            try? await Task.sleep(for: .milliseconds(300))
            let started = ContinuousClock.now
            NSLog("TIMING reply level=\(level) person moves")
            match.tap(.e2)
            match.tap(.e4)
            XCTAssertEqual(match.game.plyCount, 1)
            var waited = 0
            while match.game.plyCount < 2, waited < 1000 {
                try? await Task.sleep(for: .milliseconds(5))
                waited += 1
            }
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            NSLog("TIMING reply level=\(level) think=\(level.thinkTimeMs)ms total=\(ms)ms")
            XCTAssertEqual(match.game.plyCount, 2, "\(level) never answered")
            // Stockfish now and then never answers the stop that ends the hint search. The
            // engine then gives that search its grace and waits out its lost answer before the
            // reply's own search starts (see StockfishEngine.search), so that is allowed for too.
            let recoveryMs = Int((StockfishEngine.stopGrace + StockfishEngine.lostAnswer) / .milliseconds(1))
            XCTAssertLessThan(ms, level.thinkTimeMs + recoveryMs + 2500, "\(level) took \(ms) ms to answer")
            // Leave the engine alone for the next level: no grading or hints still running.
            await match.settleEngine()
        }
    }

    /// Alex's report: Spark as white never made its first move. Every rival opens as
    /// white with the real engine, including when the new game starts while the last
    /// game's hint search is still running (the usual way into a game).
    @MainActor
    func testEveryRivalOpensAsWhite() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        StockfishEngine.trace = { NSLog("TIMING engine %@", $0) }
        defer { StockfishEngine.trace = nil }
        let match = MatchController(engine: StockfishEngine.shared, sounds: nil)
        for level in MatchController.Level.allCases {
            // A game where the person is to move, so a long hint search is under way.
            match.start(.init(opponent: .computer, playerColor: .white, level: level))
            try? await Task.sleep(for: .milliseconds(300))
            let started = ContinuousClock.now
            match.start(.init(opponent: .computer, playerColor: .black, level: level))
            var waited = 0
            while match.game.plyCount < 1, waited < 1200 {
                try? await Task.sleep(for: .milliseconds(5))
                waited += 1
            }
            let elapsed = ContinuousClock.now - started
            NSLog("TIMING opening level=\(level) total=\(elapsed)")
            XCTAssertEqual(match.game.plyCount, 1, "\(level) never opened as white")
            XCTAssertEqual(match.game.sideToMove, .black)
            XCTAssertFalse(match.engineFailed, "\(level) said the engine was unavailable")
        }
        await match.settleEngine()
    }

    // MARK: Grading known blunders with the real engine

    /// Grades `move` the way a game does: the position before searched for two lines,
    /// the one after for the opponent's answer, at the coach's full depth.
    private func gradeWithStockfish(_ move: String, in fen: String) async throws -> MoveReview.Grade {
        let budget = EngineBudget.full
        let engine = StockfishEngine.shared
        let before = await engine.analyze(fen: fen, depth: budget.gradeDepth, lines: 2, maxTimeMs: 10_000)
        let best = try XCTUnwrap(before.first)
        if best.firstMove == move { return .best }
        var board = Board(position: try XCTUnwrap(Position(fen: fen)))
        let squares = try XCTUnwrap(Notation.squares(of: move))
        XCTAssertNotNil(board.move(pieceAt: squares.from, to: squares.to), "\(move) should be legal")
        let answers = await engine.analyze(fen: board.position.fen, depth: budget.gradeDepth, lines: 1, maxTimeMs: 10_000)
        let answer = try XCTUnwrap(answers.first)
        let loss = MoveReview.materialLoss(fen: fen, best: best.moves, played: [move] + answer.moves)
        return MoveReview.grade(before: best.evaluation, after: answer.evaluation.flipped, playedBest: false, materialLoss: loss)
    }

    /// Alex's game against the 1200s, move 22: twelve pawns down, Rd1 walks into mate.
    /// The coach called moves like it "Good".
    func testWalkingIntoMateInALostGameIsABlunder() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "3r2k1/p5pp/2n1p1bn/1pP5/1P3qP1/1KN5/P3B2P/7R w - - 0 22"
        let grade = try await gradeWithStockfish("h1d1", in: fen)
        XCTAssertEqual(grade, .blunder)
    }

    /// Ten pawns down with the bishop on c5 attacked: a3 leaves it to be taken.
    func testHangingAPieceInALostGameIsABlunder() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "r1bqkbnr/ppp2ppp/2n5/2B5/8/8/PPP2PPP/R3K2R w KQkq - 1 10"
        let grade = try await gradeWithStockfish("a2a3", in: fen)
        XCTAssertEqual(grade, .blunder)
    }

    /// The level game the old scale already got right still grades the same.
    func testHangingAKnightInALevelGameIsStillABlunder() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"
        let grade = try await gradeWithStockfish("f3d4", in: fen)
        XCTAssertEqual(grade, .blunder)
    }

    func testAQuietDevelopingMoveIsNotPunished() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"
        let grade = try await gradeWithStockfish("b1c3", in: fen)
        XCTAssertTrue([.best, .excellent, .good].contains(grade), "\(grade)")
    }
}

extension MatchController {
    /// Leaves the shared engine idle for whatever runs next. A fresh two-person game still
    /// starts a hint search, and that search landing in the next test's search cuts it short
    /// (the newest search wins), so this waits for it to report: it sets the evaluation.
    func settleEngine() async {
        startTapping()
        var waited = 0
        while evaluation == nil, waited < 800 {
            try? await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
    }
}
