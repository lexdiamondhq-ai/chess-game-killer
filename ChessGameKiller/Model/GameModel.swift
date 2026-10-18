import ChessKit
import Foundation
import Observation

/// A piece with a stable identity, so the board can animate it sliding
/// from square to square instead of popping in and out.
struct PlacedPiece: Identifiable, Equatable {
    let id: Int
    let piece: Piece

    var square: Square { piece.square }
}

struct LastMove: Equatable {
    let from: Square
    let to: Square
}

/// One game of chess. The rules come from ChessKit; this adds selection,
/// move hints, promotion, undo and the text shown above the board.
@Observable
final class GameModel {
    private(set) var board = Board()
    private(set) var pieces: [PlacedPiece] = []
    private(set) var selected: Square?
    private(set) var targets: Set<Square> = []
    private(set) var lastMove: LastMove?
    /// Set while the player is choosing what a pawn becomes.
    private(set) var pendingPromotion: Move?
    /// Bumps on every completed move. Drives haptics.
    private(set) var moveCount = 0

    /// Snapshots taken before each move, for undo.
    private var history: [Snapshot] = []
    private var nextPieceID = 0

    private struct Snapshot {
        let board: Board
        let lastMove: LastMove?
    }

    /// Starts from the standard position, or any other (useful for lessons and tests).
    init(position: Position = .standard) {
        board = Board(position: position)
        syncPieces()
    }

    // MARK: Reading the position

    var sideToMove: Piece.Color { board.position.sideToMove }

    func piece(at square: Square) -> Piece? {
        board.position.piece(at: square)
    }

    var isGameOver: Bool {
        switch board.state {
        case .checkmate, .draw: return true
        default: return false
        }
    }

    var canUndo: Bool { !history.isEmpty }

    /// The square of the king that is in check, if any.
    var checkedKing: Square? {
        let color: Piece.Color
        switch board.state {
        case .check(let c), .checkmate(let c): color = c
        default: return nil
        }
        return board.position.pieces.first { $0.kind == .king && $0.color == color }?.square
    }

    var status: String {
        switch board.state {
        case .checkmate(let loser):
            return "Checkmate. \(loser.opposite.displayName) wins"
        case .draw(let reason):
            return "Draw by \(reason.displayName)"
        case .check(let color):
            return "\(color.displayName) is in check"
        case .promotion:
            return "Choose a piece"
        case .active:
            return "\(sideToMove.displayName) to move"
        }
    }

    // MARK: Playing

    /// Handles a tap on a square: select a piece, move it, or clear the selection.
    func tap(_ square: Square) {
        guard pendingPromotion == nil, !isGameOver else { return }

        if let from = selected, targets.contains(square) {
            play(from: from, to: square)
            return
        }

        if let piece = piece(at: square), piece.color == sideToMove, selected != square {
            selected = square
            targets = Set(board.legalMoves(forPieceAt: square))
        } else {
            clearSelection()
        }
    }

    /// Finishes a pawn promotion started by `tap`.
    func promote(to kind: Piece.Kind) {
        guard let move = pendingPromotion else { return }
        board.completePromotion(of: move, to: kind)
        pendingPromotion = nil
        finishMove()
    }

    /// Takes back the last move, or cancels a promotion in progress.
    func undo() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        lastMove = snapshot.lastMove
        pendingPromotion = nil
        clearSelection()
        syncPieces()
    }

    func newGame() {
        history.removeAll()
        board = Board()
        lastMove = nil
        pendingPromotion = nil
        clearSelection()
        syncPieces()
    }

    // MARK: Private

    private func play(from: Square, to: Square) {
        let before = Snapshot(board: board, lastMove: lastMove)
        guard board.move(pieceAt: from, to: to) != nil else {
            clearSelection()
            return
        }
        history.append(before)
        lastMove = LastMove(from: from, to: to)
        clearSelection()

        if case .promotion(let move) = board.state {
            pendingPromotion = move
            syncPieces()
        } else {
            finishMove()
        }
    }

    private func finishMove() {
        moveCount += 1
        syncPieces()
    }

    private func clearSelection() {
        selected = nil
        targets = []
    }

    /// Matches the board's pieces to the ones already on screen so each
    /// keeps its identity: unmoved pieces by square, moved pieces by kind
    /// and color (one move never moves two pieces of the same kind and color).
    private func syncPieces() {
        var unmatched = pieces
        var result: [PlacedPiece] = []
        var moved: [Piece] = []

        for piece in board.position.pieces {
            if let i = unmatched.firstIndex(where: { $0.piece == piece }) {
                result.append(PlacedPiece(id: unmatched[i].id, piece: piece))
                unmatched.remove(at: i)
            } else {
                moved.append(piece)
            }
        }
        for piece in moved {
            if let i = unmatched.firstIndex(where: { $0.piece.kind == piece.kind && $0.piece.color == piece.color }) {
                result.append(PlacedPiece(id: unmatched[i].id, piece: piece))
                unmatched.remove(at: i)
            } else {
                result.append(PlacedPiece(id: nextPieceID, piece: piece))
                nextPieceID += 1
            }
        }
        pieces = result.sorted { $0.id < $1.id }
    }
}

extension Piece.Color {
    var displayName: String { self == .white ? "White" : "Black" }
}

extension Board.State.DrawReason {
    var displayName: String {
        switch self {
        case .agreement: return "agreement"
        case .fiftyMoves: return "the 50-move rule"
        case .insufficientMaterial: return "insufficient material"
        case .repetition: return "repetition"
        case .stalemate: return "stalemate"
        }
    }
}

extension Piece {
    /// Name of the vector image in Assets.xcassets/Pieces, e.g. "wK" or "bP".
    var assetName: String {
        color.rawValue + (kind == .pawn ? "P" : kind.rawValue)
    }

    /// Spoken name for VoiceOver, e.g. "white knight".
    var spokenName: String {
        "\(color.displayName.lowercased()) \(String(describing: kind))"
    }
}

extension Square {
    /// Square from zero-based file (a = 0) and rank (rank 1 = 0) indexes.
    init(file: Int, rank: Int) {
        self.init(rawValue: rank * 8 + file)!
    }

    var fileIndex: Int { rawValue % 8 }
    var rankIndex: Int { rawValue / 8 }
}
