import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Real positions from the puzzle pack, with Stockfish 18's best lines for them.
enum ThinkSample {
    /// Black castles into a skewer; the winner is the quiet Bf4.
    static let skewer = LichessPuzzle(id: "abgJu", fen: "r3k2r/p2b1ppp/2pbp3/3pq3/8/4B1P1/P1Q1BP1P/1R3RK1 b kq - 0 16",
                                      moves: ["e8g8", "e3f4", "e5f6", "f4d6"], rating: 1393, themes: ["middlegame", "skewer"])
    static let skewerLines = [
        EngineLine(moves: ["e3f4", "e5f6", "f4d6", "f8e8"], evaluation: .centipawns(290)),
        EngineLine(moves: ["b1b7", "d7c8", "b7b3"], evaluation: .centipawns(-93)),
        EngineLine(moves: ["e2d3", "e5h5", "b1b7"], evaluation: .centipawns(-237)),
        EngineLine(moves: ["f1c1", "e5f6", "b1b7"], evaluation: .centipawns(-281)),
    ]

    /// The winner takes with check: Bxf6+.
    static let fork = LichessPuzzle(id: "RoFxT", fen: "1rb4r/2p1qpk1/1b3n2/1p2n1B1/3p4/1BP3QP/1P4P1/RN3R1K b - - 1 21",
                                    moves: ["e5g4", "g5f6", "e7f6", "f1f6"], rating: 1564, themes: ["fork", "middlegame", "pin"])
    static let forkLines = [
        EngineLine(moves: ["g5f6", "e7f6", "f1f6"], evaluation: .centipawns(397)),
        EngineLine(moves: ["f1f3", "f6h5"], evaluation: .centipawns(-83)),
        EngineLine(moves: ["f1f6", "g4f6"], evaluation: .centipawns(-138)),
        EngineLine(moves: ["b1d2", "f6h5"], evaluation: .centipawns(-166)),
    ]

    /// A back-rank mate in two: Qxe8+.
    static let backRank = LichessPuzzle(id: "HH2kL", fen: "4r1k1/1pq2ppp/8/2b5/Q2Nr3/2P3Pb/PP1B1P1P/3RR1K1 b - - 6 21",
                                        moves: ["c5d4", "a4e8", "e4e8", "e1e8"], rating: 1517,
                                        themes: ["backRankMate", "mateIn2", "middlegame", "xRayAttack"])
    static let backRankLines = [
        EngineLine(moves: ["a4e8", "e4e8", "e1e8"], evaluation: .mate(2)),
        EngineLine(moves: ["e1e4", "e8e4"], evaluation: .centipawns(22)),
        EngineLine(moves: ["c3d4", "h7h6"], evaluation: .centipawns(19)),
        EngineLine(moves: ["b2b3", "e4e1"], evaluation: .centipawns(-440)),
    ]

    /// Mates in one from 400 to 2400, for the level check.
    static let mates = PuzzleLibrary(csv: """
    id,fen,moves,rating,themes
    UGlI7,r3k1nr/ppp2ppp/8/3pP1q1/2P1p3/2P1P2b/P3BPPP/R1BQ1RK1 w kq - 5 11,f2f4 g5g2,406,kingsideAttack mateIn1 middlegame
    EorD7,k1rq2nr/p3b3/PpR2p1p/3Q4/3P1B2/5N2/1P3PPP/R5K1 b - - 0 21,d8d5 c6c8,450,hangingPiece mateIn1 middlegame queensideAttack
    indnJ,2kr3r/1bpn3p/5pp1/1N1Pp3/4P3/8/2Q3PP/q4RK1 b - - 1 31,a1a6 c2c7,601,mateIn1 middlegame queensideAttack
    ARAML,r2q2kr/pppb2pp/4pn2/1B1pQ3/P2P4/B1P5/2P2PPP/R3K2R b KQ - 0 13,d7b5 e5e6,750,kingsideAttack mateIn1 middlegame
    27cr8,1kr4r/pp3p2/4p2n/2NpPn1p/1P3Ppq/P2B4/3Q2PP/R4RBK w - - 5 23,d2c2 f5g3,900,mateIn1 middlegame pin smotheredMate
    NVbPd,5rk1/pp4pp/2p5/3P2b1/3Pp1n1/1PQ1P1Pb/P3B2P/R3BqK1 w - - 0 26,e2f1 f8f1,1050,kingsideAttack mateIn1 middlegame
    aPwpC,kr3b1r/P1Q5/1p2pq2/3p3p/1p1P4/2P5/5PP1/RN2K2R b KQ - 0 30,f8h6 a7b8q,1202,advancedPawn doubleCheck mateIn1 middlegame promotion queensideAttack
    827Xy,3r4/5p2/4k2R/2ppP3/8/3BK3/5PP1/r7 b - - 1 44,e6e5 f2f4,1357,endgame mateIn1
    K3l1I,4r3/p1p4p/8/2p1rkp1/R3p1P1/4R2P/PP2K3/8 b - - 0 36,f5f4 e3f3,1500,endgame mateIn1 pin rookEndgame
    dMZQ8,r3k1nr/4pp1p/p2p2pb/1pp5/2PnP3/1PqP1bPP/PR1N1PB1/2BKQ2R w kq - 0 16,d2f3 c3c1,1657,mateIn1 opening
    cd0ni,r1b1k1nr/pppp2pp/5p2/4n3/1b2q3/2P2NP1/PB1PP2P/RN1QKB1R w KQkq - 0 8,c3b4 e5d3,1800,mateIn1 opening pin
    kl1hQ,5rk1/3p2pp/bq2p3/3NP3/p2b1p2/5QP1/PP3rBP/1RB1R1K1 w - - 0 24,d5b6 f2f1,1951,doubleCheck mateIn1 middlegame
    48128,7r/3b1p2/3pn2r/p1bBk3/1p2P2N/3P2P1/PP4K1/2R2R2 b - - 1 36,f7f6 h4f3,2100,mateIn1 middlegame
    2c4bk,rn2k2r/pQp1nppp/3q4/8/2Bb4/8/PP1N2PP/R1BKR3 b kq - 5 14,d6c6 b7c8,2254,mateIn1 opening pin
    0jbFz,8/pBP3q1/1pRkb3/3N1p2/3P2p1/P2KP1P1/r7/8 b - - 3 30,d6d5 c6b6,2421,discoveredAttack endgame mateIn1
    """).puzzles

    /// The position a puzzle is solved from, after the opponent's move.
    static func position(of puzzle: LichessPuzzle) -> String {
        TrainingChess.fen(after: [puzzle.moves[0]], from: puzzle.fen) ?? puzzle.fen
    }

    /// An engine that knows the skewer position, and the queen blunder Qxc6 in it.
    static func skewerEngine() -> FakeEngine {
        let fen = position(of: skewer)
        let afterQxc6 = TrainingChess.fen(after: ["c2c6"], from: fen) ?? ""
        return FakeEngine(scripted: [
            fen: skewerLines,
            afterQxc6: [EngineLine(moves: ["d7c6", "f1c1"], evaluation: .centipawns(663))],
        ])
    }

    /// Names a move on the candidates board: the piece, then where it goes.
    @MainActor
    static func name(_ runner: CandidateRunner, _ uci: String) {
        guard let squares = Notation.squares(of: uci) else { return }
        runner.tap(squares.from)
        runner.tap(squares.to)
    }
}

/// A repeatable random number generator (SplitMix64), so simulated players answer the same way every run.
struct ThinkSeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The thinking drills: Leo's verdicts on a list of candidate moves, the round
/// score, the level check's estimate, and what gets saved.
@MainActor
final class ThinkTests: XCTestCase {

    private var skewerFEN: String { ThinkSample.position(of: ThinkSample.skewer) }

    // MARK: Verdicts and scoring

    func testVerdictsAreWordsNotNumbers() {
        XCTAssertEqual(CandidateVerdict(.mate(3)), .mates)
        XCTAssertEqual(CandidateVerdict(.mate(-2)), .allowsMate)
        XCTAssertEqual(CandidateVerdict(.centipawns(290)), .wins)
        XCTAssertEqual(CandidateVerdict(.centipawns(120)), .edge)
        XCTAssertEqual(CandidateVerdict(.centipawns(-40)), .equal)
        XCTAssertEqual(CandidateVerdict(.centipawns(-93)), .worse)
        XCTAssertEqual(CandidateVerdict(.centipawns(-663)), .losesMaterial)
        XCTAssertEqual(CandidateVerdict.edge.words, "keeps an edge")
        XCTAssertEqual(CandidateVerdict.equal.words, "about equal")
        XCTAssertEqual(CandidateVerdict.losesMaterial.words, "loses material")
        XCTAssertGreaterThan(CandidateVerdict.wins, .edge)
        XCTAssertEqual(CandidateVerdict.allCases.map(\.color), [.red, .red, .orange, nil, nil, .green, .green],
                       "Green wins, plain text is playable, orange and red hurt")
        for verdict in CandidateVerdict.allCases {
            XCTAssertFalse(verdict.words.contains(where: \.isNumber), verdict.words)
        }
    }

    func testTheWinnerAsTheSecondCandidate() {
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["b1b7", "e3f4", "c2c6"],
                                           lines: ThinkSample.skewerLines, extra: ["c2c6": .centipawns(-663)])
        XCTAssertEqual(report.foundAt, 1)
        XCTAssertEqual(report.otherMatches, 1, "Rb7 is in Leo's top three; Qxc6 isn't")
        XCTAssertEqual(report.points, 3)
        XCTAssertEqual(report.takeaway, "You found it as your second candidate: always list more than one.")
        XCTAssertEqual(report.rows.map(\.san), ["Bf4", "Rb7", "Bd3", "Qxc6"], "The winner, then strongest to weakest")
        XCTAssertEqual(report.rows.map(\.verdict), [.wins, .worse, .worse, .losesMaterial])
        XCTAssertEqual(report.rows.map(\.listed), [1, 0, nil, 2])
        XCTAssertEqual(report.rows.map(\.leoRank), [0, 1, 2, nil])
        XCTAssertEqual(report.rows.map(\.isMatch), [true, true, false, false])
        XCTAssertEqual(report.winner?.uci, "e3f4")
    }

    func testTheWinnerFirstWithTwoMoreOfLeosTopThreeScoresTheMost() {
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["e3f4", "b1b7", "e2d3"],
                                           lines: ThinkSample.skewerLines)
        XCTAssertEqual(report.foundAt, 0)
        XCTAssertEqual(report.points, CandidateJudge.maxPoints)
        XCTAssertEqual(report.takeaway, "Your first idea, Bf4, wins. Weighing the others is what makes it safe.")
        XCTAssertEqual(report.rows.count, 3)
    }

    func testOneCandidateThatWins() {
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["e3f4"], lines: ThinkSample.skewerLines)
        XCTAssertEqual(report.points, 3)
        XCTAssertEqual(report.takeaway, "You saw Bf4 at once. Still list two or three moves; it's the habit that counts.")
    }

    func testAMissedWinnerSaysWhereToLook() {
        let quiet = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["b1b7"], lines: ThinkSample.skewerLines)
        XCTAssertNil(quiet.foundAt)
        XCTAssertEqual(quiet.points, 1, "Rb7 is still one of Leo's top three")
        XCTAssertEqual(quiet.takeaway, "The winner was the quiet Bf4. After checks and captures, look for threats.")
        XCTAssertEqual(quiet.rows.first?.isWinner, true)

        let forcing = CandidateJudge.report(fen: ThinkSample.position(of: ThinkSample.fork), winner: "g5f6",
                                            candidates: ["f1f3"], lines: ThinkSample.forkLines)
        XCTAssertEqual(forcing.takeaway, "The winner was Bxf6+. Look at every check and capture before anything else.")
        XCTAssertEqual(forcing.rows.first?.verdict, .wins)
    }

    func testWithoutAnEngineOnlyTheWinnerCounts() {
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["b1b7", "e3f4"], lines: [])
        XCTAssertFalse(report.usedEngine)
        XCTAssertEqual(report.rows.map(\.san), ["Bf4"], "Nothing is said about the other candidates")
        XCTAssertEqual(report.rows.first?.verdict, .wins)
        XCTAssertEqual(report.otherMatches, 0)
        XCTAssertEqual(report.points, 2)
    }

    func testAMatePuzzlesWinnerMates() {
        let fen = ThinkSample.position(of: ThinkSample.backRank)
        let report = CandidateJudge.report(fen: fen, winner: "a4e8", candidates: ["e1e4", "a4e8"],
                                           lines: ThinkSample.backRankLines, mate: true)
        XCTAssertEqual(report.rows.first?.san, "Qxe8+")
        XCTAssertEqual(report.rows.first?.verdict, .mates)
        XCTAssertEqual(report.rows.dropFirst().first?.verdict, .equal)
        XCTAssertEqual(report.points, 3)
        let alone = CandidateJudge.report(fen: fen, winner: "a4e8", candidates: [], lines: [], mate: true)
        XCTAssertEqual(alone.rows.first?.verdict, .mates)
        XCTAssertEqual(alone.points, 0)
    }

    func testMovesThatEndTheGameNeedNoEngine() {
        let backRank = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        XCTAssertEqual(CandidateJudge.finalEvaluation(of: "a1a8", in: backRank), .mate(1))
        XCTAssertNil(CandidateJudge.finalEvaluation(of: "a1a7", in: backRank))
        XCTAssertEqual(CandidateJudge.finalEvaluation(of: "e7f7", in: "7k/4Q3/6K1/8/8/8/8/8 w - - 0 1"), .centipawns(0),
                       "Stalemate is a draw")
    }

    func testPromotionsOnOneSquareAreOneMove() {
        XCTAssertTrue(CandidateJudge.same("e7e8q", "e7e8n"))
        XCTAssertTrue(CandidateJudge.same("e2e4", "e2e4"))
        XCTAssertFalse(CandidateJudge.same("e7e8q", "e7d8q"))
        XCTAssertFalse(CandidateJudge.same("e2e4", "e2e3"))
    }

    func testARoundAddsUpAndEndsAfterFive() {
        let best = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["e3f4", "b1b7", "e2d3"],
                                         lines: ThinkSample.skewerLines)
        let missed = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["f1c1"], lines: ThinkSample.skewerLines)
        var round = CandidateRound()
        for report in [best, missed, best, missed, best] {
            XCTAssertFalse(round.isFinished)
            round.add(report)
        }
        XCTAssertTrue(round.isFinished)
        XCTAssertEqual(round.points, 15)
        XCTAssertEqual(round.found, 3)
        XCTAssertEqual(round.foundFirst, 3)
        round.add(best)
        XCTAssertEqual(round.reports.count, CandidateRound.length, "A round holds five")
        XCTAssertEqual(round.summary, "Three winners out of five. The habit is working.")
        XCTAssertEqual(CandidateRound.maxPoints, 25)
    }

    // MARK: Picking positions

    private func puzzle(_ id: String, rating: Int, length: Int, themes: [String]) -> LichessPuzzle {
        LichessPuzzle(id: id, fen: "", moves: Array(repeating: "a1a2", count: length * 2), rating: rating, themes: themes)
    }

    func testCandidatePositionsHaveARealChoice() {
        let pool = [
            puzzle("mate", rating: 1400, length: 1, themes: ["mateIn1", "middlegame"]),
            puzzle("short", rating: 1400, length: 1, themes: ["fork", "middlegame"]),
            puzzle("defend", rating: 1400, length: 2, themes: ["defensiveMove", "middlegame"]),
            puzzle("ending", rating: 1400, length: 2, themes: ["endgame"]),
            puzzle("middle", rating: 1900, length: 3, themes: ["fork", "middlegame"]),
        ]
        XCTAssertEqual(pool.map(ThinkPicker.suitsCandidates), [false, false, false, true, true])
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(ThinkPicker.candidatePosition(in: pool, near: 1400, avoid: [], using: &generator)?.id, "middle",
                       "A middlegame first, even a little further away")
        XCTAssertEqual(ThinkPicker.candidatePosition(in: pool, near: 1400, avoid: ["middle"], using: &generator)?.id, "ending")
        XCTAssertEqual(ThinkPicker.candidatePosition(in: pool, near: 1400, avoid: ["middle", "ending"], using: &generator)?.id,
                       "ending", "A repeat rather than nothing")
    }

    func testLevelPuzzlesAreShortAndNearTheTarget() {
        let pool = [
            puzzle("long", rating: 1200, length: 4, themes: []),
            puzzle("short", rating: 1250, length: 1, themes: []),
            puzzle("far", rating: 2000, length: 1, themes: []),
        ]
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(ThinkPicker.levelPuzzle(in: pool, near: 1200, avoid: [], using: &generator)?.id, "short")
        XCTAssertEqual(ThinkPicker.levelPuzzle(in: pool, near: 1200, avoid: ["short"], using: &generator)?.id, "long")
        XCTAssertNil(ThinkPicker.levelPuzzle(in: pool, near: 1200, avoid: ["short", "long", "far"], using: &generator))
    }

    // MARK: The candidates drill

    func testNamingCandidatesNeverMovesAPiece() async throws {
        let runner = try XCTUnwrap(CandidateRunner(puzzle: ThinkSample.skewer, engine: nil, sounds: nil))
        XCTAssertEqual(runner.learner, .white)
        runner.begin()
        await waitUntil("the board is handed over") { runner.phase == .listing }
        let position = runner.game.fen
        XCTAssertEqual(TrainingChess.key(position), TrainingChess.key(runner.fen))

        ThinkSample.name(runner, "b1b7")
        ThinkSample.name(runner, "e3f4")
        XCTAssertEqual(runner.candidates.map(\.san), ["Rb7", "Bf4"])
        XCTAssertEqual(runner.game.fen, position, "The pieces stay where they are")
        XCTAssertNil(runner.game.selected)
        XCTAssertEqual(runner.arrows.count, 2)
        XCTAssertEqual(runner.labels.map(\.text), ["1", "2"])
        XCTAssertEqual(runner.labels.map(\.square), ["b7", "f4"])

        ThinkSample.name(runner, "e3f4")
        XCTAssertEqual(runner.candidates.count, 2, "No move twice")
        XCTAssertEqual(runner.message, "That one's already on your list.")
        ThinkSample.name(runner, "c2c6")
        ThinkSample.name(runner, "e2d3")
        XCTAssertEqual(runner.candidates.map(\.san), ["Rb7", "Bf4", "Qxc6"], "Three at most")
        XCTAssertTrue(runner.message.hasPrefix("Three is plenty"))

        runner.remove(runner.candidates[0])
        XCTAssertEqual(runner.candidates.map(\.san), ["Bf4", "Qxc6"])
        XCTAssertEqual(runner.labels.map(\.text), ["1", "2"], "The list renumbers")
        XCTAssertEqual(runner.game.fen, position)
    }

    func testLeoChecksTheListWithTheEngine() async throws {
        let sounds = SilentSounds()
        let runner = try XCTUnwrap(CandidateRunner(puzzle: ThinkSample.skewer, engine: ThinkSample.skewerEngine(), sounds: sounds))
        var judged: [CandidateReport] = []
        runner.onJudged = { judged.append($0) }
        runner.begin()
        await waitUntil("the board is handed over") { runner.phase == .listing }
        runner.check()
        XCTAssertEqual(runner.phase, .listing, "An empty list isn't checked")

        for move in ["b1b7", "e3f4", "c2c6"] { ThinkSample.name(runner, move) }
        runner.check()
        XCTAssertEqual(runner.phase, .checking)
        await waitUntil("Leo answers") { runner.phase == .judged }
        let report = try XCTUnwrap(runner.report)
        XCTAssertEqual(report.points, 3)
        XCTAssertEqual(report.rows.last?.san, "Qxc6")
        XCTAssertEqual(report.rows.last?.verdict, .losesMaterial, "Judged by a search of its own")
        XCTAssertEqual(runner.message, report.takeaway)
        XCTAssertEqual(runner.tone, .success)
        XCTAssertEqual(judged.count, 1)
        XCTAssertTrue(sounds.played.contains(.win))
        // The winner's arrow turns green; Qxc6, which didn't count, is dashed.
        XCTAssertEqual(runner.arrows.first { $0.from == "e3" }?.color, .green)
        XCTAssertEqual(runner.arrows.first { $0.from == "c2" }?.dashed, true)
        XCTAssertEqual(runner.labels.first { $0.square == "f4" }?.color, .green)
    }

    func testWithoutAnEngineLeoJudgesByTheAnswerAlone() async throws {
        for engine in [nil, FakeEngine(silent: true)] as [ChessEngine?] {
            let runner = try XCTUnwrap(CandidateRunner(puzzle: ThinkSample.skewer, engine: engine, sounds: nil))
            runner.begin()
            await waitUntil("the board is handed over") { runner.phase == .listing }
            ThinkSample.name(runner, "b1b7")
            runner.check()
            await waitUntil("Leo answers") { runner.phase == .judged }
            let report = try XCTUnwrap(runner.report)
            XCTAssertFalse(report.usedEngine)
            XCTAssertEqual(report.rows.map(\.san), ["Bf4"])
            XCTAssertEqual(report.points, 0)
            XCTAssertEqual(runner.tone, .hint)
            XCTAssertEqual(runner.arrows.count, 2, "Your move, and the winner in green")
            XCTAssertNil(runner.arrows.first { $0.from == "b1" }?.dashed, "Nothing is said about Rb7")
        }
    }

    func testTheWinningLinePlaysOut() async throws {
        let runner = try XCTUnwrap(CandidateRunner(puzzle: ThinkSample.skewer, engine: nil, sounds: nil))
        runner.begin()
        await waitUntil("the board is handed over") { runner.phase == .listing }
        ThinkSample.name(runner, "e3f4")
        runner.check()
        await waitUntil("Leo answers") { runner.phase == .judged }
        runner.showLine()
        XCTAssertEqual(runner.phase, .playingLine)
        await waitUntil("the line has played", timeout: .seconds(8)) { runner.phase == .lineShown }
        let end = try XCTUnwrap(TrainingChess.fen(after: Array(ThinkSample.skewer.moves.dropFirst()), from: runner.fen))
        XCTAssertEqual(TrainingChess.key(runner.game.fen), TrainingChess.key(end))
        XCTAssertEqual(runner.message, "The winning line: 1. Bf4 Qf6 2. Bxd6")
        XCTAssertTrue(runner.arrows.isEmpty)
    }

    func testARoundOfFiveIsScoredAndSaved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("think-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThinkStore(fileURL: url)
        let session = CandidateSession(puzzles: [ThinkSample.skewer, ThinkSample.fork], rating: 1400, engine: nil,
                                       store: store, sounds: nil)
        session.next()
        for position in 1...CandidateRound.length {
            let runner = try XCTUnwrap(session.runner)
            XCTAssertEqual(session.position, position)
            await waitUntil("position \(position) is ready") { runner.phase == .listing }
            ThinkSample.name(runner, runner.winner)
            runner.check()
            await waitUntil("position \(position) is judged") { runner.phase == .judged }
            session.next()
        }
        XCTAssertEqual(session.stage, .summary)
        XCTAssertEqual(session.round.points, 15)
        XCTAssertTrue(session.newBest)
        XCTAssertEqual(store.progress.positions, 5)
        XCTAssertEqual(store.progress.found, 5)
        XCTAssertEqual(store.progress.foundFirst, 5)
        XCTAssertEqual(store.progress.rounds, 1)
        XCTAssertEqual(store.progress.bestRound, 15)
        XCTAssertEqual(session.bestRound, 15)
        XCTAssertEqual(store.candidateStatus, "Best round 15 of 25")
        XCTAssertEqual(ThinkStore.load(from: url), store.progress, "Saved as it goes")

        session.newRound()
        XCTAssertEqual(session.stage, .playing)
        XCTAssertEqual(session.round.points, 0)
        XCTAssertEqual(session.position, 1)
        session.cancel()
    }

    // MARK: Saving

    func testTheRecordSurvivesARestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("think-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThinkStore(fileURL: url)
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: ["e3f4"], lines: ThinkSample.skewerLines)
        store.record(report, puzzleID: "abgJu")
        XCTAssertTrue(store.finishRound(points: 12))
        XCTAssertFalse(store.finishRound(points: 9))
        store.recordLevel(1480, on: Date(timeIntervalSince1970: 1_800_000_000))

        let loaded = try XCTUnwrap(ThinkStore.load(from: url))
        XCTAssertEqual(loaded, store.progress)
        XCTAssertEqual(loaded.recent, ["abgJu"])
        XCTAssertEqual(loaded.foundFirst, 1)
        XCTAssertEqual(loaded.bestRound, 12)
        XCTAssertEqual(loaded.rounds, 2)
        XCTAssertEqual(loaded.level, 1480)
        XCTAssertEqual(store.levelBand, .club)
        XCTAssertEqual(store.levelStatus, "Club player · 1480")
    }

    func testOlderFilesStillLoad() throws {
        let partial = try JSONDecoder().decode(ThinkProgress.self, from: Data(#"{"positions": 4, "found": 2}"#.utf8))
        XCTAssertEqual(partial.positions, 4)
        XCTAssertEqual(partial.found, 2)
        XCTAssertEqual(partial.bestRound, 0)
        XCTAssertEqual(partial.recent, [])
        XCTAssertNil(partial.level)
        XCTAssertEqual(try JSONDecoder().decode(ThinkProgress.self, from: Data("{}".utf8)), ThinkProgress())
    }

    func testTheDoorSaysWhereThePlayerStands() {
        var progress = ThinkProgress()
        XCTAssertEqual(ThinkStore(progress: progress).candidateStatus, "Three candidates, one winner")
        progress.positions = 8
        progress.found = 5
        XCTAssertEqual(ThinkStore(progress: progress).candidateStatus, "Winner found 5 of 8")
        progress.rounds = 1
        progress.bestRound = 17
        XCTAssertEqual(ThinkStore(progress: progress).candidateStatus, "Best round 17 of 25")
        XCTAssertNil(ThinkStore(progress: progress).levelStatus)
        XCTAssertNil(ThinkStore(progress: progress).levelBand)
    }

    func testRecentPositionsAreCapped() {
        let store = ThinkStore()
        let report = CandidateJudge.report(fen: skewerFEN, winner: "e3f4", candidates: [], lines: [])
        for index in 0..<(ThinkStore.recentLimit + 20) {
            store.record(report, puzzleID: "p\(index)")
        }
        XCTAssertEqual(store.progress.recent.count, ThinkStore.recentLimit)
        XCTAssertEqual(store.progress.recent.last, "p\(ThinkStore.recentLimit + 19)")
        XCTAssertEqual(store.progress.positions, ThinkStore.recentLimit + 20)
    }

    // MARK: The level check

    func testTheCheckStartsAt1200AndFollowsTheAnswers() {
        var up = LevelEstimator()
        XCTAssertEqual(up.nextRating, 1200)
        up.record(rating: 1200, solved: true)
        XCTAssertGreaterThan(up.nextRating, 1500, "A big step up after a solve")
        // A miss says less than a solve, since good players slip too, so the step down is smaller.
        var down = LevelEstimator()
        down.record(rating: 1200, solved: false)
        XCTAssertLessThan(down.nextRating, 1100, "A step down after a miss")
        XCTAssertGreaterThan(down.nextRating, 850)
    }

    func testStepsShrinkAsTheAnswersComeIn() {
        var estimator = LevelEstimator()
        var steps: [Int] = []
        for index in 0..<LevelEstimator.questions {
            let before = estimator.nextRating
            estimator.record(rating: before, solved: index.isMultiple(of: 2))
            steps.append(abs(estimator.nextRating - before))
        }
        XCTAssertGreaterThan(steps[0], 2 * steps[LevelEstimator.questions - 1], "Big steps first, then small: \(steps)")
        XCTAssertLessThan(estimator.uncertainty, 250)
        XCTAssertTrue(estimator.isDone)
    }

    /// Players of known strength, simulated: each solves a puzzle with the chance
    /// the Elo curve gives, and slips one in twenty. Ten puzzles should find them.
    func testTheEstimateFindsSimulatedPlayers() {
        var generator = ThinkSeededRandom(seed: 42)
        for strength in [700, 1000, 1300, 1600, 1900, 2200, 2500] {
            var errors: [Int] = []
            for _ in 0..<200 {
                var estimator = LevelEstimator()
                while !estimator.isDone {
                    // The pack rarely has a puzzle at exactly the target.
                    let rating = estimator.nextRating + Int.random(in: -60...60, using: &generator)
                    let chance = 0.95 / (1 + pow(10, Double(rating - strength) / 400))
                    estimator.record(rating: rating, solved: Double.random(in: 0..<1, using: &generator) < chance)
                }
                errors.append(estimator.estimate - strength)
            }
            let bias = Double(errors.reduce(0, +)) / Double(errors.count)
            let meanError = Double(errors.map(abs).reduce(0, +)) / Double(errors.count)
            let close = Double(errors.filter { abs($0) <= 300 }.count) / Double(errors.count)
            XCTAssertLessThan(abs(bias), 120, "Bias for a \(strength) player")
            XCTAssertLessThan(meanError, 170, "Typical miss for a \(strength) player")
            XCTAssertGreaterThan(close, 0.85, "Within 300 for a \(strength) player")
        }
    }

    func testTheExtremesGoAllTheWay() {
        var strong = LevelEstimator()
        var weak = LevelEstimator()
        while !strong.isDone {
            strong.record(rating: strong.nextRating, solved: true)
            weak.record(rating: weak.nextRating, solved: false)
        }
        XCTAssertGreaterThanOrEqual(strong.estimate, 2500)
        XCTAssertLessThanOrEqual(weak.estimate, 600)
        XCTAssertEqual(LevelBand(rating: strong.estimate), .expert)
        XCTAssertEqual(LevelBand(rating: weak.estimate), .beginner)
        strong.record(rating: 1000, solved: false)
        XCTAssertEqual(strong.answers.count, LevelEstimator.questions, "Nothing counts after the last puzzle")
    }

    func testBandsHaveFriendlyNames() {
        XCTAssertEqual(LevelBand(rating: 400), .beginner)
        XCTAssertEqual(LevelBand(rating: 999), .beginner)
        XCTAssertEqual(LevelBand(rating: 1000), .improver)
        XCTAssertEqual(LevelBand(rating: 1520), .club)
        XCTAssertEqual(LevelBand(rating: 1800), .strongClub)
        XCTAssertEqual(LevelBand(rating: 2650), .expert)
        XCTAssertEqual(LevelBand.allCases.map(\.name),
                       ["Beginner", "Improver", "Club player", "Strong club player", "Expert"])
        for band in LevelBand.allCases {
            XCTAssertTrue(band.advice.hasSuffix("."), band.name)
        }
    }

    func testTheLevelCheckAsksTenPuzzlesOneTryEach() async throws {
        let runner = LevelCheckRunner(puzzles: ThinkSample.mates, playsSounds: false)
        XCTAssertEqual(runner.phase, .intro)
        runner.start()
        var seen: Set<String> = []
        for index in 0..<LevelEstimator.questions {
            XCTAssertEqual(runner.phase, .solving)
            XCTAssertEqual(runner.number, index + 1)
            let puzzle = try XCTUnwrap(runner.puzzle)
            XCTAssertTrue(seen.insert(puzzle.id).inserted, "No puzzle twice")
            switch index {
            case 0, 1:
                await waitUntil("puzzle \(index + 1) is ready") { runner.drill?.acceptsTaps == true }
                play(runner, puzzle.moves[1])
                XCTAssertEqual(runner.phase, .answered(solved: true))
            case 2:
                await waitUntil("puzzle \(index + 1) is ready") { runner.drill?.acceptsTaps == true }
                let fen = ThinkSample.position(of: puzzle)
                let board = try XCTUnwrap(TrainingChess.board(after: [], from: fen))
                let wrong = try XCTUnwrap(TrainingChess.legalMoves(in: board).first {
                    CandidateJudge.finalEvaluation(of: $0, in: fen) == nil
                })
                play(runner, wrong)
                XCTAssertEqual(runner.phase, .answered(solved: false), "One wrong move and it's a miss")
            default:
                runner.pass()
                XCTAssertEqual(runner.phase, .answered(solved: false))
            }
            await waitUntil("the next puzzle or the result") { runner.phase == .solving || runner.phase == .finished }
        }
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.solved, 2)
        XCTAssertEqual(runner.estimator.answers.count, LevelEstimator.questions)
        XCTAssertEqual(runner.progress, 1)
        XCTAssertEqual(runner.band, LevelBand(rating: runner.rating))
    }

    func testAFinishedCheckGoesStraightToTheResult() {
        var estimator = LevelEstimator()
        while !estimator.isDone { estimator.record(rating: estimator.nextRating, solved: true) }
        let runner = LevelCheckRunner(puzzles: [], playsSounds: false, estimator: estimator)
        runner.start()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.band, .expert)
    }

    // MARK: Helpers

    private func play(_ runner: LevelCheckRunner, _ uci: String) {
        guard let squares = Notation.squares(of: uci) else { return }
        runner.tap(squares.from)
        runner.tap(squares.to)
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Timed out waiting until \(what)")
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Snapshots

/// An engine that takes its time, so the screen can be seen while Leo checks.
actor ThinkSlowEngine: ChessEngine {
    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        try? await Task.sleep(for: .seconds(30))
        return []
    }

    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String? { nil }
}

/// The thinking drills' screens at iPhone size in their main states, on the
/// default look and on Neon, and on a small phone. When SNAPSHOT_DIR is set the
/// pictures are saved there as train-candidates-*.png and train-level-*.png.
@MainActor
final class ThinkSnapshotTests: XCTestCase {
    private let small = CGSize(width: 375, height: 667)
    /// The type design before the test, put back after it so other screens' pictures don't change.
    private var savedDesign: Font.Design = .rounded

    override func setUp() async throws {
        savedDesign = ThemeFont.design
    }

    override func tearDown() async throws {
        ThemeFont.design = savedDesign
    }

    func testCandidatesScreens() throws {
        let theme = BoardTheme.named(.gilded)
        let session = CandidateSession(puzzles: [ThinkSample.skewer], rating: 1400, engine: ThinkSample.skewerEngine(),
                                       store: ThinkStore(), sounds: nil)
        session.next()
        let runner = try XCTUnwrap(session.runner)
        let window = try show(candidates(session, theme: theme), theme: theme)
        settle { runner.phase == .listing }
        ThinkSample.name(runner, "b1b7")
        ThinkSample.name(runner, "e3f4")
        try save(window, "train-candidates-listing")
        ThinkSample.name(runner, "c2c6")
        runner.check()
        settle { runner.phase == .judged }
        try save(window, "train-candidates-verdict")
        runner.showLine()
        settle(timeout: 8) { runner.phase == .lineShown }
        try save(window, "train-candidates-line")
        session.cancel()
        window.isHidden = true
    }

    func testCandidatesWhileLeoChecks() throws {
        let theme = BoardTheme.named(.gilded)
        let session = CandidateSession(puzzles: [ThinkSample.fork], rating: 1500, engine: ThinkSlowEngine(),
                                       store: nil, sounds: nil)
        session.next()
        let runner = try XCTUnwrap(session.runner)
        let window = try show(candidates(session, theme: theme), theme: theme)
        settle { runner.phase == .listing }
        for move in ["f1f6", "g5f6", "g3g4"] { ThinkSample.name(runner, move) }
        runner.check()
        settle(timeout: 1.5) { false }
        try save(window, "train-candidates-checking")
        session.cancel()
        window.isHidden = true
    }

    /// The verdict on Neon, the one look with glow, and on a small phone.
    func testCandidatesVerdictOnNeonAndASmallPhone() throws {
        let looks: [(BoardTheme, CGSize?, String)] = [(BoardTheme.named(.neon), nil, "train-candidates-verdict-neon"),
                                                      (BoardTheme.named(.gilded), small, "train-candidates-verdict-small")]
        for (theme, size, name) in looks {
            let session = CandidateSession(puzzles: [ThinkSample.skewer], rating: 1400, engine: ThinkSample.skewerEngine(),
                                           store: nil, sounds: nil)
            session.next()
            let runner = try XCTUnwrap(session.runner)
            let window = try show(candidates(session, theme: theme), theme: theme, size: size)
            settle { runner.phase == .listing }
            for move in ["b1b7", "e3f4", "c2c6"] { ThinkSample.name(runner, move) }
            runner.check()
            settle { runner.phase == .judged }
            try save(window, name)
            session.cancel()
            window.isHidden = true
        }
    }

    func testCandidatesRoundSummary() throws {
        let theme = BoardTheme.named(.gilded)
        let fen = ThinkSample.position(of: ThinkSample.skewer)
        var round = CandidateRound()
        for candidates in [["e3f4", "b1b7"], ["b1b7"], ["e2d3", "e3f4"], ["e3f4", "b1b7", "e2d3"], ["f1c1", "b1b7"]] {
            round.add(CandidateJudge.report(fen: fen, winner: "e3f4", candidates: candidates, lines: ThinkSample.skewerLines))
        }
        let store = ThinkStore()
        let session = CandidateSession(puzzles: [ThinkSample.skewer], rating: 1400, engine: nil, store: store,
                                       sounds: nil, round: round)
        session.next()
        XCTAssertEqual(session.stage, .summary)
        let window = try show(candidates(session, theme: theme), theme: theme)
        try save(window, "train-candidates-summary")
        window.isHidden = true
    }

    func testLevelCheckScreens() throws {
        let theme = BoardTheme.named(.gilded)
        let runner = LevelCheckRunner(puzzles: ThinkSample.mates, playsSounds: false)
        let window = try show(level(runner, theme: theme), theme: theme)
        try save(window, "train-level-intro")
        runner.start()
        settle { runner.drill?.acceptsTaps == true }
        try save(window, "train-level-puzzle")
        runner.cancel()
        window.isHidden = true
    }

    func testLevelCheckResult() throws {
        // A club player's answers: solved, missed, missed, solved, missed, solved, missed, then three solved.
        var estimator = LevelEstimator()
        for solved in [true, false, false, true, false, true, false, true, true, true] {
            estimator.record(rating: estimator.nextRating, solved: solved)
        }
        let looks: [(BoardTheme, CGSize?, String)] = [(BoardTheme.named(.gilded), nil, "train-level-result"),
                                                      (BoardTheme.named(.neon), small, "train-level-result-small")]
        for (theme, size, name) in looks {
            let runner = LevelCheckRunner(puzzles: ThinkSample.mates, playsSounds: false, estimator: estimator)
            runner.start()
            XCTAssertEqual(runner.phase, .finished)
            let window = try show(level(runner, theme: theme), theme: theme, size: size)
            try save(window, name)
            window.isHidden = true
        }
    }

    // MARK: Drawing

    private func candidates(_ session: CandidateSession, theme: BoardTheme) -> some View {
        CandidateMovesView(theme: theme, session: session)
            .environment(PuzzleStore(library: PuzzleLibrary(puzzles: [ThinkSample.skewer, ThinkSample.fork])))
    }

    private func level(_ runner: LevelCheckRunner, theme: BoardTheme) -> some View {
        LevelCheckView(theme: theme, runner: runner) { _ in }
            .environment(PuzzleStore(library: PuzzleLibrary(puzzles: ThinkSample.mates)))
            .environment(ThinkStore())
    }

    /// Puts the view in a window the size of the phone, or of a small phone, and lets it settle.
    private func show(_ view: some View, theme: BoardTheme, size: CGSize? = nil, wait: TimeInterval = 3) throws -> UIWindow {
        ThemeFont.use(theme)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    /// Lets the run loop turn until `condition` holds, or the time is up.
    private func settle(timeout: TimeInterval = 6, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
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
