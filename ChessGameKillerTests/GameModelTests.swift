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
        XCTAssertEqual(game.fen, Position.standard.fen)
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

    @MainActor
    func testCaptureEventIsDroppedOnceTheExplosionIsOver() async throws {
        let game = GameModel()
        play(game, "e2e4", "d7d5", "e4d5")
        XCTAssertEqual(game.captureEvents.map(\.piece.kind), [.pawn])
        // The explosion is over in under a second; the event goes shortly after.
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(game.captureEvents.isEmpty)
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

    func testPromotedPawnIsNotCountedAsCaptured() {
        let game = GameModel()
        // 1. e4 d5 2. exd5 c6 3. dxc6 Nf6 4. cxb7 Nc6 5. bxa8=Q
        play(game, "e2e4", "d7d5", "e4d5", "c7c6", "d5c6", "g8f6", "c6b7", "b8c6", "b7a8")
        game.promote(to: .queen)
        XCTAssertEqual(game.piece(at: .a8)?.kind, .queen)
        XCTAssertEqual(game.captured(by: .white), [
            CapturedCount(kind: .rook, count: 1), CapturedCount(kind: .pawn, count: 3),
        ])
        XCTAssertTrue(game.captured(by: .black).isEmpty)
        XCTAssertEqual(game.materialLead(for: .white), 16)
        XCTAssertEqual(game.materialLead(for: .black), -16)
    }

    func testCapturesAreCountedFromTheStartingPosition() throws {
        let position = try XCTUnwrap(Position(fen: "6k1/8/8/8/8/8/8/R5K1 w - - 0 1"))
        let game = GameModel(position: position)
        XCTAssertTrue(game.captured(by: .white).isEmpty)
        XCTAssertTrue(game.captured(by: .black).isEmpty)
        XCTAssertEqual(game.materialLead(for: .white), 5)
        XCTAssertEqual(game.materialLead(for: .black), -5)
    }

    func testActiveColorStaysWithThePromotingSide() throws {
        let position = try XCTUnwrap(Position(fen: "7k/P7/8/8/8/8/8/K7 w - - 0 1"))
        let game = GameModel(position: position)
        XCTAssertEqual(game.activeColor, .white)
        play(game, "a7a8")
        XCTAssertEqual(game.sideToMove, .black)
        XCTAssertEqual(game.activeColor, .white)
        game.promote(to: .rook)
        XCTAssertEqual(game.activeColor, .black)
    }

    func testStartPositionInCheckShowsTheCheck() throws {
        let position = try XCTUnwrap(Position(fen: "4k3/8/8/4r3/8/8/8/4K3 w - - 0 1"))
        let game = GameModel(position: position)
        XCTAssertEqual(game.status, "White is in check")
        XCTAssertEqual(game.checkedKing, .e1)
        XCTAssertFalse(game.isGameOver)

        play(game, "e1d1")
        XCTAssertNil(game.checkedKing)
        XCTAssertEqual(game.status, "Black to move")

        // Back at the start the check shows again.
        game.undo()
        XCTAssertEqual(game.checkedKing, .e1)
        XCTAssertEqual(game.status, "White is in check")
    }

    func testStartPositionThatIsFinishedEndsTheGame() throws {
        // The analyzer won't start a game from a finished position, so this is about the model, not a path through the app.
        let mate = try XCTUnwrap(Position(fen: "k7/1Q6/2K5/8/8/8/8/8 b - - 0 1"))
        let game = GameModel(position: mate)
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.winner, .white)
        XCTAssertEqual(game.status, "Checkmate. White wins")
        XCTAssertEqual(game.checkedKing, .a8)
        game.tap(.a8)
        XCTAssertNil(game.selected)

        let stalemate = try XCTUnwrap(Position(fen: "k7/2Q5/2K5/8/8/8/8/8 b - - 0 1"))
        game.newGame(from: stalemate)
        XCTAssertTrue(game.isGameOver)
        XCTAssertNil(game.winner)
        XCTAssertEqual(game.status, "Draw by stalemate")
    }

    func testCastlingRightGoesWithARookCapturedAtHome() {
        let game = GameModel()
        // 1. a4 b6 2. h4 Bb7 3. Ra3 Bxg2 4. Rh3 Bxh1
        play(game, "a2a4", "b7b6", "h2h4", "c8b7", "a1a3", "b7g2", "a3h3", "g2h1")
        XCTAssertEqual(game.piece(at: .h1)?.kind, .bishop)
        XCTAssertEqual(castlingField(game), "kq")

        // Taking the capture back gives the right back.
        game.undo()
        XCTAssertEqual(castlingField(game), "Kkq")
        play(game, "g2h1")
        XCTAssertEqual(castlingField(game), "kq")

        // 5. Rxh1 e6 6. Nf3 Nc6 7. e3 Nf6 8. Be2 Be7: a rook is back on h1, but the king can't castle with it.
        play(game, "h3h1", "e7e6", "g1f3", "b8c6", "e2e3", "g8f6", "f1e2", "f8e7")
        XCTAssertEqual(game.piece(at: .h1), Piece(.rook, color: .white, square: .h1))
        XCTAssertEqual(castlingField(game), "kq")
        game.tap(.e1)
        XCTAssertEqual(game.targets, [.f1])
        XCTAssertFalse(game.playEngineMove("e1g1"))
        XCTAssertEqual(game.piece(at: .e1)?.kind, .king)
        XCTAssertTrue(game.playEngineMove("e1f1"))
    }

    /// The castling field of the game's FEN, like "KQkq" or "-".
    private func castlingField(_ game: GameModel) -> String {
        String(game.fen.split(separator: " ")[2])
    }
}
