import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

// Board vision: the coordinates drill, and the board scan (the Traffic Light as a drill).
// The scan's answers come from the rules alone. While they were written they were also
// checked against python-chess on every position in the puzzle pack, with no differences.

/// Each scan's answers on hand-picked positions: discovered checks, pins, promotions,
/// en passant, kings, x-rays, and real positions from the pack.
final class BoardScanTests: XCTestCase {

    /// A position and the squares each scan must find in it. Nil: the scan skips the position.
    private struct Case {
        let name: String
        let fen: String
        let checks: [String]?
        let captures: [String]
        let threats: [String]?
    }

    private static let cases: [Case] = [
        Case(name: "every knight move uncovers the rook", fen: "4k3/8/8/8/4N3/8/8/K3R3 w - - 0 1",
             checks: ["c3", "c5", "d2", "d6", "f2", "f6", "g3", "g5"], captures: [], threats: []),
        Case(name: "a pinned knight gives no check", fen: "4r3/8/8/7k/8/8/4N3/4K3 w - - 0 1",
             checks: [], captures: [], threats: []),
        Case(name: "only the knight promotion checks", fen: "8/2k1P3/8/8/8/8/8/7K w - - 0 1",
             checks: ["e8"], captures: [], threats: []),
        Case(name: "en passant uncovers the rook", fen: "8/8/8/R2pP2k/8/8/8/4K3 w - d6 0 1",
             checks: ["d6"], captures: ["d5"], threats: []),
        Case(name: "castling gives check, so the checks scan skips it", fen: "5k2/8/8/8/8/8/8/4K2R w K - 0 1",
             checks: nil, captures: [], threats: []),
        Case(name: "rook and queen both check on a8: one square", fen: "4k3/3p1p2/8/8/8/8/8/R3K2Q w - - 0 1",
             checks: ["a8", "e4", "h8"], captures: [], threats: []),
        Case(name: "en passant takes the pawn beside it",
             fen: "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3",
             checks: ["b5", "h5"], captures: ["f5"], threats: []),
        Case(name: "a pinned knight can't take", fen: "4r3/8/8/7k/3p4/8/4N3/4K3 w - - 0 1",
             checks: [], captures: [], threats: []),
        Case(name: "the king takes only what isn't defended", fen: "4k3/8/8/2p5/3nKn2/8/8/8 w - - 0 1",
             checks: [], captures: ["f4"], threats: []),
        Case(name: "in check, only the captures that answer it", fen: "r3k3/8/8/8/8/R4n2/8/4K2Q w - - 0 1",
             checks: [], captures: ["f3"], threats: nil),
        Case(name: "taking and promoting with check", fen: "1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1",
             checks: ["b8"], captures: ["b8"], threats: []),
        Case(name: "a defended rook attacked by a pawn", fen: "7k/8/8/3p4/4R3/5P2/8/4K3 w - - 0 1",
             checks: ["e8", "h4"], captures: [], threats: ["e4"]),
        Case(name: "an even trade is no threat", fen: "4k3/8/2n5/8/3B4/2P5/8/4K3 w - - 0 1",
             checks: [], captures: [], threats: []),
        Case(name: "an undefended pawn", fen: "4k3/8/1q6/8/8/8/1P6/4K3 w - - 0 1",
             checks: [], captures: [], threats: ["b2"]),
        Case(name: "in check, there's no threat scan", fen: "4k3/8/8/8/8/8/3q4/4K3 w - - 0 1",
             checks: [], captures: ["d2"], threats: nil),
        // Positions from the pack, after the opponent's first move.
        Case(name: "UGlI7: a pinned pawn can't take the bishop on h3",
             fen: "r3k1nr/ppp2ppp/8/3pP1q1/2P1pP2/2P1P2b/P3B1PP/R1BQ1RK1 b kq f3 0 11",
             checks: ["g2"], captures: ["c4", "e5", "f4", "g2"], threats: ["d5", "g5"]),
        Case(name: "DcYxb: the queen behind the bishop makes f2 a threat",
             fen: "rnb1k1nr/ppp2ppp/1q6/2b1p1B1/4P3/2N2N2/PPP2PPP/R2QKB1R w KQkq - 4 7",
             checks: ["b5", "d7", "d8"], captures: ["e5"], threats: ["b2", "f2"]),
        Case(name: "Ha4wN: the rook on c7 guards a7 through the rook that takes it",
             fen: "2r5/pRrnBkp1/4p2p/3n4/3NN3/8/P4PPP/1R4K1 b - - 0 25",
             checks: ["c1"], captures: ["b7", "e7"], threats: []),
        Case(name: "esNlI: the rook on f2 guards b2 through the rook that takes it",
             fen: "6k1/p2qp1bp/3pN3/3Pn2P/8/1P5K/1Br2R2/5R2 w - - 0 31",
             checks: ["f8"], captures: ["c2", "e5"], threats: []),
        Case(name: "ariqG: a king can't take back next to the other king",
             fen: "k2r4/p1R1N3/Kp3p2/1P5p/Q7/q7/7N/8 b - - 2 39",
             checks: ["a4"], captures: ["a4", "e7"], threats: ["a3", "a7"]),
        Case(name: "HUnMK: a king can't take back next to the other king",
             fen: "8/6k1/4R2p/6pK/r7/7P/6P1/8 b - - 6 46",
             checks: ["h4"], captures: [], threats: ["h6"]),
        Case(name: "0YPDM: a pinned knight doesn't defend e2",
             fen: "k3r3/pp3Q2/1p6/1q6/1P6/8/Pb2RPP1/5KNr w - - 2 33",
             checks: ["b7", "e8"], captures: ["b7", "e8"], threats: ["b4", "e2"]),
        Case(name: "dAuJi: a pinned pawn can't take the bishop on h6",
             fen: "r1b2rk1/1pqpbppp/p6B/3pn3/1P4Q1/2P2N2/P4PPP/RN3RK1 w - - 0 14",
             checks: ["g7"], captures: ["d7", "e5", "g7"], threats: ["g4"]),
    ]

    func testHandPickedPositions() throws {
        for item in Self.cases {
            let position = try XCTUnwrap(Position(fen: item.fen), item.name)
            for kind in BoardScan.Kind.allCases {
                let expected: [String]?
                switch kind {
                case .checks: expected = item.checks
                case .captures: expected = item.captures
                case .threats: expected = item.threats
                }
                XCTAssertEqual(BoardScan.targets(kind, in: position).map(Self.names), expected, "\(kind.title): \(item.name)")
            }
        }
    }

    func testChecksAreNamedAsMovesFromWhereTheyStart() throws {
        let discovered = try XCTUnwrap(BoardScan.checks(in: position("4k3/8/8/8/4N3/8/8/K3R3 w - - 0 1")))
        let d6 = try XCTUnwrap(discovered.first(where: { $0.square == .d6 }))
        XCTAssertEqual(d6.from, .e4)
        XCTAssertEqual(d6.name, "Nd6+")

        let promotion = try XCTUnwrap(BoardScan.checks(in: position("8/2k1P3/8/8/8/8/8/7K w - - 0 1")))
        XCTAssertEqual(promotion.map(\.name), ["e8=N+"])
        XCTAssertEqual(promotion.first?.from, .e7)

        let passant = try XCTUnwrap(BoardScan.checks(in: position("8/8/8/R2pP2k/8/8/8/4K3 w - d6 0 1")))
        XCTAssertEqual(passant.map(\.name), ["exd6+"])

        let twice = try XCTUnwrap(BoardScan.checks(in: position("4k3/3p1p2/8/8/8/8/8/R3K2Q w - - 0 1")))
        let a8 = try XCTUnwrap(twice.first(where: { $0.square == .a8 }))
        XCTAssertEqual(a8.from, .a1, "The cheaper piece names a square two pieces can check from")
        XCTAssertEqual(a8.name, "Ra8+")
    }

    func testCapturesAndThreatsAreNamedAsPieces() throws {
        let passant = BoardScan.captures(in: try position("8/8/8/R2pP2k/8/8/8/4K3 w - d6 0 1"))
        XCTAssertEqual(passant.map(\.square), [.d5])
        XCTAssertEqual(passant.first?.from, .e5)
        XCTAssertEqual(passant.first?.name, "their pawn on d5")

        let king = BoardScan.captures(in: try position("4k3/8/8/2p5/3nKn2/8/8/8 w - - 0 1"))
        XCTAssertEqual(king.first?.name, "their knight on f4")
        XCTAssertEqual(king.first?.from, .e4)

        let rook = try XCTUnwrap(BoardScan.threats(in: position("7k/8/8/3p4/4R3/5P2/8/4K3 w - - 0 1")))
        XCTAssertEqual(rook.first?.name, "your rook on e4")
        XCTAssertEqual(rook.first?.from, .d5, "The arrow comes from the pawn that attacks it")

        let pawn = try XCTUnwrap(BoardScan.threats(in: position("4k3/8/1q6/8/8/8/1P6/4K3 w - - 0 1")))
        XCTAssertEqual(pawn.first?.name, "your pawn on b2")
        XCTAssertEqual(pawn.first?.from, .b6)
    }

    func testPassingTheMoveDropsEnPassant() throws {
        let passed = try XCTUnwrap(BoardScan.passingTheMove(
            position("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")))
        XCTAssertEqual(passed.sideToMove, .black)
        XCTAssertEqual(passed.fen.split(separator: " ")[3], "-")
    }

    private func position(_ fen: String) throws -> Position {
        try XCTUnwrap(Position(fen: fen), fen)
    }

    private static func names(_ targets: [BoardScan.Target]) -> [String] {
        targets.map(\.square.notation).sorted()
    }
}

/// A round of the board scan: the positions, the player's taps, the totals, and picking
/// positions from the pack.
final class BoardScanRoundTests: XCTestCase {

    func testAnExerciseIsThePositionAfterTheirMove() throws {
        let puzzle = VisionSample.puzzle("UGlI7")
        let exercise = try XCTUnwrap(BoardScan.Exercise(puzzle: puzzle, kind: .threats))
        XCTAssertEqual(exercise.id, "UGlI7-threats")
        XCTAssertEqual(exercise.puzzleID, "UGlI7")
        XCTAssertEqual(exercise.startFEN, puzzle.fen)
        XCTAssertEqual(exercise.theirMove, "f2f4")
        XCTAssertEqual(exercise.fen, "r3k1nr/ppp2ppp/8/3pP1q1/2P1pP2/2P1P2b/P3B1PP/R1BQ1RK1 b kq f3 0 11")
        XCTAssertEqual(exercise.player, .black)
        XCTAssertEqual(exercise.targets.map(\.square.notation), ["d5", "g5"])
        XCTAssertEqual(exercise.target(on: .g5)?.from, .f4)
        XCTAssertNil(exercise.target(on: .h3), "White's g-pawn is pinned, so the bishop is safe")
    }

    func testAPositionNeedsSomethingToFind() {
        XCTAssertNil(BoardScan.Exercise(id: "pin", startFEN: "4r3/8/8/7k/8/8/4N3/4K3 w - - 0 1", kind: .checks))
        XCTAssertNil(BoardScan.Exercise(id: "castle", startFEN: "5k2/8/8/8/8/8/8/4K2R w K - 0 1", kind: .checks))
        XCTAssertNil(BoardScan.Exercise(id: "check", startFEN: "4k3/8/8/8/8/8/3q4/4K3 w - - 0 1", kind: .threats))
        XCTAssertNotNil(BoardScan.Exercise(id: "check", startFEN: "4k3/8/8/8/8/8/3q4/4K3 w - - 0 1", kind: .captures))
        XCTAssertNil(BoardScan.Exercise(id: "UGlI7", startFEN: VisionSample.puzzle("UGlI7").fen, theirMove: "f2f5", kind: .threats),
                     "A move that isn't legal")
    }

    func testAnAttemptCountsFindsSlipsAndRepeats() throws {
        let exercise = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .checks))
        var attempt = BoardScan.Attempt(exercise: exercise)
        XCTAssertEqual(attempt.outcome, .missed)
        XCTAssertEqual(attempt.tap(.e8), .found)
        XCTAssertEqual(attempt.tap(.e8), .again)
        XCTAssertEqual(attempt.tap(.a1), .slip)
        XCTAssertEqual(attempt.tap(.a1), .again, "A slip counts once")
        XCTAssertFalse(attempt.isComplete)
        XCTAssertEqual(attempt.missed.map(\.square), [.h4])
        XCTAssertEqual(attempt.outcome, .afterMistake)
        XCTAssertEqual(attempt.tap(.h4), .found)
        XCTAssertTrue(attempt.isComplete)
        XCTAssertEqual(attempt.slips, [.a1])
        XCTAssertEqual(attempt.outcome, .afterMistake, "Everything found, but after a slip")

        var clean = BoardScan.Attempt(exercise: exercise)
        clean.tap(.h4)
        clean.tap(.e8)
        XCTAssertEqual(clean.outcome, .firstTry)
    }

    func testTheSummaryAddsUpTheRound() throws {
        let checks = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .checks))
        let threats = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .threats))
        var first = BoardScan.Attempt(exercise: checks)
        first.tap(.e8)
        first.tap(.h4)
        first.seconds = 3
        var second = BoardScan.Attempt(exercise: threats)
        second.tap(.a1)
        second.seconds = 5
        let summary = BoardScan.Summary(attempts: [first, second])
        XCTAssertEqual(summary, BoardScan.Summary(found: 2, total: 3, slips: 1, seconds: 4))
        XCTAssertEqual(summary.percent, 50, "2 found, out of 3 to find and 1 slip")
    }

    func testABetterRoundIsMoreAccurateOrQuicker() {
        let round = BoardScan.Summary(found: 20, total: 22, slips: 1, seconds: 4)
        XCTAssertEqual(round.percent, 87)
        XCTAssertTrue(round.beats(nil))
        XCTAssertFalse(BoardScan.Summary(found: 0, total: 0, slips: 0, seconds: 0).beats(nil), "An empty round is never a best")
        XCTAssertTrue(BoardScan.Summary(found: 22, total: 22, slips: 0, seconds: 9).beats(round), "More accurate wins, even when slower")
        XCTAssertTrue(BoardScan.Summary(found: 20, total: 22, slips: 1, seconds: 3).beats(round), "As accurate and quicker")
        XCTAssertFalse(BoardScan.Summary(found: 20, total: 22, slips: 1, seconds: 4).beats(round), "A tie keeps the old best")
        XCTAssertFalse(BoardScan.Summary(found: 15, total: 22, slips: 0, seconds: 1).beats(round))
    }

    func testASavedSummaryStillLoadsWithFieldsMissing() throws {
        let old = try JSONDecoder().decode(BoardScan.Summary.self, from: Data(#"{"found": 7, "total": 9}"#.utf8))
        XCTAssertEqual(old, BoardScan.Summary(found: 7, total: 9, slips: 0, seconds: 0))
        let round = BoardScan.Summary(found: 3, total: 4, slips: 1, seconds: 2.5)
        XCTAssertEqual(try JSONDecoder().decode(BoardScan.Summary.self, from: JSONEncoder().encode(round)), round)
    }

    func testMixedAsksForADifferentKindEachTime() {
        let kinds = BoardScan.Mode.mixed.kinds(count: 8, start: 1)
        XCTAssertEqual(Array(kinds.prefix(4)), [.captures, .threats, .checks, .captures])
        for (one, next) in zip(kinds, kinds.dropFirst()) {
            XCTAssertNotEqual(one, next)
        }
        XCTAssertEqual(BoardScan.Mode.threats.kinds(count: 3), [.threats, .threats, .threats])
    }

    func testARoundComesFromThePackNearTheRating() throws {
        let pack = try VisionSample.pack()
        var random = TrainingRandom(seed: 7)
        let round = BoardScan.exercises(from: pack, mode: .mixed, rating: 1500, avoid: [], using: &random)
        XCTAssertEqual(round.count, BoardScan.positionsPerRound)
        XCTAssertEqual(Set(round.map(\.puzzleID)).count, round.count, "No puzzle twice")
        for (one, next) in zip(round, round.dropFirst()) {
            XCTAssertNotEqual(one.kind, next.kind, "Mixed changes the kind at every position")
        }
        let ratings = Dictionary(pack.puzzles.map { ($0.id, $0.rating) }, uniquingKeysWith: { first, _ in first })
        for exercise in round {
            XCTAssertTrue((1...BoardScan.mostTargets).contains(exercise.targets.count), exercise.id)
            XCTAssertLessThanOrEqual(abs((ratings[exercise.puzzleID] ?? 0) - 1500), 200, exercise.id)
            XCTAssertEqual(exercise.player, Position(fen: exercise.fen)?.sideToMove)
        }

        var same = TrainingRandom(seed: 7)
        XCTAssertEqual(BoardScan.exercises(from: pack, mode: .mixed, rating: 1500, avoid: [], using: &same), round,
                       "The same seed picks the same round")

        var other = TrainingRandom(seed: 8)
        let next = BoardScan.exercises(from: pack, mode: .checks, rating: 1500, avoid: Set(round.map(\.puzzleID)), using: &other)
        XCTAssertEqual(next.count, BoardScan.positionsPerRound)
        XCTAssertTrue(next.allSatisfy { $0.kind == .checks })
        XCTAssertTrue(Set(next.map(\.puzzleID)).isDisjoint(with: round.map(\.puzzleID)), "Recent positions wait their turn")
    }

    func testARoundStillComesWhenEverythingWasScannedLately() {
        let puzzles = ["UGlI7", "DcYxb", "Ha4wN"].map(VisionSample.puzzle)
        var random = TrainingRandom(seed: 1)
        let round = BoardScan.exercises(from: PuzzleLibrary(puzzles: puzzles), mode: .checks, rating: 500,
                                        avoid: Set(puzzles.map(\.id)), count: 3, using: &random)
        XCTAssertEqual(Set(round.map(\.puzzleID)), Set(puzzles.map(\.id)), "Repeats beat a short round")
    }

    func testTheRatingRangeHoldsThePuzzlesRatedInIt() throws {
        let pack = try VisionSample.pack()
        for ratings in [1400...1600, 0...500, 2500...4000, 1500...1500] {
            let range = BoardScan.ratingRange(ratings, in: pack.puzzles)
            let expected = pack.puzzles.indices.filter { ratings.contains(pack.puzzles[$0].rating) }
            XCTAssertEqual(Array(range), expected, "\(ratings)")
        }
    }
}

/// The coordinates drill's round: the squares named, right and wrong taps, the clock.
final class CoordinateRoundTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testTheSameSeedNamesTheSameSquares() {
        var one = CoordinateRound(side: .white, seed: 42)
        var two = CoordinateRound(side: .white, seed: 42)
        one.start(at: start)
        two.start(at: start)
        for _ in 0..<20 {
            XCTAssertEqual(one.target, two.target)
            XCTAssertEqual(one.upcoming, two.upcoming)
            one.tap(one.target, at: start + 1)
            two.tap(two.target, at: start + 1)
        }
    }

    func testNothingCountsBeforeTheStartOrAfterTheClock() {
        var round = CoordinateRound(side: .black, seed: 1)
        XCTAssertNil(round.tap(round.target, at: start))
        XCTAssertEqual(round.timeLeft(at: start), CoordinateRound.duration)
        round.start(at: start)
        XCTAssertTrue(round.isRunning(at: start + 29.9))
        XCTAssertEqual(round.timeLeft(at: start + 10), 20, accuracy: 0.001)
        XCTAssertNil(round.tap(round.target, at: start + 30))
        XCTAssertFalse(round.isRunning(at: start + 30))
        XCTAssertEqual(round.score, 0)
    }

    func testARightTapScoresAndTheNextNameComesAtOnce() {
        var round = CoordinateRound(side: .white, seed: 3)
        round.start(at: start)
        let target = round.target
        let upcoming = round.upcoming
        XCTAssertEqual(round.tap(target, at: start + 1), .right)
        XCTAssertEqual(round.score, 1)
        XCTAssertEqual(round.target, upcoming, "The name shown small comes next")
        XCTAssertNotEqual(round.upcoming, round.target)
        XCTAssertNotEqual(round.upcoming, target)
    }

    func testAWrongTapOnlyCostsTime() {
        var round = CoordinateRound(side: .white, seed: 5)
        round.start(at: start)
        let target = round.target
        let wrong: Square = target == .a1 ? .h8 : .a1
        XCTAssertEqual(round.tap(wrong, at: start + 1), .wrong)
        XCTAssertEqual(round.score, 0)
        XCTAssertEqual(round.misses, 1)
        XCTAssertEqual(round.target, target, "The same square is still asked for")
        XCTAssertEqual(round.mixUps, [CoordinateRound.MixUp(asked: target, tapped: wrong)])
    }

    func testNoSquareIsAskedTwiceInARow() {
        var round = CoordinateRound(side: .black, seed: 9)
        round.start(at: start)
        var asked: Set<Square> = []
        for _ in 0..<500 {
            let before = round.target
            asked.insert(before)
            XCTAssertNotEqual(round.upcoming, before)
            round.tap(before, at: start + 1)
            XCTAssertNotEqual(round.target, before)
        }
        XCTAssertEqual(asked.count, 64, "Every square comes up")
    }

    func testAccuracyAndTheSquareMostOftenMixedUp() {
        var round = CoordinateRound(side: .white, seed: 11)
        round.start(at: start)
        XCTAssertNil(round.accuracy)
        let first = round.target
        round.tap(first == .a1 ? .b1 : .a1, at: start + 1)
        round.tap(first == .c3 ? .c4 : .c3, at: start + 1)
        round.tap(first, at: start + 1)
        let second = round.target
        round.tap(second == .h8 ? .g8 : .h8, at: start + 1)
        round.tap(second, at: start + 1)
        XCTAssertEqual(round.score, 2)
        XCTAssertEqual(round.misses, 3)
        XCTAssertEqual(round.accuracy, 40)
        XCTAssertEqual(round.worstMixUp?.asked, first, "Missed twice")
    }
}

/// The record behind the vision doors: bests per side and per mode, and the recent scans.
@MainActor
final class VisionStoreTests: XCTestCase {

    func testANewPlayerSeesWhatIsInside() async throws {
        let store = VisionStore()
        XCTAssertEqual(store.status, "Know every square. Scan every position.")
        XCTAssertNil(store.coordinatesStatus)
        XCTAssertNil(store.scanStatus)
        XCTAssertEqual(store.coordinatesBest(as: .white), 0)
    }

    func testCoordinatesKeepABestForEachSide() async throws {
        let store = VisionStore()
        XCTAssertTrue(store.finishCoordinates(score: 12, as: .white))
        XCTAssertFalse(store.finishCoordinates(score: 10, as: .white))
        XCTAssertFalse(store.finishCoordinates(score: 12, as: .white), "A tie isn't a new best")
        XCTAssertTrue(store.finishCoordinates(score: 15, as: .black))
        XCTAssertEqual(store.coordinatesBest(as: .white), 12)
        XCTAssertEqual(store.coordinatesBest(as: .black), 15)
        XCTAssertEqual(store.record.coordinateRounds, 4)
        XCTAssertEqual(store.coordinatesStatus, "Best 15")
        XCTAssertEqual(store.status, "Best 15 squares")
    }

    func testScansKeepABestForEachMode() async throws {
        let store = VisionStore()
        XCTAssertTrue(store.finishScan(BoardScan.Summary(found: 20, total: 22, slips: 1, seconds: 4), mode: .mixed, puzzles: ["a", "b"]))
        XCTAssertFalse(store.finishScan(BoardScan.Summary(found: 18, total: 22, slips: 0, seconds: 2), mode: .mixed, puzzles: ["c"]))
        let quicker = BoardScan.Summary(found: 20, total: 22, slips: 1, seconds: 3)
        XCTAssertTrue(store.finishScan(quicker, mode: .mixed, puzzles: ["d"]))
        XCTAssertEqual(store.scanBest(.mixed), quicker)
        XCTAssertNil(store.scanBest(.checks))
        XCTAssertEqual(store.record.scanRounds, 3)
        XCTAssertEqual(store.recentScans, ["a", "b", "c", "d"])
        XCTAssertEqual(store.scanStatus, "Best 87%")
        XCTAssertEqual(store.status, "Scan best 87%")
        store.finishCoordinates(score: 23, as: .white)
        XCTAssertEqual(store.status, "Best 23 squares · scan 87%")
    }

    func testOnlyTheLatestScansAreRemembered() async throws {
        let store = VisionStore()
        let ids = (0..<350).map { "p\($0)" }
        store.finishScan(BoardScan.Summary(found: 1, total: 1, slips: 0, seconds: 1), mode: .checks, puzzles: ids)
        XCTAssertEqual(store.record.recentScans, Array(ids.suffix(VisionStore.recentLimit)))
    }

    func testTheRecordIsSavedAfterEachRound() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vision-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = VisionStore(fileURL: url)
        store.finishCoordinates(score: 9, as: .black)
        store.finishScan(BoardScan.Summary(found: 5, total: 6, slips: 1, seconds: 3.5), mode: .threats, puzzles: ["x"])
        let saved = try JSONDecoder().decode(VisionRecord.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved, store.record)
        XCTAssertEqual(saved.coordinatesBlack, 9)
        XCTAssertEqual(saved.scans["threats"], BoardScan.Summary(found: 5, total: 6, slips: 1, seconds: 3.5))
    }

    func testAnOlderRecordStillLoads() async throws {
        let empty = try JSONDecoder().decode(VisionRecord.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, VisionRecord())
        let json = #"{"coordinatesWhite": 14, "scans": {"checks": {"found": 3, "total": 4}}}"#
        let old = try JSONDecoder().decode(VisionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(old.coordinatesWhite, 14)
        XCTAssertEqual(old.coordinatesBlack, 0)
        XCTAssertEqual(old.scans["checks"], BoardScan.Summary(found: 3, total: 4, slips: 0, seconds: 0))
        XCTAssertEqual(old.recentScans, [])
    }
}

/// The coordinates drill: the countdown, the round, the flashes, and the bests.
@MainActor
final class CoordinatesDrillTests: XCTestCase {

    func testARoundScoresFlashesAndSavesTheBest() async throws {
        let store = VisionStore()
        let drill = CoordinatesDrill(store: store, side: .white, seed: 7)
        defer { drill.stop() }
        drill.play()
        XCTAssertEqual(drill.phase, .playing)
        for _ in 0..<3 {
            drill.tap(drill.round.target)
        }
        let asked = drill.round.target
        let wrong: Square = asked == .a1 ? .h8 : .a1
        drill.tap(wrong)
        XCTAssertEqual(drill.round.score, 3)
        XCTAssertEqual(drill.flashes.map(\.right), [true, true, true, false])
        XCTAssertEqual(drill.flashes.last?.square, wrong)

        drill.finish()
        XCTAssertEqual(drill.phase, .finished)
        XCTAssertTrue(drill.newBest)
        XCTAssertTrue(drill.flashes.isEmpty)
        XCTAssertEqual(store.coordinatesBest(as: .white), 3)
        XCTAssertEqual(drill.best, 3)
        XCTAssertEqual(drill.message(sideName: "Ivory"),
                       "3 squares: your first score as Ivory. Now beat it. Watch \(asked.notation): you tapped \(wrong.notation).")
    }

    func testALowerScoreIsNotABest() async throws {
        var record = VisionRecord()
        record.coordinatesBlack = 20
        let store = VisionStore(record: record)
        let drill = CoordinatesDrill(store: store, side: .black, seed: 2)
        defer { drill.stop() }
        drill.play()
        drill.tap(drill.round.target)
        drill.finish()
        XCTAssertFalse(drill.newBest)
        XCTAssertEqual(drill.previousBest, 20)
        XCTAssertEqual(store.coordinatesBest(as: .black), 20)
        XCTAssertEqual(drill.message(sideName: "Onyx"), "1 square. Your best as Onyx is 20.")
    }

    func testTheSideChangesOnlyBetweenRounds() async throws {
        let drill = CoordinatesDrill(store: VisionStore(), side: .white, seed: 4)
        defer { drill.stop() }
        drill.choose(.black)
        XCTAssertEqual(drill.side, .black)
        XCTAssertEqual(drill.round.side, .black)
        drill.play()
        drill.choose(.white)
        XCTAssertEqual(drill.side, .black, "Not in the middle of a round")
        drill.finish()
        drill.choose(.white)
        XCTAssertEqual(drill.side, .white)
        XCTAssertEqual(drill.phase, .ready)
    }

    func testTapsCountOnlyWhilePlaying() async throws {
        let drill = CoordinatesDrill(store: VisionStore(), seed: 5)
        defer { drill.stop() }
        drill.tap(drill.round.target)
        XCTAssertEqual(drill.round.score, 0)
        XCTAssertTrue(drill.flashes.isEmpty)
        XCTAssertEqual(drill.message(sideName: "Ivory"),
                       "I name a square, you tap it. No labels on the board, thirty seconds on the clock.")
    }

    func testTheCountdownLeadsIntoTheRound() async throws {
        let drill = CoordinatesDrill(store: VisionStore(), seed: 6)
        defer { drill.stop() }
        drill.start()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(drill.phase, .countdown(3))
        try await Task.sleep(for: .milliseconds(2_500))
        XCTAssertEqual(drill.phase, .playing)
        XCTAssertTrue(drill.round.isRunning(at: .now))
    }

    func testTheRoundEndsWhenTimeIsUp() async throws {
        let store = VisionStore()
        let drill = CoordinatesDrill(store: store, seed: 8)
        defer { drill.stop() }
        drill.play(at: Date.now.addingTimeInterval(-29.6))
        drill.tap(drill.round.target)
        try await Task.sleep(for: .milliseconds(1_000))
        XCTAssertEqual(drill.phase, .finished)
        XCTAssertEqual(store.coordinatesBest(as: .white), 1)
    }
}

/// The board scan's round: their move, the taps, the reveal, the totals and the coach's lines.
@MainActor
final class BoardScanRunnerTests: XCTestCase {

    func testAScanFindsSlipsAndReveals() async throws {
        let store = VisionStore()
        let sounds = SilentSounds()
        let threats = try XCTUnwrap(BoardScan.Exercise(puzzle: VisionSample.puzzle("UGlI7"), kind: .threats))
        let checks = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .checks))
        let runner = try XCTUnwrap(BoardScanRunner(mode: .mixed, exercises: [threats, checks], store: store, sounds: sounds))
        defer { runner.cancel() }
        XCTAssertEqual(runner.phase, .intro)
        runner.tap(.d5)
        XCTAssertTrue(runner.attempt.found.isEmpty, "No taps before the scan starts")

        runner.begin(animated: false)
        XCTAssertEqual(runner.phase, .scanning)
        XCTAssertEqual(TrainingChess.key(runner.game.board.position.fen), TrainingChess.key(threats.fen))
        XCTAssertEqual(runner.message, BoardScan.Kind.threats.instruction)
        XCTAssertEqual(runner.remaining, 2)

        let start = Date.now
        runner.tap(.d5, at: start)
        runner.tap(.a8, at: start)
        runner.tap(.d5, at: start)
        XCTAssertEqual(runner.foundTaps, 1)
        XCTAssertEqual(runner.slipTaps, 1)
        XCTAssertEqual(runner.remaining, 1)
        XCTAssertTrue(runner.arrows.isEmpty, "Nothing is shown before the reveal")

        runner.done(at: start.addingTimeInterval(4.2))
        XCTAssertEqual(runner.phase, .revealed)
        XCTAssertEqual(runner.attempt.seconds ?? 0, 4.2, accuracy: 0.3)
        XCTAssertEqual(runner.arrows, [BoardArrow(from: "f4", to: "g5", color: .orange, dashed: true)])
        XCTAssertEqual(runner.message, "1 of 2. You missed your queen on g5.")
        XCTAssertEqual(runner.tone, .wrong)
        XCTAssertEqual(runner.outcomes, [.afterMistake])

        runner.next()
        XCTAssertEqual(runner.index, 1)
        XCTAssertEqual(runner.phase, .scanning)
        runner.tap(.e8)
        runner.tap(.h4, at: Date.now.addingTimeInterval(2))
        XCTAssertEqual(runner.phase, .revealed, "Finding the last one reveals the position")
        XCTAssertEqual(runner.tone, .success)
        XCTAssertTrue(runner.message.hasPrefix("All 2 found in 2."), runner.message)
        XCTAssertTrue(runner.isLast)

        runner.next()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.summary?.found, 3)
        XCTAssertEqual(runner.summary?.total, 4)
        XCTAssertEqual(runner.summary?.slips, 1)
        XCTAssertEqual(runner.summary?.percent, 60)
        XCTAssertTrue(runner.newBest)
        XCTAssertEqual(store.scanBest(.mixed), runner.summary)
        XCTAssertEqual(store.recentScans, ["UGlI7", "rook"])
        XCTAssertEqual(runner.message, "You found 3 of 4. Checks, captures, threats: every position, every move.")
        XCTAssertEqual(runner.tone, .coach)
        XCTAssertTrue(sounds.played.isEmpty, "Not animated: their move is set up without a sound")
    }

    func testTheirMoveIsPlayedBeforeTheScan() async throws {
        let sounds = SilentSounds()
        let exercise = try XCTUnwrap(BoardScan.Exercise(puzzle: VisionSample.puzzle("UGlI7"), kind: .checks))
        let runner = try XCTUnwrap(BoardScanRunner(mode: .checks, exercises: [exercise], store: nil, sounds: sounds))
        defer { runner.cancel() }
        runner.begin()
        XCTAssertEqual(runner.phase, .intro)
        XCTAssertEqual(TrainingChess.key(runner.game.board.position.fen), TrainingChess.key(exercise.startFEN))
        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(runner.phase, .scanning)
        XCTAssertEqual(sounds.played, [.move])
        XCTAssertEqual(runner.game.lastMove, LastMove(from: .f2, to: .f4))
        XCTAssertEqual(TrainingChess.key(runner.game.board.position.fen), TrainingChess.key(exercise.fen))
    }

    func testAPerfectRound() async throws {
        let store = VisionStore()
        let exercise = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .checks))
        let runner = try XCTUnwrap(BoardScanRunner(mode: .checks, exercises: [exercise], store: store, sounds: nil))
        runner.begin(animated: false)
        runner.tap(.h4)
        runner.tap(.e8)
        XCTAssertEqual(runner.outcomes, [.firstTry])
        XCTAssertTrue(runner.message.hasSuffix("Clean scan."), runner.message)
        runner.next()
        XCTAssertEqual(runner.summary?.percent, 100)
        XCTAssertEqual(runner.tone, .success)
        XCTAssertEqual(runner.message, "A perfect scan. That's how strong players look at every position.")
        XCTAssertEqual(store.scanStatus, "Best 100%")
    }

    func testDoneWithNothingFound() async throws {
        let exercise = try XCTUnwrap(BoardScan.Exercise(id: "rook", startFEN: VisionSample.rookFEN, kind: .checks))
        let runner = try XCTUnwrap(BoardScanRunner(mode: .checks, exercises: [exercise], store: nil, sounds: nil))
        runner.begin(animated: false)
        runner.done()
        XCTAssertEqual(runner.outcomes, [.missed])
        XCTAssertEqual(runner.message, "You missed Rh4+ and Re8+.")
        XCTAssertEqual(runner.arrows.count, 2)
        runner.tap(.e8)
        XCTAssertTrue(runner.attempt.found.isEmpty, "No taps once it's revealed")
    }

    func testNoRoundWithoutPositions() async throws {
        XCTAssertNil(BoardScanRunner(mode: .mixed, exercises: [], store: nil, sounds: nil))
    }
}

/// Puzzles, positions and records the board vision tests share.
enum VisionSample {
    /// The pack puzzles behind the real positions in the hand-picked cases, in the order a
    /// round of Mixed starting with checks can use them.
    static let puzzles: [LichessPuzzle] = [
        LichessPuzzle(id: "DcYxb", fen: "rnb1k1nr/ppp2ppp/5q2/2b1p1B1/4P3/2N2N2/PPP2PPP/R2QKB1R b KQkq - 3 6",
                      moves: ["f6b6", "d1d8"], rating: 495, themes: ["mateIn1", "opening"]),
        LichessPuzzle(id: "UGlI7", fen: "r3k1nr/ppp2ppp/8/3pP1q1/2P1p3/2P1P2b/P3BPPP/R1BQ1RK1 w kq - 5 11",
                      moves: ["f2f4", "g5g2"], rating: 406, themes: ["kingsideAttack", "mateIn1", "middlegame"]),
        LichessPuzzle(id: "ariqG", fen: "k2r4/p1R1N3/Kp3p2/1P5p/5Q2/q7/7N/8 w - - 1 39",
                      moves: ["f4a4", "a3a4"], rating: 439, themes: ["endgame", "hangingPiece", "mateIn1"]),
        LichessPuzzle(id: "Ha4wN", fen: "2r5/pRrnbkp1/4p2p/3n2B1/3NN3/8/P4PPP/1R4K1 w - - 0 25",
                      moves: ["g5e7", "c7c1", "b1c1", "c8c1"], rating: 577, themes: ["backRankMate", "mateIn2", "middlegame"]),
        LichessPuzzle(id: "esNlI", fen: "2r3k1/p2qp1bp/3pN3/3Pn2P/8/1P5K/1BQ2R2/5R2 b - - 0 30",
                      moves: ["c8c2", "f2f8", "g7f8", "f1f8"], rating: 584, themes: ["mateIn2", "middlegame", "sacrifice"]),
        LichessPuzzle(id: "HUnMK", fen: "8/6k1/4R2p/6p1/r5K1/7P/6P1/8 w - - 5 46",
                      moves: ["g4h5", "a4h4"], rating: 493, themes: ["endgame", "mateIn1", "rookEndgame"]),
        LichessPuzzle(id: "0YPDM", fen: "k5r1/pp3Q2/1p6/1q6/1P6/8/Pb2RPP1/5KNr b - - 1 32",
                      moves: ["g8e8", "f7e8", "b5e8", "e2e8"], rating: 448, themes: ["backRankMate", "mateIn2", "middlegame"]),
        LichessPuzzle(id: "dAuJi", fen: "r1b2rk1/1pqpbppp/p1n4B/3pP3/1P4Q1/2P2N2/P4PPP/RN3RK1 b - - 4 13",
                      moves: ["c6e5", "g4g7"], rating: 588, themes: ["kingsideAttack", "mateIn1", "opening"]),
    ]

    /// A rook that can check on e8 and h4, and is attacked by a pawn though defended.
    static let rookFEN = "7k/8/8/3p4/4R3/5P2/8/4K3 w - - 0 1"

    static func puzzle(_ id: String) -> LichessPuzzle {
        puzzles.first { $0.id == id } ?? puzzles[0]
    }

    /// The whole bundled pack.
    static func pack() throws -> PuzzleLibrary {
        try XCTUnwrap(PuzzleLibrary.bundled(), "lichess-puzzles.csv isn't in the app")
    }

    /// Eight positions of Mixed, checks first, from the puzzles above.
    static func mixedRound() -> [BoardScan.Exercise] {
        zip(puzzles, BoardScan.Mode.mixed.kinds(count: puzzles.count)).compactMap { puzzle, kind in
            BoardScan.Exercise(puzzle: puzzle, kind: kind)
        }
    }

    /// A player a few rounds in.
    @MainActor
    static func store() -> VisionStore {
        var record = VisionRecord()
        record.coordinatesWhite = 5
        record.coordinatesBlack = 17
        record.coordinateRounds = 6
        record.scans = [
            BoardScan.Mode.checks.rawValue: BoardScan.Summary(found: 21, total: 22, slips: 0, seconds: 3.1),
            BoardScan.Mode.mixed.rawValue: BoardScan.Summary(found: 19, total: 23, slips: 2, seconds: 4.6),
        ]
        record.scanRounds = 4
        return VisionStore(record: record)
    }
}

// MARK: - Pictures of the screens

/// The coordinates drill and the board scan at iPhone size in their main states, and on a
/// small iPhone. When SNAPSHOT_DIR is set the pictures are saved there.
@MainActor
final class BoardVisionSnapshotTests: XCTestCase {
    private let theme = BoardTheme.named(.gilded)
    private let small = CGSize(width: 375, height: 667)

    override func setUp() async throws {
        ThemeFont.use(theme)
    }

    func testCoordinatesScreens() throws {
        let store = VisionSample.store()

        let ready = CoordinatesDrill(store: store, side: .white, seed: 21)
        var window = try show(CoordinatesView(theme: theme, drill: ready))
        try save(window, "train-coordinates-1-ready")
        window.isHidden = true

        let counting = CoordinatesDrill(store: store, side: .black, seed: 22)
        window = try show(CoordinatesView(theme: theme, drill: counting), wait: 1)
        counting.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try save(window, "train-coordinates-2-countdown")
        counting.stop()
        window.isHidden = true

        let playing = CoordinatesDrill(store: store, side: .white, seed: 23)
        playing.play(at: Date.now.addingTimeInterval(-11))
        window = try show(CoordinatesView(theme: theme, drill: playing), wait: 1)
        for _ in 0..<6 {
            playing.tap(playing.round.target)
        }
        playing.tap(playing.round.target == .c6 ? .c3 : .c6)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        try save(window, "train-coordinates-3-playing")

        playing.finish()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        try save(window, "train-coordinates-4-finished")
        playing.stop()
        window.isHidden = true

        let smallReady = CoordinatesDrill(store: store, side: .black, seed: 24)
        window = try show(CoordinatesView(theme: theme, drill: smallReady), size: small)
        try save(window, "train-coordinates-5-small-ready")
        window.isHidden = true

        let smallPlaying = CoordinatesDrill(store: store, side: .black, seed: 25)
        smallPlaying.play(at: Date.now.addingTimeInterval(-26))
        window = try show(CoordinatesView(theme: theme, drill: smallPlaying), size: small, wait: 1)
        try save(window, "train-coordinates-6-small-playing")
        smallPlaying.stop()
        window.isHidden = true
    }

    func testBoardScanScreens() throws {
        let defaults = UserDefaults.standard
        let savedMode = defaults.object(forKey: "visionScanMode")
        defer {
            if let savedMode { defaults.set(savedMode, forKey: "visionScanMode") } else { defaults.removeObject(forKey: "visionScanMode") }
        }
        defaults.set(BoardScan.Mode.mixed.rawValue, forKey: "visionScanMode")
        let store = VisionSample.store()
        let puzzles = PuzzleStore(library: PuzzleLibrary(puzzles: VisionSample.puzzles))
        let round = VisionSample.mixedRound()
        XCTAssertEqual(round.count, 8)

        var window = try show(BoardScanView(theme: theme, store: store, runner: nil).environment(puzzles))
        try save(window, "train-scan-1-start")
        window.isHidden = true

        // DcYxb, checks: Qd8 found, a slip on h5; Bb5 and Qd7 still to find.
        let runner = try XCTUnwrap(BoardScanRunner(mode: .mixed, exercises: round, store: store, sounds: nil))
        runner.begin(animated: false)
        let start = Date.now
        runner.tap(.d8, at: start)
        runner.tap(.h5, at: start)
        window = try show(BoardScanView(theme: theme, store: store, runner: runner).environment(puzzles))
        try save(window, "train-scan-2-scanning")

        runner.done(at: start.addingTimeInterval(6.4))
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        try save(window, "train-scan-3-revealed")

        runner.next()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        try save(window, "train-scan-4-next-kind")

        Self.finishRound(runner)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        try save(window, "train-scan-5-finished")
        window.isHidden = true

        let smallRunner = try XCTUnwrap(BoardScanRunner(mode: .mixed, exercises: round, store: store, sounds: nil))
        smallRunner.begin(animated: false)
        smallRunner.tap(.b5)
        window = try show(BoardScanView(theme: theme, store: store, runner: smallRunner).environment(puzzles), size: small)
        try save(window, "train-scan-6-small")
        window.isHidden = true

        let neon = BoardTheme.named(.neon)
        ThemeFont.use(neon)
        let neonRunner = try XCTUnwrap(BoardScanRunner(mode: .mixed, exercises: round, store: store, sounds: nil))
        neonRunner.begin(animated: false)
        neonRunner.tap(.d7)
        neonRunner.tap(.a1)
        neonRunner.done()
        window = try show(BoardScanView(theme: neon, store: store, runner: neonRunner).environment(puzzles))
        try save(window, "train-scan-7-neon-revealed")
        window.isHidden = true
        ThemeFont.use(theme)
    }

    /// Plays the rest of a round: most squares found a few seconds apart, one missed, one slip.
    private static func finishRound(_ runner: BoardScanRunner) {
        while runner.phase != .finished {
            let start = Date.now
            let targets = runner.exercise.targets
            let found = runner.index == 4 ? Array(targets.dropLast()) : targets
            if runner.index == 6, let slip = Square.allCases.first(where: { runner.exercise.target(on: $0) == nil }) {
                runner.tap(slip, at: start)
            }
            for (step, target) in found.enumerated() {
                runner.tap(target.square, at: start.addingTimeInterval(2.2 + Double(step) * 1.3))
            }
            runner.done(at: start.addingTimeInterval(7))
            runner.next()
        }
    }

    // MARK: Drawing

    private func show(_ view: some View, size: CGSize? = nil, wait: TimeInterval = 2) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
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
