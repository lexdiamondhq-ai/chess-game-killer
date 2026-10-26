import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class GrandmasterRoomTests: XCTestCase {

    func testBundledContentLoadsAndPlays() {
        let content = GrandmasterContent.shared
        XCTAssertGreaterThanOrEqual(content.games.count, 10)
        XCTAssertGreaterThanOrEqual(content.endgames.count, 20)
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

    /// Lichess asks every client to say who it is; a request without a User-Agent can be throttled.
    func testTablebaseRequestsSayWhoIsAsking() throws {
        let fen = "8/8/8/8/8/4k3/8/4K2R w K - 0 1"
        let request = Tablebase.request(for: fen, timeout: 3)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host(), "tablebase.lichess.ovh")
        XCTAssertEqual(url.path(), "/standard")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "fen" }?.value, fen)
        XCTAssertEqual(request.timeoutInterval, 3)
        let agent = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(agent.hasPrefix("ChessGameKiller/"), agent)
        XCTAssertTrue(agent.contains("github.com/lexdiamondhq-ai/chess-game-killer"), "Where to reach us: \(agent)")
        XCTAssertEqual(Tablebase.userAgent(version: "1.2"), "ChessGameKiller/1.2 (iOS; +https://github.com/lexdiamondhq-ai/chess-game-killer)")
        XCTAssertEqual(Tablebase.userAgent(version: nil), "ChessGameKiller/dev (iOS; +https://github.com/lexdiamondhq-ai/chess-game-killer)")
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
        XCTAssertEqual(result.mateInMoves, 9)
    }

    func testGuessScoresAnExactMove() {
        let game = ClassicGame(id: "t", white: "A", black: "B", event: "E", year: 2000, result: "1-0", blurb: "",
                               moves: ["e2e4", "e7e5", "g1f3"])
        let runner = GuessRunner(game: game, engine: nil)
        XCTAssertEqual(runner.hero, .white)
        XCTAssertEqual(runner.maxPoints, 0)
    }

    // MARK: Master games and opening statistics

    func testOpeningStatsParseAndLookUp() throws {
        let start = Position.standard.fen
        let key = TrainingChess.key(start)
        let text = "key\tbook\tmoves\n\(key)\tm\te2e4 60 24 24,d2d4 40 16 20\n\(key)\t2\te2e4 900 450 50\n"
        let stats = OpeningStats(table: OpeningStats.parse(text))
        let masters = try XCTUnwrap(stats.entry(fen: start, book: .masters))
        XCTAssertEqual(masters.total, 100)
        XCTAssertEqual(masters.moves.first?.uci, "e2e4")
        XCTAssertEqual(masters.share(of: "d2d4"), 0.4, accuracy: 0.001)
        XCTAssertEqual(masters.share(of: "g1f3"), 0)
        XCTAssertEqual(masters.moves[0].blackWins, 12)
        XCTAssertEqual(masters.moves[0].score(for: .white), 0.6, accuracy: 0.001)
        XCTAssertEqual(stats.entry(fen: start, book: .band(.to1800))?.total, 900)
        XCTAssertNil(stats.entry(fen: start, book: .band(.over2100)))
    }

    func testRatingBands() {
        XCTAssertEqual(OpeningStats.Band.forPuzzleRating(1000), .under1200)
        XCTAssertEqual(OpeningStats.Band.forPuzzleRating(1800), .to1800)
        XCTAssertEqual(OpeningStats.Band.forPuzzleRating(2600), .over2100)
        XCTAssertEqual(OpeningStats.Band.to1500.range, "1200–1500")
        XCTAssertEqual(OpeningStats.Book.band(.over2100).code, "4")
    }

    func testMasterGamesParse() throws {
        let json = """
        {"games":[{"id":"m-1","white":"Magnus Carlsen","black":"Anish Giri","event":"Tata Steel","year":2026,
        "result":"1-0","blurb":"","opening":"Italian Game","whiteElo":2830,"blackElo":2760,"date":"2026.01.20",
        "moves":"e2e4 e7e5 g1f3 b8c6 f1c4"}]}
        """
        let games = GrandmasterContent.parseMasterGames(Data(json.utf8))
        let game = try XCTUnwrap(games.first)
        XCTAssertTrue(game.isMasterGame)
        XCTAssertEqual(game.moves.count, 5)
        XCTAssertEqual(game.ratings, "2830 – 2760")
        XCTAssertEqual(game.opening, "Italian Game")
        XCTAssertEqual(game.hero, .white)
        let content = GrandmasterContent(games: [], masterGames: games, endgames: [], openings: [])
        XCTAssertEqual(content.masterGames(following: ["e2e4", "e7e5"]).count, 1)
        XCTAssertTrue(content.masterGames(following: ["d2d4"]).isEmpty)
    }

    /// Once the data workflow has run: the master games play legally and the start position has numbers.
    func testBundledMasterContent() throws {
        let content = GrandmasterContent.shared
        try XCTSkipIf(content.masterGames.isEmpty, "masters-games.json not built yet")
        XCTAssertGreaterThan(content.masterGames.count, 200)
        let step = max(1, content.masterGames.count / 150)
        for game in stride(from: 0, to: content.masterGames.count, by: step).map({ content.masterGames[$0] }) {
            XCTAssertNotNil(TrainingChess.fen(after: game.moves, from: Position.standard.fen), game.id)
        }
        let stats = OpeningStats.shared
        let start = Position.standard.fen
        let masters = try XCTUnwrap(stats.entry(fen: start, book: .masters))
        XCTAssertTrue(masters.moves.contains { $0.uci == "e2e4" || $0.uci == "d2d4" })
        for band in OpeningStats.Band.allCases {
            XCTAssertNotNil(stats.entry(fen: start, book: .band(band)), band.range)
        }
        // Every move kept is legal where it's played.
        for move in masters.moves {
            XCTAssertNotNil(Notation.san(of: move.uci, fen: start), move.uci)
        }
    }
}
