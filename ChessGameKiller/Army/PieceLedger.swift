import ChessKit
import Foundation

/// What one piece did in one game.
struct PieceGameStats: Equatable {
    var moves = 0
    var captures = 0
    /// Pawns' worth of material it took (pawn 1, knight 3, ... queen 9).
    var captureValue = 0
    /// What it took, in the order it took them.
    var taken: [Piece.Kind] = []
    var fell = false
    var gaveMate = false
    var promoted = false
}

/// Follows every piece of one game back to the square it started on, so each
/// of the player's pieces can keep its own record from game to game.
/// Only games that start from the standard position are followed.
struct PieceLedger: Equatable {
    /// Tells games apart, so a finished game is only counted once.
    let gameID: UUID
    /// Where each piece now on the board started: current square -> starting square.
    private(set) var origins: [Square: Square]
    /// This game's record for each piece, by starting square.
    private(set) var stats: [Square: PieceGameStats] = [:]

    static let values: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9, .king: 0]

    /// Nil unless `position` is the standard starting position.
    init?(startingFrom position: Position, gameID: UUID = UUID()) {
        guard position.fen == Position.standard.fen else { return nil }
        self.gameID = gameID
        origins = Dictionary(uniqueKeysWithValues: position.pieces.map { ($0.square, $0.square) })
    }

    /// The square the piece standing on `square` started the game on.
    func origin(of square: Square) -> Square? {
        origins[square]
    }

    func stats(forPieceStartingOn start: Square) -> PieceGameStats {
        stats[start] ?? PieceGameStats()
    }

    /// Notes one move by comparing the position before and after it. This
    /// handles castling (two pieces move), en passant (the captured pawn isn't
    /// on the target square) and promotion (a pawn becomes another piece).
    mutating func record(from before: Position, to after: Position, endedInMate: Bool) {
        let mover = before.sideToMove

        func same(_ piece: Piece?, _ other: Piece) -> Bool {
            piece?.kind == other.kind && piece?.color == other.color
        }

        var left = before.pieces.filter { $0.color == mover && !same(after.piece(at: $0.square), $0) }
        let arrived = after.pieces.filter { $0.color == mover && !same(before.piece(at: $0.square), $0) }
        let fallen = before.pieces.filter { $0.color != mover && !same(after.piece(at: $0.square), $0) }

        // Pair each piece that arrived with the one that left: same kind first,
        // then a pawn for a promoted piece.
        var moved: [(start: Square, to: Square, promoted: Bool)] = []
        for piece in arrived {
            let index = left.firstIndex { $0.kind == piece.kind } ?? left.firstIndex { $0.kind == .pawn }
            guard let index, let start = origins[left[index].square] else { continue }
            moved.append((start, piece.square, left[index].kind != piece.kind))
            left.remove(at: index)
        }

        // The piece that made the move: the king when castling.
        let main = moved.first { after.piece(at: $0.to)?.kind == .king && moved.count > 1 } ?? moved.first

        for piece in fallen {
            guard let start = origins[piece.square] else { continue }
            stats[start, default: PieceGameStats()].fell = true
            // Usually the piece that landed on its square; en passant lands next to it.
            if let capturer = moved.first(where: { $0.to == piece.square }) ?? main {
                stats[capturer.start, default: PieceGameStats()].captures += 1
                stats[capturer.start, default: PieceGameStats()].captureValue += Self.values[piece.kind] ?? 0
                stats[capturer.start, default: PieceGameStats()].taken.append(piece.kind)
            }
        }

        for piece in before.pieces where !same(after.piece(at: piece.square), piece) {
            origins[piece.square] = nil
        }
        for move in moved {
            origins[move.to] = move.start
            if move.promoted { stats[move.start, default: PieceGameStats()].promoted = true }
        }
        if let main {
            stats[main.start, default: PieceGameStats()].moves += 1
            if endedInMate { stats[main.start, default: PieceGameStats()].gaveMate = true }
        }
    }
}
