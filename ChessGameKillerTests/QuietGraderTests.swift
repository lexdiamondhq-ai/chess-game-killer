import ChessKit
import XCTest
@testable import ChessGameKiller

/// Games against people: kept the moment they end with no grades, then read quietly, so Chess
/// DNA and Leo's report count them and their real mistakes go to "Fix your mistakes".
final class QuietGraderTests: XCTestCase {

    // MARK: Sample games

    /// The scholar's mate, in engine notation.
    static let scholarsMate = "e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7"
    /// 1.e4 e5 2.Nf3 Qh4, and White plays 3.d3 with the queen there to be taken.
    static let queenLeft = "e2e4 e7e5 g1f3 d8h4 d2d3"

    /// A finished game against a person as it is kept when it ends: every position, no grades.
    static func person(_ line: String, white: Bool = true, result: SavedGame.Result = .win,
                       daysAgo: Double = 0) -> SavedGame {
        var game = ChessDNATests.game(line, white: white, result: result, accuracy: nil, daysAgo: daysAgo, level: nil)
        game.moments = []
        return game
    }

    /// An engine that sees the free queen in `game` (played from `queenLeft`) and what leaving it costs.
    static func engineSeeingTheQueen(in game: SavedGame) -> FakeEngine {
        FakeEngine(scripted: [
            // Before 3.d3: taking the queen wins.
            game.positions[4]: [EngineLine(moves: ["f3h4"], evaluation: .centipawns(900))],
            // After it: the queen steps back and Black is fine.
            game.positions[5]: [EngineLine(moves: ["h4e7"], evaluation: .centipawns(50))],
        ])
    }

    // MARK: The moves, from the positions

    func testTheMovesAreReadBackFromThePositions() throws {
        // A long quiet game with castling on both sides.
        let london = ChessDNATests.game(ChessDNATests.quietLondon)
        let quiet = try XCTUnwrap(GameImportBuilder.moves(through: london.positions))
        XCTAssertEqual(quiet.uci, ChessDNATests.quietLondon.split(separator: " ").map(String.init))
        XCTAssertFalse(quiet.endsInMate)
        // Captures and checks.
        let liver = ChessDNATests.game(ChessDNATests.friedLiver)
        XCTAssertEqual(GameImportBuilder.moves(through: liver.positions)?.uci,
                       ChessDNATests.friedLiver.split(separator: " ").map(String.init))
        // A game that ends in mate says so.
        let mate = ChessDNATests.game(Self.scholarsMate)
        let mated = try XCTUnwrap(GameImportBuilder.moves(through: mate.positions))
        XCTAssertEqual(mated.uci.last, "h5f7")
        XCTAssertTrue(mated.endsInMate)
    }

    func testAPromotionIsReadWithThePieceThePawnBecame() throws {
        let start = "8/P7/8/8/8/8/8/k6K w - - 0 1"
        for piece in ["q", "r", "b", "n"] {
            let after = try XCTUnwrap(TrainingChess.fen(after: ["a7a8" + piece], from: start))
            XCTAssertEqual(GameImportBuilder.moves(through: [start, after])?.uci, ["a7a8" + piece])
        }
    }

    func testPositionsThatAreNotAMoveApartAreNotRead() {
        let london = ChessDNATests.game(ChessDNATests.quietLondon)
        XCTAssertNil(GameImportBuilder.moves(through: [london.positions[0], london.positions[2]]))
        XCTAssertNil(GameImportBuilder.moves(through: [london.positions[0], london.positions[5]]))
        // One position alone is a game with no moves.
        XCTAssertEqual(GameImportBuilder.moves(through: [london.positions[0]])?.uci, [])
    }

    // MARK: Grading one game

    func testAGameAgainstAPersonIsGradedInPlace() async throws {
        let game = Self.person(Self.scholarsMate)
        XCTAssertTrue(game.awaitsGrading)
        XCTAssertFalse(game.isPlayersOwn)
        let reading = await GameImportGrader(engine: FakeEngine()).grade(game)
        guard case .graded(let graded) = reading else { return XCTFail("\(reading)") }
        // The same game, with the player's side of it graded.
        XCTAssertEqual(graded.id, game.id)
        XCTAssertEqual(graded.date, game.date)
        XCTAssertEqual(graded.moves, game.moves)
        XCTAssertEqual(graded.positions, game.positions)
        XCTAssertEqual(graded.result, .win)
        XCTAssertEqual(graded.graded, true)
        XCTAssertEqual(graded.moments.map(\.ply), [1, 3, 5, 7])
        XCTAssertTrue(graded.moments.allSatisfy(\.byWhite))
        XCTAssertEqual(graded.moments.last?.moveGrade, .checkmate)
        XCTAssertNotNil(graded.accuracy)
        XCTAssertFalse(graded.awaitsGrading)
        XCTAssertTrue(graded.isPlayersOwn)
        XCTAssertEqual(graded.playerMoments.count, 4)
        // Chess DNA and Leo's report read it now.
        XCTAssertEqual(ChessDNA.make(games: [game]).gamesRead, 0)
        XCTAssertEqual(ChessDNA.make(games: [graded]).gamesRead, 1)
    }

    func testOnlyThePlayersSideIsGraded() async throws {
        let game = Self.person(Self.scholarsMate, white: false, result: .loss)
        let reading = await GameImportGrader(engine: FakeEngine()).grade(game)
        guard case .graded(let graded) = reading else { return XCTFail("\(reading)") }
        XCTAssertEqual(graded.moments.map(\.ply), [2, 4, 6])
        XCTAssertTrue(graded.moments.allSatisfy { !$0.byWhite })
        XCTAssertEqual(graded.result, .loss)
    }

    func testAMissedFreePieceIsGradedAndNamed() async throws {
        let game = Self.person(Self.queenLeft)
        let reading = await GameImportGrader(engine: Self.engineSeeingTheQueen(in: game)).grade(game)
        guard case .graded(let graded) = reading else { return XCTFail("\(reading)") }
        let slip = try XCTUnwrap(graded.moments.last)
        XCTAssertEqual(slip.ply, 5)
        XCTAssertEqual(slip.moveGrade, .blunder)
        XCTAssertEqual(slip.best, "Nxh4")
        XCTAssertEqual(slip.bestUCI, "f3h4")
        XCTAssertEqual(slip.reply, "h4e7")
        XCTAssertEqual(MomentFinder.find(in: slip.review)?.kind, .missedFreePiece)
        XCTAssertEqual(CoachReport.make(games: [graded]).missed[.missedFreePiece], 1)
    }

    func testAGameWhosePositionsDontReplayIsLeftUngraded() async {
        let game = Self.person(Self.scholarsMate)
        let engine = FakeEngine()
        let grader = GameImportGrader(engine: engine)
        var short = game
        short.positions.removeLast()
        let first = await grader.grade(short)
        XCTAssertEqual(first, .unreadable)
        var jumbled = game
        jumbled.positions.swapAt(2, 4)
        let second = await grader.grade(jumbled)
        XCTAssertEqual(second, .unreadable)
        let asked = await engine.searches
        XCTAssertTrue(asked.isEmpty, "Nothing to ask the engine about")
    }

    func testAQuietReadingStopsWhenTheEngineHasNothingToSay() async {
        let game = Self.person(Self.queenLeft)
        // A move was played from every position, so an engine with no move to offer isn't working:
        // stop and try again later, never keep a game with holes in it.
        let quiet = GameImportGrader(engine: FakeEngine(silent: true), quiet: true, standBack: .milliseconds(1))
        let silent = await quiet.grade(game)
        XCTAssertEqual(silent, .stopped)
        // Cancelled before the first move.
        let cancelled = await GameImportGrader(engine: FakeEngine(), quiet: true).grade(game, isCancelled: { true })
        XCTAssertEqual(cancelled, .stopped)
    }

    // MARK: Reading the games that wait

    @MainActor
    func testTheWaitingGameIsReadAndItsMistakesSaved() async throws {
        let rival = ChessDNATests.game(ChessDNATests.quietLondon, daysAgo: 1)
        let friend = Self.person(Self.queenLeft, daysAgo: 3)
        let vault = GameVault(games: [rival, friend])
        let store = TrainingStore(library: try XCTUnwrap(TrainingLibrary.shared))
        let engine = Self.engineSeeingTheQueen(in: friend)
        let reader = QuietGrader(vault: vault, store: store, engine: engine)
        reader.holdsBack = { false }

        await reader.run()

        let read = try XCTUnwrap(vault.game(friend.id))
        XCTAssertEqual(read.graded, true)
        XCTAssertFalse(read.awaitsGrading)
        XCTAssertEqual(read.date, friend.date)
        XCTAssertEqual(read.moments.map(\.ply), [1, 3, 5])
        XCTAssertEqual(read.moments.last?.moveGrade, .blunder)
        XCTAssertEqual(vault.games.map(\.id), [rival.id, friend.id], "It stays where it was in the list")
        // The game against the rival was graded as it was played: left as it is.
        XCTAssertEqual(vault.game(rival.id), rival)
        // Its real mistake is saved to practice, dated when the game was played, so reading an
        // old game never pushes fresher mistakes out of the pile.
        let saved = try XCTUnwrap(store.openMistakes.first)
        XCTAssertEqual(store.openMistakes.count, 1)
        XCTAssertEqual(saved.fen, friend.positions[4])
        XCTAssertEqual(saved.best, "f3h4")
        XCTAssertEqual(saved.played, "d2d3")
        XCTAssertEqual(saved.skill, "free-pieces")
        XCTAssertEqual(saved.created, friend.date)
        // Chess DNA counts both games now.
        XCTAssertEqual(ChessDNA.make(games: vault.games).gamesRead, 2)

        // Nothing waits any more: another go asks the engine nothing.
        let asked = await engine.searches.count
        await reader.run()
        let askedAgain = await engine.searches.count
        XCTAssertEqual(askedAgain, asked)
    }

    @MainActor
    func testGamesBroughtInAndUnfinishedGamesAreNotItsToRead() async {
        var imported = Self.person(Self.scholarsMate, daysAgo: 1)
        imported.source = "lichess"
        let unfinished = Self.person(Self.scholarsMate, result: .unfinished, daysAgo: 2)
        let vault = GameVault(games: [imported, unfinished])
        let engine = FakeEngine()
        let reader = QuietGrader(vault: vault, store: nil, engine: engine)
        reader.holdsBack = { false }
        await reader.run()
        let asked = await engine.searches
        XCTAssertTrue(asked.isEmpty)
        XCTAssertEqual(vault.games, [imported, unfinished])
    }

    @MainActor
    func testAHotPhoneLeavesTheGamesForLater() async {
        let friend = Self.person(Self.scholarsMate)
        let vault = GameVault(games: [friend])
        let engine = FakeEngine()
        let reader = QuietGrader(vault: vault, store: nil, engine: engine)
        reader.holdsBack = { true }
        await reader.run()
        let asked = await engine.searches
        XCTAssertTrue(asked.isEmpty)
        XCTAssertEqual(vault.game(friend.id)?.awaitsGrading, true)
        // Cooled down, the next go reads it.
        reader.holdsBack = { false }
        await reader.run()
        XCTAssertEqual(vault.game(friend.id)?.graded, true)
    }

    @MainActor
    func testAnEngineWithNothingToSayLeavesTheGameWaiting() async {
        let friend = Self.person(Self.queenLeft)
        let vault = GameVault(games: [friend])
        let reader = QuietGrader(vault: vault, store: nil, engine: FakeEngine(silent: true))
        reader.holdsBack = { false }
        // Comes back instead of asking for ever.
        await reader.run()
        XCTAssertEqual(vault.game(friend.id), friend)
    }

    @MainActor
    func testAGameThatCantBeReadDoesNotHoldUpTheOthers() async {
        var broken = Self.person(Self.scholarsMate, daysAgo: 0)
        broken.positions.swapAt(2, 4)
        let fine = Self.person(Self.scholarsMate, daysAgo: 1)
        let vault = GameVault(games: [broken, fine])
        let reader = QuietGrader(vault: vault, store: nil, engine: FakeEngine())
        reader.holdsBack = { false }
        await reader.run()
        XCTAssertEqual(vault.game(broken.id), broken)
        XCTAssertEqual(vault.game(fine.id)?.graded, true)
    }

    @MainActor
    func testALongBacklogIsReadALittleAtATime() async {
        let waiting = (0..<QuietGrader.atATime + 2).map { Self.person("e2e4 e7e5", daysAgo: Double($0)) }
        let vault = GameVault(games: waiting)
        let reader = QuietGrader(vault: vault, store: nil, engine: FakeEngine())
        reader.holdsBack = { false }
        await reader.run()
        XCTAssertEqual(vault.games.filter(\.awaitsGrading).count, 2)
        // Newest first: the two left are the oldest.
        XCTAssertEqual(vault.games.filter(\.awaitsGrading).map(\.id), waiting.suffix(2).map(\.id))
        await reader.run()
        XCTAssertTrue(vault.games.allSatisfy { !$0.awaitsGrading })
    }

    // MARK: The real engine, asked quietly

    /// A quiet search waits for a search somebody asked for instead of stopping it, then runs.
    func testAQuietSearchWaitsItsTurn() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let engine = StockfishEngine.shared
        await engine.warmUp()
        await engine.setCalm(.zero)
        addTeardownBlock { await StockfishEngine.shared.setCalm(StockfishEngine.usualCalm) }
        let start = Position.standard.fen
        // Somebody's analysis, and a quiet one asked for while it runs.
        async let wanted = engine.analyze(fen: start, depth: 16, lines: 1, maxTimeMs: 1500)
        try await Task.sleep(for: .milliseconds(150))
        // Watched from here on: whatever an earlier test left behind is dealt with by now.
        let traces = Traces()
        StockfishEngine.trace = { traces.add($0) }
        defer { StockfishEngine.trace = nil }
        let quiet = await engine.analyzeQuietly(fen: start, depth: 8, lines: 1, maxTimeMs: 2000)
        let lines = await wanted
        XCTAssertFalse(lines.isEmpty)
        let found = try XCTUnwrap(quiet, "With the engine free again, the quiet search runs")
        let move = try XCTUnwrap(found.first?.firstMove)
        XCTAssertNotNil(Notation.san(of: move, fen: start), "\(move) should be legal")
        XCTAssertEqual(traces.all.filter { $0.hasPrefix("stop search") }, [], "It stopped nobody")
    }

    /// A quiet search gives way the moment somebody asks for the engine, and says it was cut short.
    func testAQuietSearchGivesWayToOneSomebodyWaitsFor() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let engine = StockfishEngine.shared
        await engine.warmUp()
        await engine.setCalm(.zero)
        addTeardownBlock { await StockfishEngine.shared.setCalm(StockfishEngine.usualCalm) }
        let start = Position.standard.fen
        // A short search first, so the engine owes nothing to an earlier test.
        _ = await engine.chooseMove(fen: start, skill: 10, depth: 1, thinkTimeMs: 100)
        let before = await engine.quietSearches
        // Deep enough that it is still running when the move is asked for.
        let quiet = Task { await engine.analyzeQuietly(fen: start, depth: 60, lines: 1, maxTimeMs: 8000) }
        let waiting = ContinuousClock.now
        while await engine.quietSearches == before, ContinuousClock.now - waiting < .seconds(10) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let running = await engine.quietSearches
        XCTAssertEqual(running, before + 1, "The quiet search never started")

        let asked = ContinuousClock.now
        let move = await engine.chooseMove(fen: start, skill: 20, depth: 2, thinkTimeMs: 1000)
        let elapsed = ContinuousClock.now - asked
        XCTAssertNotNil(move)
        XCTAssertLessThan(elapsed, .seconds(3), "The move waited behind a search nobody was waiting on")
        let result = await quiet.value
        XCTAssertNil(result, "Cut short: its lines aren't as deep as asked, so it has no answer")
    }

    /// Quiet work keeps out of a game being played: it waits until the engine has been left alone.
    func testAQuietSearchWaitsUntilTheEngineHasBeenLeftAlone() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let engine = StockfishEngine.shared
        await engine.warmUp()
        await engine.setCalm(.milliseconds(600))
        addTeardownBlock { await StockfishEngine.shared.setCalm(StockfishEngine.usualCalm) }
        let start = Position.standard.fen
        _ = await engine.chooseMove(fen: start, skill: 20, depth: 2, thinkTimeMs: 500)
        let asked = ContinuousClock.now
        let quiet = await engine.analyzeQuietly(fen: start, depth: 4, lines: 1, maxTimeMs: 1000)
        let elapsed = ContinuousClock.now - asked
        XCTAssertNotNil(quiet)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(500), "It started while the engine was still in use")
    }

    private final class Traces: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }
}
