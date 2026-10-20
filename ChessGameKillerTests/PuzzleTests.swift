import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class PuzzleTests: XCTestCase {

    private let sample = """
    id,fen,moves,rating,themes
    0000D,5rk1/1p3ppp/pq3b2/8/8/1P1Q1N2/P4PPP/3R2K1 w - - 2 27,d3d6 f8d8 d6d8 f6d8,1500,endgame
    00008,r6k/pp2r2p/4Rp1Q/3p4/8/1N1P2R1/PqP2bPP/7K b - - 0 24,f2g3 e6e7 b2b1 b3c1 b1c1 h6c1,1913,hangingPiece middlegame
    bad,not enough fields
    """

    func testReadsThePackFormat() throws {
        let library = PuzzleLibrary(csv: sample)
        XCTAssertEqual(library.puzzles.map(\.id), ["0000D", "00008"])
        let puzzle = try XCTUnwrap(library.puzzles.last)
        XCTAssertEqual(puzzle.rating, 1913)
        XCTAssertEqual(puzzle.moves.first, "f2g3")
        XCTAssertEqual(puzzle.length, 3)
        XCTAssertEqual(puzzle.themeNames, ["Free piece", "Middlegame"])
    }

    func testPuzzleBecomesADrill() throws {
        let puzzle = try XCTUnwrap(PuzzleLibrary(csv: sample).puzzles.first)
        let drill = puzzle.drill
        XCTAssertEqual(drill.type, .move)
        XCTAssertEqual(drill.setup, "d3d6")
        XCTAssertEqual(drill.solution, ["f8d8", "d6d8", "f6d8"])
        XCTAssertNotNil(DrillRunner(item: SessionItem(content: .drill(drill), role: .focus), library: nil, engine: nil,
                                    playsSounds: false))
    }

    func testPicksInTheThemeNearTheRating() {
        let library = PuzzleLibrary(csv: sample)
        var generator = SystemRandomNumberGenerator()
        let endgame = PuzzleTheme.named("endgame")
        XCTAssertEqual(library.pick(near: 1900, theme: endgame, avoid: [], using: &generator)?.id, "0000D")
        XCTAssertEqual(library.pick(near: 1900, theme: .all, avoid: [], using: &generator)?.id, "00008")
        XCTAssertEqual(library.pick(near: 1900, theme: .all, avoid: ["00008"], using: &generator)?.id, "0000D")
        XCTAssertNil(library.pick(near: 1500, theme: .named("pin"), avoid: [], using: &generator))
    }

    func testRatingMovesWithResults() {
        let puzzle = LichessPuzzle(id: "x", fen: "", moves: ["a", "b"], rating: 1000, themes: [])
        let store = PuzzleStore()
        let gain = store.record(puzzle, outcome: .firstTry)
        XCTAssertGreaterThan(gain, 0)
        XCTAssertEqual(store.progress.rating, 1000 + gain)
        XCTAssertEqual(store.progress.streak, 1)
        let loss = store.record(puzzle, outcome: .missed)
        XCTAssertLessThan(loss, 0)
        XCTAssertEqual(store.progress.streak, 0)
        XCTAssertEqual(store.progress.played, 2)
        XCTAssertEqual(store.progress.recent, ["x", "x"])
    }

    func testRushGetsHarderAndKeepsTheBest() {
        XCTAssertLessThan(PuzzleStore.rushRating(after: 0), PuzzleStore.rushRating(after: 10))
        let store = PuzzleStore()
        XCTAssertTrue(store.finishRush(score: 12))
        XCTAssertFalse(store.finishRush(score: 8))
        XCTAssertEqual(store.progress.rushBest, 12)
    }

    /// The bundled pack: large, every theme in the picker present, and a sample of
    /// puzzles that play legally from start to finish.
    func testBundledPackPlays() throws {
        let library = try XCTUnwrap(PuzzleLibrary.bundled(), "lichess-puzzles.csv isn't in the app")
        XCTAssertGreaterThan(library.puzzles.count, 5000)
        for theme in PuzzleTheme.choices {
            XCTAssertGreaterThan(library.count(of: theme), 20, theme.name)
        }
        let step = max(1, library.puzzles.count / 300)
        for puzzle in stride(from: 0, to: library.puzzles.count, by: step).map({ library.puzzles[$0] }) {
            XCTAssertNotNil(TrainingChess.fen(after: puzzle.moves, from: puzzle.fen), puzzle.id)
        }
    }
}
