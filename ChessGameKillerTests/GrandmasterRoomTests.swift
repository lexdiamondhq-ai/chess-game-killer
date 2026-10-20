import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class GrandmasterRoomTests: XCTestCase {

    func testBundledContentLoadsAndPlays() {
        let content = GrandmasterContent.shared
        XCTAssertGreaterThanOrEqual(content.games.count, 10)
        XCTAssertGreaterThanOrEqual(content.endgames.count, 8)
        XCTAssertGreaterThan(content.openings.count, 3000)
        for game in content.games {
            XCTAssertNotNil(TrainingChess.fen(after: game.moves, from: Position.standard.fen), game.id)
        }
        for study in content.endgames {
            XCTAssertNotNil(Position(fen: study.fen), study.id)
        }
        for line in content.openings.prefix(400) {
            XCTAssertNotNil(TrainingChess.fen(after: line.moves, from: Position.standard.fen), line.name)
        }
    }

    func testOpeningNames() {
        let line = OpeningLine(eco: "B90", name: "Sicilian Defense: Najdorf Variation",
                               moves: ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6"])
        XCTAssertEqual(line.family, "Sicilian Defense")
        XCTAssertEqual(line.variation, "Najdorf Variation")
        XCTAssertEqual(line.naturalSide, .black)
    }

    func testRepertoireSchedule() {
        let store = RepertoireStore()
        let line = OpeningLine(eco: "C50", name: "Italian Game", moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
        store.add(line, side: .white)
        store.add(line, side: .white)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.due.count, 1)
        let now = Date()
        store.reviewed(store.entries[0], clean: true, now: now)
        XCTAssertEqual(store.entries[0].box, 1)
        XCTAssertTrue(store.due.isEmpty)
        store.reviewed(store.entries[0], clean: false, now: now)
        XCTAssertEqual(store.entries[0].box, 0)
    }

    func testTablebaseValues() throws {
        let json = """
        {"category":"win","dtm":17,"checkmate":false,"stalemate":false,
         "moves":[{"uci":"h1h5","san":"Qh5+","category":"loss","dtm":-16},
                  {"uci":"e1d1","san":"Kd1","category":"draw","dtm":null}]}
        """
        let result = try JSONDecoder().decode(TablebaseResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.value, 1)
        XCTAssertEqual(result.value(of: "h1h5"), 1)
        XCTAssertEqual(result.value(of: "e1d1"), 0)
        XCTAssertNil(result.value(of: "a1a2"))
    }

    func testGuessScoresAnExactMove() {
        let game = ClassicGame(id: "t", white: "A", black: "B", event: "E", year: 2000, result: "1-0", blurb: "",
                               moves: ["e2e4", "e7e5", "g1f3"])
        let runner = GuessRunner(game: game, engine: nil)
        XCTAssertEqual(runner.hero, .white)
        XCTAssertEqual(runner.maxPoints, 0)
    }
}
