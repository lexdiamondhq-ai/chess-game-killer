import ChessKit
import XCTest
@testable import ChessGameKiller

final class GameModelTests: XCTestCase {

    /// Plays moves written as "e2e4" by tapping the start and end squares.
    private func play(_ game: GameModel, _ moves: String...) {
        for move in moves {
            game.tap(Square(String(move.prefix(2))))
            game.tap(Square(String(move.suffix(2))))
        }
    }

    private func pieceID(_ game: GameModel, at square: Square) -> Int? {
        game.pieces.first { $0.square == square }?.id
    }

    func testNewGameStartsWithWhiteToMove() {
        let game = GameModel()
        XCTAssertEqual(game.pieces.count, 32)
        XCTAssertEqual(game.sideToMove, .white)
        XCTAssertEqual(game.status, "White to move")
        XCTAssertFalse(game.canUndo)
    }

    func testSelectingPawnShowsItsLegalMoves() {
        let game = GameModel()
        game.tap(.e2)
        XCTAssertEqual(game.selected, .e2)
        XCTAssertEqual(game.targets, [.e3, .e4])
    }

    func testCannotSelectOpponentsPiece() {
        let game = GameModel()
        game.tap(.e7)
        XCTAssertNil(game.selected)
        XCTAssertTrue(game.targets.isEmpty)
    }

    func testTappingSelectedPieceAgainDeselects() {
        let game = GameModel()
        game.tap(.e2)
        game.tap(.e2)
        XCTAssertNil(game.selected)
    }

    func testMovePlaysAndSwitchesTurn() {
        let game = GameModel()
        play(game, "e2e4")
        XCTAssertEqual(game.piece(at: .e4)?.kind, .pawn)
        XCTAssertNil(game.piece(at: .e2))
        XCTAssertEqual(game.sideToMove, .black)
        XCTAssertEqual(game.lastMove, LastMove(from: .e2, to: .e4))
        XCTAssertEqual(game.moveCount, 1)
        XCTAssertNil(game.selected)
    }

    func testIllegalTargetDoesNotMove() {
        let game = GameModel()
        play(game, "e2e5")
        XCTAssertEqual(game.piece(at: .e2)?.kind, .pawn)
        XCTAssertEqual(game.sideToMove, .white)
        XCTAssertNil(game.selected)
    }

    func testCaptureRemovesPiece() {
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5")
        XCTAssertEqual(game.pieces.count, 31)
        XCTAssertEqual(game.piece(at: .d5)?.color, .white)
    }

    func testMovesAreKeptInStandardNotation() {
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5")
        XCTAssertEqual(game.moves, ["e4", "d5", "exd5"])
        game.undo()
        XCTAssertEqual(game.moves, ["e4", "d5"])
        game.newGame()
        XCTAssertTrue(game.moves.isEmpty)
    }

    func testFoolsMateEndsGame() {
        let game = GameModel()
        play(game, "f2f3", "e7e5", "g2g4", "d8h4")
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.status, "Checkmate. Black wins")
        XCTAssertEqual(game.checkedKing, .e1)

        // No more moves after the game ends.
        game.tap(.a2)
        XCTAssertNil(game.selected)
    }

    func testUndoTakesBackMove() {
        let game = GameModel()
        play(game, "e2e4", "e7e5")
        game.undo()
        XCTAssertEqual(game.piece(at: .e7)?.kind, .pawn)
        XCTAssertEqual(game.sideToMove, .black)
        XCTAssertEqual(game.lastMove, LastMove(from: .e2, to: .e4))
        game.undo()
        XCTAssertEqual(game.piece(at: .e2)?.kind, .pawn)
        XCTAssertNil(game.lastMove)
        XCTAssertFalse(game.canUndo)
    }

    func testMovedPieceKeepsItsIdentity() {
        let game = GameModel()
        let id = pieceID(game, at: .e2)
        play(game, "e2e4")
        XCTAssertEqual(pieceID(game, at: .e4), id)
    }

    func testCastlingSlidesKingAndRook() {
        let game = GameModel()
        let kingID = pieceID(game, at: .e1)
        let rookID = pieceID(game, at: .h1)
        play(game, "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1")
        XCTAssertEqual(game.piece(at: .g1)?.kind, .king)
        XCTAssertEqual(game.piece(at: .f1)?.kind, .rook)
        XCTAssertEqual(pieceID(game, at: .g1), kingID)
        XCTAssertEqual(pieceID(game, at: .f1), rookID)
        XCTAssertEqual(Set(game.pieces.map(\.id)).count, 32)
    }

    func testPromotionAsksForPieceThenCompletes() throws {
        let position = try XCTUnwrap(Position(fen: "7k/P7/8/8/8/8/8/K7 w - - 0 1"))
        let game = GameModel(position: position)
        play(game, "a7a8")
        XCTAssertNotNil(game.pendingPromotion)
        XCTAssertEqual(game.status, "Choose a piece")

        // Board is locked until a piece is chosen.
        game.tap(.a1)
        XCTAssertNil(game.selected)

        game.promote(to: .queen)
        XCTAssertNil(game.pendingPromotion)
        XCTAssertEqual(game.piece(at: .a8)?.kind, .queen)
        XCTAssertEqual(game.sideToMove, .black)
        XCTAssertEqual(game.status, "Black is in check")
        XCTAssertEqual(game.checkedKing, .h8)
    }

    func testUndoCancelsPromotion() throws {
        let position = try XCTUnwrap(Position(fen: "7k/P7/8/8/8/8/8/K7 w - - 0 1"))
        let game = GameModel(position: position)
        play(game, "a7a8")
        game.undo()
        XCTAssertNil(game.pendingPromotion)
        XCTAssertEqual(game.piece(at: .a7)?.kind, .pawn)
        XCTAssertEqual(game.sideToMove, .white)
    }

    func testNewGameResets() {
        let game = GameModel()
        play(game, "e2e4")
        game.newGame()
        XCTAssertEqual(game.pieces.count, 32)
        XCTAssertEqual(game.sideToMove, .white)
        XCTAssertFalse(game.canUndo)
        XCTAssertNil(game.lastMove)
    }

    func testCapturedPiecesAreCountedByKind() {
        let game = GameModel()
        XCTAssertTrue(game.captured(by: .white).isEmpty)
        XCTAssertEqual(game.materialLead(for: .white), 0)

        // 1. e4 d5 2. exd5 Qxd5 3. Nc3 Qxg2?? 4. Bxg2
        play(game, "e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5g2", "f1g2")
        XCTAssertEqual(game.captured(by: .white), [
            CapturedCount(kind: .queen, count: 1), CapturedCount(kind: .pawn, count: 1),
        ])
        XCTAssertEqual(game.captured(by: .black), [CapturedCount(kind: .pawn, count: 2)])
        XCTAssertEqual(game.materialLead(for: .white), 8)
        XCTAssertEqual(game.materialLead(for: .black), -8)
    }
}
