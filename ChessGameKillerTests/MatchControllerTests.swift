import ChessKit
import XCTest
@testable import ChessGameKiller

/// A stand-in engine with scripted answers. Unscripted positions get the
/// first legal moves it finds, scored as equal.
actor FakeEngine: ChessEngine {
    private let scripted: [String: [EngineLine]]
    private(set) var analyzed: [String] = []
    /// How many of the next move requests get no answer, like a search the real engine dropped.
    private var missedMoves: Int
    /// An engine that never answers anything.
    private let silent: Bool
    private(set) var moveRequests = 0

    /// The score given to unscripted positions, for the side to move.
    private let score: Int

    init(scripted: [String: [EngineLine]] = [:], missedMoves: Int = 0, silent: Bool = false, score: Int = 0) {
        self.scripted = scripted
        self.score = score
        self.missedMoves = missedMoves
        self.silent = silent
    }

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        analyzed.append(fen)
        if silent { return [] }
        if let lines = scripted[fen] { return lines }
        return Self.legalMoves(fen: fen).prefix(lines).map { EngineLine(moves: [$0], evaluation: .centipawns(score)) }
    }

    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String? {
        moveRequests += 1
        if silent { return nil }
        if missedMoves > 0 {
            missedMoves -= 1
            return nil
        }
        if let line = scripted[fen]?.first { return line.firstMove }
        return Self.legalMoves(fen: fen).first
    }

    static func legalMoves(fen: String) -> [String] {
        guard let position = Position(fen: fen) else { return [] }
        let board = Board(position: position)
        return position.pieces
            .filter { $0.color == position.sideToMove }
            .sorted { $0.square.rawValue < $1.square.rawValue }
            .flatMap { piece in
                board.legalMoves(forPieceAt: piece.square).map { piece.square.notation + $0.notation }
            }
    }
}

extension MatchController {
    /// A game whose moves the test taps out for both sides: the computer never answers.
    func startTapping(_ setup: Setup = Setup(), from position: Position = .standard) {
        start(setup, from: position)
        game.humanColors = [.white, .black]
    }
}

@MainActor
final class SilentSounds: SoundPlaying {
    private(set) var played: [GameSound] = []
    func play(_ sound: GameSound) { played.append(sound) }
}

@MainActor
final class MatchControllerTests: XCTestCase {

    private func waitUntil(
        _ what: String,
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async {
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

    private func fen(after moves: String...) -> String {
        let game = GameModel()
        for move in moves { XCTAssertTrue(game.playEngineMove(move), "\(move) should be legal") }
        return game.fen
    }

    private func tapMove(_ match: MatchController, _ move: String) {
        match.tap(Square(String(move.prefix(2))))
        match.tap(Square(String(move.suffix(2))))
    }

    func testShowsTwoBestMovesForThePlayer() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }
        XCTAssertEqual(match.hints.map(\.rank), [0, 1])
        XCTAssertFalse(match.hints[0].san.isEmpty)
    }

    func testHidingBestMovesClearsTheHints() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }
        match.showBestMoves = false
        XCTAssertTrue(match.hints.isEmpty)
        match.showBestMoves = true
        XCTAssertEqual(match.hints.count, 2)
    }

    func testPlayingTheTopMoveIsGradedBest() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [
            start: [
                EngineLine(moves: ["e2e4", "e7e5"], evaluation: .centipawns(30)),
                EngineLine(moves: ["d2d4", "d7d5"], evaluation: .centipawns(25)),
            ],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }

        tapMove(match, "e2e4")
        await waitUntil("the move is reviewed") { match.review != nil }
        XCTAssertEqual(match.review?.grade, .best)
        XCTAssertEqual(match.review?.played, "e4")
        XCTAssertNil(match.review?.best)
    }

    func testABadMoveIsGradedAndTheBetterMoveNamed() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [
            start: [
                EngineLine(moves: ["e2e4"], evaluation: .centipawns(30)),
                EngineLine(moves: ["d2d4"], evaluation: .centipawns(25)),
            ],
            // After 1. a3 the engine likes Black's position a lot (from Black's side).
            fen(after: "a2a3"): [EngineLine(moves: ["e7e5"], evaluation: .centipawns(250))],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }

        tapMove(match, "a2a3")
        await waitUntil("the move is reviewed") { match.review != nil }
        XCTAssertEqual(match.review?.grade, .blunder)
        XCTAssertEqual(match.review?.best, "e4")
        XCTAssertEqual(match.review?.evaluation, .centipawns(-250))
    }

    func testComputerRepliesAndPlayerCanMoveAgain() async {
        let sounds = SilentSounds()
        let match = MatchController(engine: FakeEngine(), sounds: sounds)
        match.start(.init(opponent: .computer, playerColor: .white, level: .beginner))
        tapMove(match, "e2e4")
        XCTAssertFalse(match.game.isHumanTurn)

        await waitUntil("the computer replies") { match.game.plyCount == 2 }
        XCTAssertTrue(match.game.isHumanTurn)
        XCTAssertFalse(match.isComputerThinking)
        XCTAssertEqual(sounds.played.filter { $0 == .move }.count, 2)
        await waitUntil("hints appear for the player") { match.hints.count == 2 }
    }

    func testComputerOpensWhenThePlayerTakesBlack() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black, level: .club))
        XCTAssertTrue(match.isBoardFlipped)
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.sideToMove, .black)
    }

    func testCannotMoveTheComputersPieces() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black))
        tapMove(match, "e2e4")
        XCTAssertEqual(match.game.plyCount, 0)
    }

    func testUndoAgainstTheComputerTakesBackBothMoves() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .white))
        tapMove(match, "e2e4")
        await waitUntil("the computer replies") { match.game.plyCount == 2 }

        match.undo()
        XCTAssertEqual(match.game.plyCount, 0)
        XCTAssertTrue(match.game.isHumanTurn)
    }

    func testCapturesAreRecordedForTheFall() {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping()
        for move in ["e2e4", "d7d5", "e4d5"] { tapMove(match, move) }
        XCTAssertEqual(match.game.captureEvents.count, 1)
        XCTAssertEqual(match.game.captureEvents.first?.piece.kind, .pawn)
        XCTAssertEqual(match.game.captureEvents.first?.piece.square, .d5)
        // It falls away from the pawn that took it.
        XCTAssertEqual(match.game.captureEvents.first?.from, .e4)
        XCTAssertEqual(match.game.lastPlayed?.san, "exd5")
        XCTAssertTrue(match.game.lastPlayed?.isCapture == true)
    }

    func testCaptureAndCheckSounds() {
        let sounds = SilentSounds()
        let match = MatchController(engine: nil, sounds: sounds)
        match.startTapping()
        XCTAssertTrue(sounds.played.isEmpty, "a game starts quietly")
        for move in ["e2e4", "d7d5", "e4d5"] { tapMove(match, move) }
        XCTAssertEqual(sounds.played.last, .capture)
        for move in ["e7e6", "f1b5"] { tapMove(match, move) }
        XCTAssertEqual(sounds.played.last, .check)
    }

    func testCheckmateIsReviewedAsCheckmate() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.startTapping()
        for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { tapMove(match, move) }
        XCTAssertEqual(match.game.winner, .black)
        await waitUntil("the mate is reviewed") { match.review?.grade == .checkmate }
    }

    func testSavedSetupReadsLastChoices() {
        let defaults = UserDefaults(suiteName: "MatchControllerTests")!
        defaults.removePersistentDomain(forName: "MatchControllerTests")
        XCTAssertEqual(NewGameSheet.savedSetup(defaults).timeControl, .unlimited)
        // A friend game picked before pass-and-play was removed is ignored.
        defaults.set("friend", forKey: "setup.opponent")
        defaults.set("black", forKey: "setup.side")
        defaults.set(MatchController.Level.expert.rawValue, forKey: "setup.level")
        defaults.set("5+0", forKey: "setup.clock")
        let setup = NewGameSheet.savedSetup(defaults)
        XCTAssertEqual(setup.opponent, .computer)
        XCTAssertEqual(setup.playerColor, .black)
        XCTAssertEqual(setup.level, .expert)
        XCTAssertEqual(setup.timeControl, .blitz5)
    }

    func testOnlyTheBestHintWhenTheSecondIsOff() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.showSecondBest = false
        match.startTapping()
        await waitUntil("the hint appears") { match.hints.count == 1 }
        XCTAssertEqual(match.hints.map(\.rank), [0])
        match.showSecondBest = true
        XCTAssertEqual(match.hints.count, 2)
    }

    func testPlayingAHintMakesTheMove() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }
        let hint = match.hints[0]
        match.play(hint)
        XCTAssertEqual(match.game.plyCount, 1)
        XCTAssertEqual(match.game.moves, [hint.san])
        XCTAssertEqual(match.game.sideToMove, .black)
    }

    func testTimedGameRunsTheClockForTheSideToMove() {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping(.init(timeControl: .blitz5))
        XCTAssertEqual(match.clock?.running, .white)
        XCTAssertEqual(match.clock?.remaining(for: .black), .seconds(300))

        tapMove(match, "e2e4")
        XCTAssertEqual(match.clock?.running, .black)
        match.undo()
        XCTAssertEqual(match.clock?.running, .white)

        match.startTapping()
        XCTAssertNil(match.clock)
    }

    func testFlipTurnsTheBoardAround() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black))
        XCTAssertTrue(match.isBoardFlipped)
        match.flipBoard()
        XCTAssertFalse(match.isBoardFlipped)
        match.start(.init(opponent: .computer, playerColor: .black))
        XCTAssertTrue(match.isBoardFlipped, "a new game puts the player's side back at the bottom")
    }

    func testTheComputerAnswersBeforeTheMoveIsGraded() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [
            start: [
                EngineLine(moves: ["e2e4"], evaluation: .centipawns(30)),
                EngineLine(moves: ["d2d4"], evaluation: .centipawns(25)),
            ],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .white))
        await waitUntil("hints appear") { match.hints.count == 2 }

        tapMove(match, "e2e4")
        await waitUntil("the computer replies") { match.game.moveCount == 2 }
        await waitUntil("the move is reviewed") { match.review != nil }
        XCTAssertEqual(match.review?.played, "e4")
        // The verdict describes the position the person's move made, not the reply.
        XCTAssertEqual(match.review?.fenAfter, fen(after: "e2e4"))
        XCTAssertEqual(match.game.sideToMove, .white)
    }

    func testEveryStartCountsAGame() {
        let match = MatchController(engine: nil, sounds: nil)
        XCTAssertEqual(match.gameNumber, 0)
        match.startTapping()
        match.rematch()
        XCTAssertEqual(match.gameNumber, 2)
    }

    func testAFinishedGameCannotBeUndone() {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping()
        for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { tapMove(match, move) }
        XCTAssertTrue(match.isOver)
        XCTAssertFalse(match.canUndo)
        match.undo()
        XCTAssertEqual(match.game.plyCount, 4)
    }

    func testATakenBackMoveLeavesTheSummary() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [
            start: [
                EngineLine(moves: ["e2e4"], evaluation: .centipawns(30)),
                EngineLine(moves: ["d2d4"], evaluation: .centipawns(25)),
            ],
            fen(after: "a2a3"): [EngineLine(moves: ["e7e5"], evaluation: .centipawns(250))],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }

        tapMove(match, "a2a3")
        await waitUntil("the move is reviewed") { match.review?.grade == .blunder }
        XCTAssertEqual(match.gradeCounts[.blunder], 1)
        XCTAssertEqual(match.accuracy, 10)

        match.undo()
        XCTAssertTrue(match.gradeCounts.isEmpty)
        XCTAssertNil(match.accuracy)
    }

    func testUndoGivesBackTheIncrementOfTheUndoneMove() {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping(.init(timeControl: .blitz3Plus2))
        tapMove(match, "e2e4")
        match.undo()
        let left = match.clock?.remaining(for: .white) ?? .zero
        XCTAssertLessThanOrEqual(left, .seconds(180), "the two seconds for e4 must come off again")
        XCTAssertGreaterThan(left, .seconds(170))
        XCTAssertEqual(match.clock?.running, .white)
    }

    func testFlagFallIsADrawWhenTheOtherSideCannotMate() throws {
        let sounds = SilentSounds()
        let match = MatchController(engine: nil, sounds: sounds)
        // White has a queen, Black only a king: if White's flag falls, Black could never have won.
        let position = try XCTUnwrap(Position(fen: "k7/8/8/8/8/8/8/KQ6 w - - 0 1"))
        match.startTapping(.init(timeControl: .blitz5), from: position)
        match.flagFell(.white)
        XCTAssertEqual(match.outcome, .timeoutDraw(flagged: .white))
        XCTAssertNil(match.winner)
        XCTAssertTrue(match.isOver)
        XCTAssertEqual(sounds.played.last, .gameOver)
    }

    func testFlagFallIsALossWhenTheOtherSideCanMate() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: "k6r/8/8/8/8/8/8/KQ6 w - - 0 1"))
        match.startTapping(.init(timeControl: .blitz5), from: position)
        match.flagFell(.white)
        XCTAssertEqual(match.outcome, .timeout(loser: .white))
        XCTAssertEqual(match.winner, .black)
    }

    func testMatingMaterial() throws {
        func canMate(_ fen: String, _ color: Piece.Color = .white) throws -> Bool {
            let position = try XCTUnwrap(Position(fen: fen))
            return MatchController.hasMatingMaterial(position.pieces, for: color)
        }
        XCTAssertFalse(try canMate("k7/8/8/8/8/8/8/K7 w - - 0 1"))
        XCTAssertFalse(try canMate("k7/8/8/8/8/8/8/KN6 w - - 0 1"))
        XCTAssertFalse(try canMate("k7/8/8/8/8/8/8/KB6 w - - 0 1"))
        // Two bishops on light squares.
        XCTAssertFalse(try canMate("k7/8/8/8/8/8/8/KB1B4 w - - 0 1"))
        // Bishops on both colours, a knight with a bishop, two knights, or any pawn.
        XCTAssertTrue(try canMate("k7/8/8/8/8/8/8/KBB5 w - - 0 1"))
        XCTAssertTrue(try canMate("k7/8/8/8/8/8/8/KNB5 w - - 0 1"))
        XCTAssertTrue(try canMate("k7/8/8/8/8/8/8/KNN5 w - - 0 1"))
        XCTAssertTrue(try canMate("k7/8/8/8/8/8/P7/K7 w - - 0 1"))
        XCTAssertTrue(try canMate("k6r/8/8/8/8/8/8/K7 w - - 0 1", .black))
    }

    func testAFlagDuringPromotionPutsThePawnBack() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: "7k/P7/8/8/8/8/8/K7 w - - 0 1"))
        match.startTapping(.init(timeControl: .blitz5), from: position)
        tapMove(match, "a7a8")
        XCTAssertNotNil(match.game.pendingPromotion)

        match.flagFell(.white)
        XCTAssertNil(match.game.pendingPromotion)
        XCTAssertEqual(match.game.piece(at: .a7)?.kind, .pawn)
        XCTAssertEqual(match.outcome, .timeoutDraw(flagged: .white))
    }

    func testASuspendedClockStaysStoppedThroughTheComputersReply() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .white, timeControl: .blitz5))
        tapMove(match, "e2e4")
        XCTAssertEqual(match.clock?.running, .black)

        match.suspendClock()
        XCTAssertNil(match.clock?.running)
        await waitUntil("the computer replies") { match.game.plyCount == 2 }
        XCTAssertNil(match.clock?.running, "the reply must not restart a held clock")

        match.resumeClock()
        XCTAssertEqual(match.clock?.running, .white)
    }

    func testResumingTheClockOfAFinishedGameDoesNothing() {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping(.init(timeControl: .blitz5))
        for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { tapMove(match, move) }
        match.suspendClock()
        match.resumeClock()
        XCTAssertNil(match.clock?.running)
    }

    func testSparkSometimesPlaysAnyLegalMove() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [start: [EngineLine(moves: ["e2e4"], evaluation: .centipawns(30))]])
        let match = MatchController(engine: engine, sounds: nil)
        // Always slip, and take the first legal move in notation order.
        match.chance = { 0 }
        match.start(.init(opponent: .computer, playerColor: .black, level: .beginner))
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.moves, ["a3"])
        XCTAssertEqual(match.game.sideToMove, .black)
        XCTAssertFalse(match.engineFailed)
    }

    /// Alex played Spark with Spark as white and nothing moved: the engine's first
    /// answer went missing and the game sat on "Engine unavailable" for good.
    func testTheComputerOpensAsWhiteEvenWhenTheEngineMissesAnAnswer() async {
        for level in MatchController.Level.allCases {
            let engine = FakeEngine(missedMoves: 2)
            let match = MatchController(engine: engine, sounds: nil)
            match.chance = { 0.99 }
            match.start(.init(opponent: .computer, playerColor: .black, level: level))
            await waitUntil("\(level) opens") { match.game.plyCount == 1 }
            XCTAssertEqual(match.game.sideToMove, .black, "\(level)")
            XCTAssertFalse(match.engineFailed, "\(level) shouldn't say the engine is unavailable")
            let requests = await engine.moveRequests
            XCTAssertEqual(requests, 3, "\(level) should ask again after a missed answer")
        }
    }

    /// With no engine answer at all, the rival still moves rather than freezing the game.
    func testTheComputerStillMovesWhenTheEngineIsSilent() async {
        let match = MatchController(engine: FakeEngine(silent: true), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black, level: .beginner))
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.sideToMove, .black)
        tapMove(match, "e7e5")
        await waitUntil("the computer answers") { match.game.plyCount == 3 }
    }

    /// The fallback takes what is hanging rather than shuffling pieces.
    func testTheFallbackMoveTakesAHangingQueen() async {
        // White to move; the black queen on d5 is free for the knight on c3.
        let position = Position(fen: "4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1")!
        let match = MatchController(engine: FakeEngine(silent: true), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black, level: .club), from: position)
        await waitUntil("the computer moves") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.moves, ["Nxd5"])
    }

    func testThePersonCanResign() async {
        let sounds = SilentSounds()
        let match = MatchController(engine: FakeEngine(), sounds: sounds)
        match.start(.init(opponent: .computer, playerColor: .white, level: .club))
        XCTAssertFalse(match.canResign, "nothing to resign before the first move")
        tapMove(match, "e2e4")
        await waitUntil("the computer answers") { match.game.plyCount == 2 }
        match.resign()
        XCTAssertEqual(match.outcome, .resigned(loser: .white))
        XCTAssertEqual(match.winner, .black)
        XCTAssertTrue(match.isOver)
        XCTAssertEqual(sounds.played.last, .gameOver)
        XCTAssertFalse(match.canResign)
    }

    func testAHopelessRivalResignsAndTheVictoryThemePlays() async {
        let sounds = SilentSounds()
        // Every position scores 20 pawns for the person on their turn.
        let match = MatchController(engine: FakeEngine(score: 2000), sounds: sounds)
        match.start(.init(opponent: .computer, playerColor: .white, level: .club))
        await waitUntil("the first look at the position") { match.evaluation != nil }
        XCTAssertNil(match.outcome, "one bad look isn't enough to resign")
        tapMove(match, "e2e4")
        await waitUntil("the rival resigns") { match.outcome != nil }
        XCTAssertEqual(match.outcome, .resigned(loser: .black))
        XCTAssertEqual(match.winner, .white)
        XCTAssertEqual(sounds.played.last, .victory)
    }

    func testCheckmatingTheRivalPlaysTheVictoryTheme() async {
        let sounds = SilentSounds()
        let match = MatchController(engine: FakeEngine(), sounds: sounds)
        match.startTapping()
        for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { tapMove(match, move) }
        XCTAssertEqual(match.winner, .black)
        XCTAssertEqual(sounds.played.last, .victory)
    }

    func testEveryRivalHasSomethingToSay() {
        let moments: [RivalMoment] = [
            .greeting, .tookPiece(.knight), .lostPiece(.queen), .givesCheck, .playerBlunder,
            .playerGreatMove, .rivalResigns, .rivalWins, .playerWins, .draw,
        ]
        for level in MatchController.Level.allCases {
            for moment in moments {
                for pick in [0, 0.5, 0.999] {
                    let line = RivalVoice.line(for: moment, level: level, pick: pick)
                    XCTAssertNotNil(line, "\(level.rival.name) says nothing for \(moment)")
                    XCTAssertLessThanOrEqual(line?.count ?? 0, 48, "too long for the bubble: \(line ?? "")")
                }
            }
        }
        XCTAssertEqual(RivalVoice.line(for: .tookPiece(.rook), level: .beginner, pick: 0), "Yay, I got your rook!")
    }

    func testTheRivalGreetsAndReactsToACapture() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.chance = { 0.1 }
        match.start(.init(opponent: .computer, playerColor: .white, level: .beginner))
        XCTAssertNotNil(match.rivalLine, "the rival says hello")
        let hello = match.rivalLine
        tapMove(match, "e2e4")
        await waitUntil("the rival answers") { match.game.plyCount == 2 }
        // A big moment always gets a line: taking the queen.
        let position = Position(fen: "4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1")!
        match.start(.init(opponent: .computer, playerColor: .white, level: .beginner), from: position)
        XCTAssertNotEqual(match.rivalLine, hello)
        tapMove(match, "e4d5")
        XCTAssertEqual(match.rivalLine?.text.contains("queen"), true, "\(match.rivalLine?.text ?? "nothing")")
    }

    func testStrongerRivalsAlwaysPlayTheEnginesMove() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [start: [EngineLine(moves: ["e2e4"], evaluation: .centipawns(30))]])
        let match = MatchController(engine: engine, sounds: nil)
        match.chance = { 0 }
        match.start(.init(opponent: .computer, playerColor: .black, level: .club))
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.moves, ["e4"])
    }

    func testHintsAreTurnedOffOnceForEveryone() {
        let defaults = UserDefaults(suiteName: "hints-\(UUID().uuidString)")!
        defaults.set(true, forKey: "showBestMoves")
        HintsIntroduction.applyOnce(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: "showBestMoves"))
        // Turned back on by the player, they stay on.
        defaults.set(true, forKey: "showBestMoves")
        HintsIntroduction.applyOnce(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "showBestMoves"))
    }
}
