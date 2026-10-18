import ChessKit
import Foundation

/// Small rules helpers for lessons and drills, on top of ChessKit.
enum TrainingChess {
    /// The position in ChessKit's own FEN, so positions compare cleanly.
    static func normalized(_ fen: String) -> String? {
        Position(fen: fen)?.fen
    }

    /// Piece placement and side to move: enough to tell two positions apart.
    static func key(_ fen: String) -> String {
        fen.split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// The side to move in a FEN.
    static func sideToMove(_ fen: String) -> Piece.Color? {
        Position(fen: fen)?.sideToMove
    }

    /// The move number in a FEN (its sixth field).
    static func moveNumber(_ fen: String) -> Int {
        let fields = fen.split(separator: " ")
        guard fields.count >= 6, let number = Int(fields[5]) else { return 1 }
        return number
    }

    /// Plays engine-notation moves from a position. Nil at the first move that isn't legal.
    static func board(after moves: [String], from fen: String) -> Board? {
        guard let position = Position(fen: fen) else { return nil }
        var board = Board(position: position)
        for uci in moves {
            guard play(uci, on: &board) != nil else { return nil }
        }
        return board
    }

    static func fen(after moves: [String], from fen: String) -> String? {
        board(after: moves, from: fen)?.position.fen
    }

    /// Plays one move, finishing a promotion with the piece the move names (a queen if none).
    @discardableResult
    static func play(_ uci: String, on board: inout Board) -> Move? {
        guard
            let squares = Notation.squares(of: uci),
            board.position.piece(at: squares.from)?.color == board.position.sideToMove,
            board.canMove(pieceAt: squares.from, to: squares.to),
            let move = board.move(pieceAt: squares.from, to: squares.to)
        else { return nil }
        if case .promotion(let pawnMove) = board.state {
            return board.completePromotion(of: pawnMove, to: promotionKind(of: uci) ?? .queen)
        }
        return move
    }

    /// The piece a move promotes to, from its fifth letter ("e7e8n").
    static func promotionKind(of uci: String) -> Piece.Kind? {
        guard uci.count == 5, let letter = uci.last else { return nil }
        return Piece.Kind(rawValue: letter.uppercased())
    }

    /// Every legal move for the side to move, in engine notation. Promotions
    /// are listed once, as a queen.
    static func legalMoves(in board: Board) -> [String] {
        let position = board.position
        return position.pieces
            .filter { $0.color == position.sideToMove }
            .sorted { $0.square.rawValue < $1.square.rawValue }
            .flatMap { piece in
                board.legalMoves(forPieceAt: piece.square).map { target in
                    let uci = piece.square.notation + target.notation
                    let promotes = piece.kind == .pawn && (target.rankIndex == 0 || target.rankIndex == 7)
                    return promotes ? uci + "q" : uci
                }
            }
    }

    static func isCheckmate(_ board: Board) -> Bool {
        if case .checkmate = board.state { return true }
        return false
    }

    static func givesCheck(_ move: Move) -> Bool {
        move.checkState == .check || move.checkState == .checkmate
    }

    static func isCapture(_ move: Move) -> Bool {
        if case .capture = move.result { return true }
        return false
    }
}
