import ChessKit
import XCTest
@testable import ChessGameKiller

/// A stand-in engine with scripted answers. Unscripted positions get the
/// first legal moves it finds, scored as equal.
actor FakeEngine: ChessEngine {
    private let scripted: [String: [EngineLine]]
    private(set) var analyzed: [String] = []

    init(scripted: [String: [EngineLine]] = [:]) {
        self.scripted = scripted
    }

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        analyzed.append(fen)
        if let lines = scripted[fen] { return lines }
        return Self.legalMoves(fen: fen).prefix(lines).map { EngineLine(moves: [$0], evaluation: .centipawns(0)) }
    }

    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String? {
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
        match.start(.init(opponent: .friend), playSound: false)
        await waitUntil("hints appear") { match.hints.count == 2 }
        XCTAssertEqual(match.hints.map(\.rank), [0, 1])
        XCTAssertFalse(match.hints[0].san.isEmpty)
    }

    func testHidingBestMovesClearsTheArrows() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .friend), playSound: false)
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
        match.start(.init(opponent: .friend), playSound: false)
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
        match.start(.init(opponent: .friend), playSound: false)
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
        match.start(.init(opponent: .computer, playerColor: .white, level: .beginner), playSound: false)
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
        match.start(.init(opponent: .computer, playerColor: .black, level: .club), playSound: false)
        XCTAssertTrue(match.isBoardFlipped)
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.sideToMove, .black)
    }

    func testCannotMoveTheComputersPieces() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black), playSound: false)
        tapMove(match, "e2e4")
        XCTAssertEqual(match.game.plyCount, 0)
    }

    func testUndoAgainstTheComputerTakesBackBothMoves() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .white), playSound: false)
        tapMove(match, "e2e4")
        await waitUntil("the computer replies") { match.game.plyCount == 2 }

        match.undo()
        XCTAssertEqual(match.game.plyCount, 0)
        XCTAssertTrue(match.game.isHumanTurn)
    }

    func testCapturesAreRecordedForTheExplosion() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .friend), playSound: false)
        for move in ["e2e4", "d7d5", "e4d5"] { tapMove(match, move) }
        XCTAssertEqual(match.game.captureEvents.count, 1)
        XCTAssertEqual(match.game.captureEvents.first?.piece.kind, .pawn)
        XCTAssertEqual(match.game.captureEvents.first?.piece.square, .d5)
        XCTAssertEqual(match.game.lastPlayed?.san, "exd5")
        XCTAssertTrue(match.game.lastPlayed?.isCapture == true)
    }

    func testCaptureAndCheckSounds() {
        let sounds = SilentSounds()
        let match = MatchController(engine: nil, sounds: sounds)
        match.start(.init(opponent: .friend), playSound: true)
        XCTAssertEqual(sounds.played.last, .gameStart)
        for move in ["e2e4", "d7d5", "e4d5"] { tapMove(match, move) }
        XCTAssertEqual(sounds.played.last, .capture)
        for move in ["e7e6", "f1b5"] { tapMove(match, move) }
        XCTAssertEqual(sounds.played.last, .check)
    }

    func testCheckmateIsReviewedAsCheckmate() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .friend), playSound: false)
        for move in ["f2f3", "e7e5", "g2g4", "d8h4"] { tapMove(match, move) }
        XCTAssertEqual(match.game.winner, .black)
        await waitUntil("the mate is reviewed") { match.review?.grade == .checkmate }
    }

    func testSavedSetupReadsLastChoices() {
        let defaults = UserDefaults(suiteName: "MatchControllerTests")!
        defaults.removePersistentDomain(forName: "MatchControllerTests")
        XCTAssertEqual(NewGameSheet.savedSetup(defaults).opponent, .computer)
        XCTAssertEqual(NewGameSheet.savedSetup(defaults).timeControl, .unlimited)
        defaults.set("friend", forKey: "setup.opponent")
        defaults.set("black", forKey: "setup.side")
        defaults.set(MatchController.Level.expert.rawValue, forKey: "setup.level")
        defaults.set("5+0", forKey: "setup.clock")
        let setup = NewGameSheet.savedSetup(defaults)
        XCTAssertEqual(setup.opponent, .friend)
        XCTAssertEqual(setup.playerColor, .black)
        XCTAssertEqual(setup.level, .expert)
        XCTAssertEqual(setup.timeControl, .blitz5)
    }

    func testOnlyTheBestArrowWhenTheSecondIsOff() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.showSecondBest = false
        match.start(.init(opponent: .friend), playSound: false)
        await waitUntil("the hint appears") { match.hints.count == 1 }
        XCTAssertEqual(match.hints.map(\.rank), [0])
        match.showSecondBest = true
        XCTAssertEqual(match.hints.count, 2)
    }

    func testPlayingAHintMakesTheMove() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(.init(opponent: .friend), playSound: false)
        await waitUntil("hints appear") { match.hints.count == 2 }
        let hint = match.hints[0]
        match.play(hint)
        XCTAssertEqual(match.game.plyCount, 1)
        XCTAssertEqual(match.game.moves, [hint.san])
        XCTAssertEqual(match.game.sideToMove, .black)
    }

    func testTimedGameRunsTheClockForTheSideToMove() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .friend, timeControl: .blitz5), playSound: false)
        XCTAssertEqual(match.clock?.running, .white)
        XCTAssertEqual(match.clock?.remaining(for: .black), .seconds(300))

        tapMove(match, "e2e4")
        XCTAssertEqual(match.clock?.running, .black)
        match.undo()
        XCTAssertEqual(match.clock?.running, .white)

        match.start(.init(opponent: .friend), playSound: false)
        XCTAssertNil(match.clock)
    }

    func testFlipTurnsTheBoardAround() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(.init(opponent: .computer, playerColor: .black), playSound: false)
        XCTAssertTrue(match.isBoardFlipped)
        match.flipBoard()
        XCTAssertFalse(match.isBoardFlipped)
        match.start(.init(opponent: .computer, playerColor: .black), playSound: false)
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
        match.start(.init(opponent: .computer, playerColor: .white), playSound: false)
        await waitUntil("hints appear") { match.hints.count == 2 }

        tapMove(match, "e2e4")
        await waitUntil("the computer replies") { match.game.moveCount == 2 }
        await waitUntil("the move is reviewed") { match.review != nil }
        XCTAssertEqual(match.review?.played, "e4")
        // The verdict describes the position the person's move made, not the reply.
        XCTAssertEqual(match.review?.fenAfter, fen(after: "e2e4"))
        XCTAssertEqual(match.game.sideToMove, .white)
    }
}
