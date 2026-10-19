import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class ArmyTests: XCTestCase {

    private func play(_ game: GameModel, _ moves: String...) {
        for move in moves {
            XCTAssertTrue(game.playEngineMove(move), "\(move) should be legal")
        }
    }

    // MARK: Following pieces through a game

    func testOnlyStandardStartsAreFollowed() {
        XCTAssertNotNil(GameModel().ledger)
        let position = Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")!
        XCTAssertNil(GameModel(position: position).ledger)
    }

    func testCaptureIsCreditedToTheCapturer() {
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5")
        let ledger = game.ledger!
        XCTAssertEqual(ledger.origin(of: .d5), .e2)
        XCTAssertEqual(ledger.stats(forPieceStartingOn: .e2).captures, 1)
        XCTAssertEqual(ledger.stats(forPieceStartingOn: .e2).captureValue, 1)
        XCTAssertEqual(ledger.stats(forPieceStartingOn: .e2).moves, 2)
        XCTAssertTrue(ledger.stats(forPieceStartingOn: .d7).fell)
    }

    func testCastlingMovesKingAndRook() {
        let game = GameModel()
        play(game, "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "e1g1")
        let ledger = game.ledger!
        XCTAssertEqual(ledger.origin(of: .g1), .e1)
        XCTAssertEqual(ledger.origin(of: .f1), .h1)
        XCTAssertEqual(ledger.origin(of: .f3), .g1)
        XCTAssertEqual(ledger.stats(forPieceStartingOn: .e1).moves, 1)
    }

    func testEnPassantCreditsThePawn() {
        let game = GameModel()
        play(game, "e2e4", "a7a6", "e4e5", "d7d5", "e5d6")
        let ledger = game.ledger!
        XCTAssertEqual(ledger.origin(of: .d6), .e2)
        XCTAssertEqual(ledger.stats(forPieceStartingOn: .e2).captures, 1)
        XCTAssertTrue(ledger.stats(forPieceStartingOn: .d7).fell)
    }

    func testPromotedPawnKeepsItsMemory() {
        let game = GameModel()
        play(game, "h2h4", "g7g5", "h4g5", "g8f6", "g5f6", "h8g8", "f6e7", "g8g7", "e7d8q")
        let ledger = game.ledger!
        XCTAssertEqual(game.piece(at: .d8)?.kind, .queen)
        XCTAssertEqual(ledger.origin(of: .d8), .h2)
        let stats = ledger.stats(forPieceStartingOn: .h2)
        XCTAssertTrue(stats.promoted)
        XCTAssertEqual(stats.captures, 4)
        XCTAssertEqual(stats.captureValue, 1 + 3 + 1 + 9)
    }

    func testMateIsCreditedToTheMatingPiece() {
        let game = GameModel()
        play(game, "f2f3", "e7e5", "g2g4", "d8h4")
        XCTAssertTrue(game.ledger!.stats(forPieceStartingOn: .d8).gaveMate)
    }

    func testUndoRestoresTheLedger() {
        let game = GameModel()
        play(game, "e2e4", "d7d5")
        let before = game.ledger
        play(game, "e4d5")
        game.undo()
        XCTAssertEqual(game.ledger, before)
    }

    // MARK: The army

    func testSlotsMatchStartingSquares() {
        XCTAssertEqual(ArmySlot.kingsKnight.square(for: .white), .g1)
        XCTAssertEqual(ArmySlot.kingsKnight.square(for: .black), .g8)
        XCTAssertEqual(ArmySlot.ePawn.square(for: .black), .e7)
        XCTAssertEqual(ArmySlot(start: .d8, color: .black), .queen)
        XCTAssertEqual(ArmySlot.kingsKnight.kind, .knight)
        XCTAssertEqual(ArmySlot.aPawn.kind, .pawn)
        XCTAssertNil(ArmySlot(start: .e4, color: .white))
    }

    func testRanksFollowExperience() {
        XCTAssertEqual(ArmyRank.forXP(0), .recruit)
        XCTAssertEqual(ArmyRank.forXP(25), .veteran)
        XCTAssertEqual(ArmyRank.forXP(150), .elite)
        XCTAssertEqual(ArmyRank.forXP(1000), .legend)
    }

    func testWinsAreRecordedOnceAndEarnNames() {
        let store = ArmyStore()
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5")
        let ledger = game.ledger!

        store.record(ledger, playerColor: .white, won: true)
        XCTAssertEqual(store.record(for: .ePawn).wins, 1)
        XCTAssertEqual(store.record(for: .ePawn).captures, 1)
        XCTAssertEqual(store.record(for: .ePawn).survivedWins, 1)
        // The same game again doesn't count twice.
        XCTAssertTrue(store.record(ledger, playerColor: .white, won: true).isEmpty)
        XCTAssertEqual(store.record(for: .ePawn).wins, 1)

        var news: [ArmyNews] = []
        for _ in 0..<5 {
            let next = GameModel()
            play(next, "e2e4", "d7d5", "e4d5")
            news += store.record(next.ledger!, playerColor: .white, won: true)
        }
        let pawn = store.record(for: .ePawn)
        XCTAssertGreaterThanOrEqual(pawn.rank, .veteran)
        XCTAssertNotNil(pawn.name)
        XCTAssertTrue(news.contains { $0.slot == .ePawn && $0.rank == .veteran })
        let names = ArmySlot.allCases.compactMap { store.record(for: $0).name }
        XCTAssertEqual(names.count, Set(names).count, "Names are unique")
    }

    func testPlayingBlackFillsTheSameSlots() {
        let store = ArmyStore()
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5", "d8d5")
        store.record(game.ledger!, playerColor: .black, won: false)
        XCTAssertEqual(store.record(for: .queen).captures, 1)
        XCTAssertEqual(store.record(for: .dPawn).falls, 1)
        XCTAssertEqual(store.record(for: .queen).wins, 0)
    }

    func testRenameKeepsANonEmptyName() {
        let store = ArmyStore()
        store.rename(.kingsKnight, to: "  Vesper  ")
        XCTAssertEqual(store.record(for: .kingsKnight).name, "Vesper")
        store.rename(.kingsKnight, to: "   ")
        XCTAssertEqual(store.record(for: .kingsKnight).name, "Vesper")
    }
}
