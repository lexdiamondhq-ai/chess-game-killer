import Foundation

enum PieceColor { case white, black }
enum PieceKind { case king, queen, rook, bishop, knight, pawn }

struct Piece: Hashable {
    let kind: PieceKind
    let color: PieceColor

    var symbol: String {
        switch (color, kind) {
        case (.white, .king): "♔"; case (.white, .queen): "♕"
        case (.white, .rook): "♖"; case (.white, .bishop): "♗"
        case (.white, .knight): "♘"; case (.white, .pawn): "♙"
        case (.black, .king): "♚"; case (.black, .queen): "♛"
        case (.black, .rook): "♜"; case (.black, .bishop): "♝"
        case (.black, .knight): "♞"; case (.black, .pawn): "♟"
        }
    }
}

/// 8x8 board. squares[rank][file], rank 0 = white's back rank.
struct Board {
    var squares: [[Piece?]]

    static var starting: Board {
        let back: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        var s = Array(repeating: Array<Piece?>(repeating: nil, count: 8), count: 8)
        for f in 0..<8 {
            s[0][f] = Piece(kind: back[f], color: .white)
            s[1][f] = Piece(kind: .pawn, color: .white)
            s[6][f] = Piece(kind: .pawn, color: .black)
            s[7][f] = Piece(kind: back[f], color: .black)
        }
        return Board(squares: s)
    }
}
