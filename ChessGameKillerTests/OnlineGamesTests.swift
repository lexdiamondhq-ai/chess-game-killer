import ChessKit
import XCTest
@testable import ChessGameKiller

/// Bringing games in from Chess.com and Lichess: reading what the sites send, replaying the
/// moves, grading the player's side, and keeping each game once.
final class OnlineGamesTests: XCTestCase {

    // MARK: PGN

    func testPGNMovesSkipTagsCommentsSideLinesAndTheResult() {
        let pgn = """
        [Event "Live Chess"]
        [White "alex"]
        [Black "rival"]

        1. e4 {[%clk 0:02:59.9]} 1... e5 {[%clk 0:02:58]} 2. Nf3 $1 (2. Bc4 Nc6) 2... Nc6
        3.Bb5 a6!? 4. O-O 1-0
        """
        XCTAssertEqual(PGN.moves(in: pgn), ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6!?", "O-O"])
    }

    func testPGNKeepsCastlingWrittenWithZeros() {
        XCTAssertEqual(PGN.moves(in: "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 *"),
                       ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "0-0"])
    }

    // MARK: Replaying

    func testScholarsMateReplaysAndEndsInMate() throws {
        let replay = try XCTUnwrap(GameImportBuilder.replay(["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"]))
        XCTAssertEqual(replay.uci, ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"])
        XCTAssertEqual(replay.positions.count, 8)
        XCTAssertTrue(replay.endsInMate)
    }

    func testAMoveThatDoesNotFitStopsTheReplay() {
        XCTAssertNil(GameImportBuilder.replay(["e4", "e5", "Ke3", "Qh4", "Kxh7"]))
    }

    func testCastlingAndUnderpromotion() throws {
        let castles = Board(position: try XCTUnwrap(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")))
        XCTAssertEqual(GameImportBuilder.uci(forSAN: "O-O", on: castles), "e1g1")
        XCTAssertEqual(GameImportBuilder.uci(forSAN: "0-0-0", on: castles), "e1c1")

        let promotes = Board(position: try XCTUnwrap(Position(fen: "8/P7/8/8/8/8/8/k6K w - - 0 1")))
        XCTAssertEqual(GameImportBuilder.uci(forSAN: "a8=N", on: promotes), "a7a8n")
        XCTAssertEqual(GameImportBuilder.uci(forSAN: "a8=Q+", on: promotes), "a7a8q")
    }

    // MARK: The sites

    func testLichessExportSkipsUnfinishedGames() {
        let lines = [
            #"{"id":"abc12345","rated":true,"variant":"standard","speed":"blitz","status":"mate","createdAt":1700000000000,"lastMoveAt":1700000300000,"players":{"white":{"user":{"name":"Alex","id":"alex"},"rating":1510},"black":{"user":{"name":"Rook99","id":"rook99"},"rating":1490}},"winner":"white","moves":"e4 e5 Bc4 Nc6 Qh5 Nf6 Qxf7#","clock":{"initial":180,"increment":2,"totalTime":260}}"#,
            #"{"id":"zzz","variant":"standard","status":"aborted","createdAt":1700000000000,"players":{"white":{"user":{"name":"Alex"}},"black":{"aiLevel":3}},"moves":"e4"}"#,
            #"{"id":"draw1","variant":"standard","status":"draw","createdAt":1690000000000,"players":{"white":{"aiLevel":3},"black":{"user":{"name":"Alex"},"rating":1500}},"moves":"d4 d5"}"#,
        ]
        let games = OnlineGames.parseLichess(Data(lines.joined(separator: "\n").utf8))
        XCTAssertEqual(games.map(\.gameID), ["abc12345", "draw1"])
        XCTAssertEqual(games[0].winner, .white)
        XCTAssertEqual(games[0].clock, "3+2")
        XCTAssertEqual(games[0].playerIsWhite("alex"), true)
        XCTAssertEqual(games[0].date, Date(timeIntervalSince1970: 1_700_000_300))
        XCTAssertNil(games[1].winner)
        XCTAssertEqual(games[1].white, "Stockfish level 3")
        XCTAssertEqual(games[1].playerIsWhite("ALEX"), false)
    }

    func testChessComMonthReadsResultsAndSkipsVariants() throws {
        let month = """
        {"games":[
          {"url":"https://www.chess.com/game/live/1","uuid":"u1","pgn":"[White \\"alex\\"]\\n\\n1. e4 e5 2. Nf3 Nc6 1/2-1/2","time_control":"600","end_time":1700000000,"rules":"chess","white":{"username":"alex","rating":1200,"result":"agreed"},"black":{"username":"bob","rating":1180,"result":"agreed"}},
          {"url":"https://www.chess.com/game/live/2","uuid":"u2","pgn":"1. d4 d5 0-1","time_control":"180+2","end_time":1700000500,"rules":"chess","white":{"username":"alex","rating":1210,"result":"resigned"},"black":{"username":"carol","rating":1250,"result":"win"}},
          {"url":"https://www.chess.com/game/live/3","uuid":"u3","pgn":"1. e4 1-0","time_control":"180","end_time":1700000900,"rules":"chess960","white":{"username":"alex","result":"win"},"black":{"username":"dan","result":"resigned"}}
        ]}
        """
        let games = OnlineGames.parseChessComMonth(Data(month.utf8))
        XCTAssertEqual(games.map(\.gameID), ["u2", "u1"], "newest first, the Chess960 game left out")
        XCTAssertEqual(games[0].winner, .black)
        XCTAssertEqual(games[0].clock, "3+2")
        XCTAssertNil(games[1].winner)
        XCTAssertEqual(games[1].clock, "10+0")
        XCTAssertEqual(games[1].moves, ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertEqual(games[1].sourceID, "chess.com:u1")
    }

    func testClockNamesOnlyForClocksTheAppPlays() {
        XCTAssertEqual(OnlineGames.clockName(chessCom: "180+2"), "3+2")
        XCTAssertEqual(OnlineGames.clockName(chessCom: "300"), "5+0")
        XCTAssertNil(OnlineGames.clockName(chessCom: "60"))
        XCTAssertNil(OnlineGames.clockName(chessCom: "1/86400"))
    }

    func testUsernames() {
        XCTAssertEqual(OnlineGames.cleaned("  Magnus_C-1 "), "Magnus_C-1")
        XCTAssertNil(OnlineGames.cleaned("a"))
        XCTAssertNil(OnlineGames.cleaned("bad name"))
        XCTAssertNil(OnlineGames.cleaned("../etc"))
        XCTAssertNotNil(OnlineGames.lichessURL(username: "alex", max: 10))
        XCTAssertEqual(OnlineGames.chessComArchivesURL(username: "Alex")?.absoluteString,
                       "https://api.chess.com/pub/player/alex/games/archives")
    }

    // MARK: Grading

    static func scholarsMate(id: String = "abc12345", date: Date = .now) -> ImportedGame {
        ImportedGame(site: .lichess, gameID: id, white: "Alex", black: "Rook99", whiteRating: 1510, blackRating: 1490,
                   winner: .white, date: date, moves: ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"], clock: "3+2")
    }

    func testGradingKeepsOnlyThePlayersMovesAndEndsWithTheMate() async throws {
        let grader = GameImportGrader(engine: FakeEngine())
        let gradedGame = await grader.grade(Self.scholarsMate(), username: "alex")
        let game = try XCTUnwrap(gradedGame)
        XCTAssertEqual(game.moments.map(\.ply), [1, 3, 5, 7])
        XCTAssertTrue(game.moments.allSatisfy(\.byWhite))
        XCTAssertEqual(game.moments.last?.moveGrade, .checkmate)
        XCTAssertEqual(game.result, .win)
        XCTAssertEqual(game.opponent, "Rook99")
        XCTAssertEqual(game.opponentRating, 1490)
        XCTAssertEqual(game.source, "lichess")
        XCTAssertEqual(game.sourceID, "lichess:abc12345")
        XCTAssertEqual(game.clock, "3+2")
        XCTAssertNil(game.level)
        XCTAssertTrue(game.isPlayersOwn)
        XCTAssertNotNil(game.accuracy)
        XCTAssertEqual(game.positions.count, 8)
    }

    func testGradingTheLosingSide() async throws {
        let grader = GameImportGrader(engine: FakeEngine())
        let gradedGame = await grader.grade(Self.scholarsMate(), username: "rook99")
        let game = try XCTUnwrap(gradedGame)
        XCTAssertEqual(game.moments.map(\.ply), [2, 4, 6])
        XCTAssertEqual(game.result, .loss)
        XCTAssertFalse(game.playerIsWhite)
        XCTAssertEqual(game.playerMoments.count, 3)
    }

    func testAGameThePlayerIsNotInIsLeftOut() async {
        let grader = GameImportGrader(engine: FakeEngine())
        let game = await grader.grade(Self.scholarsMate(), username: "someoneelse")
        XCTAssertNil(game)
    }

    // MARK: The import

    struct FakeSource: OnlineGameSource {
        let games: [ImportedGame]
        var error: GameImportError?

        func recentGames(site: OnlineSite, username: String, count: Int) async throws -> [ImportedGame] {
            if let error { throw error }
            return games
        }
    }

    @MainActor
    func testImportingKeepsEachGameOnceAndRemembersTheAccount() async throws {
        let suite = "import-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let older = Self.scholarsMate(id: "old", date: .now.addingTimeInterval(-86_400))
        let newer = Self.scholarsMate(id: "new", date: .now.addingTimeInterval(-3_600))
        let importer = GameImporter(source: FakeSource(games: [newer, older]), engine: FakeEngine(), defaults: defaults)
        let vault = GameVault()

        await importer.run(site: .lichess, username: "Alex", vault: vault, store: nil)
        XCTAssertEqual(importer.phase, .finished(added: 2, mistakes: 0))
        XCTAssertEqual(vault.games.map(\.sourceID), ["lichess:new", "lichess:old"])
        XCTAssertEqual(importer.account, GameImporter.Account(site: .lichess, username: "Alex"))

        await importer.run(site: .lichess, username: "Alex", vault: vault, store: nil)
        XCTAssertEqual(importer.phase, .finished(added: 0, mistakes: 0))
        XCTAssertEqual(vault.games.count, 2)

        let reopened = GameImporter(source: FakeSource(games: []), engine: FakeEngine(), defaults: defaults)
        XCTAssertEqual(reopened.account?.username, "Alex")
    }

    @MainActor
    func testAnUnknownPlayerSaysSo() async throws {
        let suite = "import-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = GameImporter(source: FakeSource(games: [], error: .noSuchPlayer(.chessCom, "nobody")),
                                    engine: FakeEngine(), defaults: defaults)
        await importer.run(site: .chessCom, username: "nobody", vault: GameVault(), store: nil)
        XCTAssertEqual(importer.phase, .failed("Chess.com has no player called nobody."))
        XCTAssertNil(importer.account)
    }

    @MainActor
    func testImportedGamesSitInTheVaultByDateAndCountForTheCoach() async throws {
        let vault = GameVault()
        let playedHere = RewindSample.game(date: .now)
        vault.record(playedHere)
        let grader = GameImportGrader(engine: FakeEngine())
        let gradedImported = await grader.grade(Self.scholarsMate(date: .now.addingTimeInterval(-86_400 * 3)), username: "alex")
        let imported = try XCTUnwrap(gradedImported)
        vault.record(imported)
        XCTAssertEqual(vault.games.first?.id, playedHere.id)
        XCTAssertEqual(vault.games.last?.id, imported.id)
        XCTAssertTrue(vault.hasImported("lichess:abc12345"))
        XCTAssertEqual(ChessDNA.make(games: vault.games).gamesRead, 2)
    }
}
