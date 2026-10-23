import ChessKit
import XCTest
@testable import ChessGameKiller

/// The Scouting Report: what the rivals learn from the player's saved games, and how they use it.
@MainActor
final class ScoutingTests: XCTestCase {

    private var sample: SavedGame { RewindSample.game() }

    private func positions(_ game: SavedGame) -> [String] { game.positions }

    // MARK: Reading the games

    func testTheReportRemembersWhereThePlayerWentWrong() {
        let game = sample
        let report = ScoutingReport.make(from: [game])
        XCTAssertEqual(report.gamesStudied, 1)
        // The mistake on move 6 (castling instead of Nxf7) and the blunder on move 8 (Nxh7).
        XCTAssertEqual(report.traps.count, 2)
        XCTAssertEqual(report.trap(at: game.positions[14])?.played, "Nxh7")
        XCTAssertEqual(report.trap(at: game.positions[10])?.playedUCI, "e1g1")
        // An inaccuracy is not a trap.
        XCTAssertNil(report.trap(at: game.positions[18]))
        let first = report.findings.first
        XCTAssertEqual(first?.kind, .trap)
        XCTAssertTrue(first?.line.contains("Move 8") == true, first?.line ?? "")
        XCTAssertTrue(first?.line.contains("Nxh7") == true, first?.line ?? "")
        XCTAssertEqual(first?.fen, game.positions[14])
        // One game is not enough for a full report.
        XCTAssertFalse(report.isReady)
    }

    func testTheReportIsReadyAfterThreeGames() {
        let report = ScoutingReport.make(from: (0..<3).map { _ in sample })
        XCTAssertTrue(report.isReady)
        XCTAssertLessThanOrEqual(report.findings.count, 3)
    }

    func testAHabitNeedsFiveGames() {
        let four = ScoutingReport.make(from: (0..<4).map { _ in sample })
        XCTAssertNil(four.findings.first { $0.kind == .opening })
        let five = ScoutingReport.make(from: (0..<5).map { _ in sample })
        let opening = five.findings.first { $0.kind == .opening }
        XCTAssertEqual(opening?.line, "You open with 1. e4 10 times in 10. I've prepared for it.")
        XCTAssertEqual(opening?.examples, 5)
    }

    func testUnfinishedAndFriendGamesAreNotRead() {
        var unfinished = sample
        unfinished.result = .unfinished
        let friend = SavedGame(id: UUID(), date: .now, opponent: "Friend", level: nil, playerIsWhite: true,
                               result: .loss, accuracy: nil, positions: sample.positions, moves: sample.moves,
                               moments: sample.moments)
        XCTAssertEqual(ScoutingReport.make(from: [unfinished, friend]), .empty)
    }

    func testTheNewestMistakeInAPositionWins() {
        let old = RewindSample.game(date: Date(timeIntervalSinceNow: -30 * 86_400))
        let new = RewindSample.game(date: .now)
        let report = ScoutingReport.make(from: [old, new])
        XCTAssertEqual(report.trap(at: new.positions[14])?.gameID, new.id)
    }

    func testPhasesAreToldApartByTheMoveAndThePieces() {
        XCTAssertEqual(ScoutingReport.Phase.of(Position.standard.fen), .opening)
        XCTAssertEqual(ScoutingReport.Phase.of("r1bq1rk1/pp3ppp/2n2n2/3p4/3P4/2N2N2/PP3PPP/R1BQ1RK1 w - - 0 14"), .middlegame)
        XCTAssertEqual(ScoutingReport.Phase.of("4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 30"), .endgame)
    }

    func testWhenReadsLikeSpeech() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_800_000)   // a Friday
        XCTAssertEqual(ScoutingReport.when(now, now: now, calendar: calendar), "today")
        XCTAssertEqual(ScoutingReport.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar), "yesterday")
        XCTAssertTrue(ScoutingReport.when(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar).hasPrefix("on "))
        XCTAssertFalse(ScoutingReport.when(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar).contains(" 20"))
    }

    // MARK: Steering

    func testTheRivalStepsIntoATrapWhenItCostsLittle() {
        let game = sample
        let report = ScoutingReport.make(from: [game])
        // Black to move before castling (ply 14): castling puts White where it played Nxh7.
        let fen = game.positions[13]
        let lines = [EngineLine(moves: ["c8e6"], evaluation: .centipawns(20)),
                     EngineLine(moves: ["e8g8"], evaluation: .centipawns(0))]
        let steer = report.steer(fen: fen, lines: lines, chosen: "c8e6", tolerance: 30)
        XCTAssertEqual(steer?.uci, "e8g8")
        XCTAssertEqual(steer?.trap.played, "Nxh7")
        // A rival that gives nothing away keeps its own move.
        XCTAssertNil(report.steer(fen: fen, lines: lines, chosen: "c8e6", tolerance: 15))
    }

    func testTheRivalLooksThreeMovesAheadThroughThePlayersUsualAnswer() {
        let game = sample
        let report = ScoutingReport.make(from: [game])
        // Black to move before ...Be7 (ply 12): after it the player usually plays Re1,
        // and then castling reaches the trap.
        let fen = game.positions[11]
        let lines = [EngineLine(moves: ["f8c5"], evaluation: .centipawns(10)),
                     EngineLine(moves: ["f8e7"], evaluation: .centipawns(0))]
        XCTAssertEqual(report.steer(fen: fen, lines: lines, chosen: "f8c5", tolerance: 30)?.uci, "f8e7")
    }

    func testNoTrapsNoSteering() {
        let fen = Position.standard.fen
        let lines = [EngineLine(moves: ["e2e4"], evaluation: .centipawns(30))]
        XCTAssertNil(ScoutingReport.empty.steer(fen: fen, lines: lines, chosen: "e2e4", tolerance: 60))
    }

    // MARK: In a game

    func testTheRivalSetsTheTrapAndNoticesTheSameMistake() async throws {
        let game = sample
        let trapFEN = game.positions[14]
        let engine = FakeEngine(scripted: [
            game.positions[13]: [EngineLine(moves: ["c8e6"], evaluation: .centipawns(20)),
                                 EngineLine(moves: ["e8g8"], evaluation: .centipawns(0))],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.studyGames = { [game] }
        var results: [Bool] = []
        match.onTrapResult = { _, fell, _ in results.append(fell) }
        let start = try XCTUnwrap(Position(fen: game.positions[12]))
        match.start(.init(opponent: .computer, playerColor: .white, level: .club), from: start)
        XCTAssertEqual(match.scouting.traps.count, 2)

        match.tap(Square("f1"))
        match.tap(Square("e1"))
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while match.trapSprung == nil, clock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(TrainingChess.key(match.game.fen), TrainingChess.key(trapFEN))
        XCTAssertEqual(match.trapSprung?.played, "Nxh7")
        XCTAssertNotNil(match.rivalLine)
        XCTAssertEqual(match.trapsThisGame.sprung, 1)

        // The same knight sacrifice again.
        match.tap(Square("g5"))
        match.tap(Square("h7"))
        XCTAssertEqual(results, [true])
        XCTAssertNil(match.trapSprung)
        XCTAssertEqual(match.trapsThisGame.dodged, 0)
    }

    func testTheLedgerKeepsTheLastDuelPerRival() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ScoutingTests"))
        defaults.removePersistentDomain(forName: "ScoutingTests")
        let trap = try XCTUnwrap(ScoutingReport.make(from: [sample]).trap(at: sample.positions[14]))
        ScoutingLedger.record(trap, fell: false, level: .club, defaults: defaults)
        XCTAssertEqual(ScoutingLedger.last(for: .club, defaults: defaults)?.fell, false)
        XCTAssertEqual(ScoutingLedger.last(for: .club, defaults: defaults)?.moveNumber, 8)
        XCTAssertNil(ScoutingLedger.last(for: .expert, defaults: defaults))
    }
}
