import Foundation

enum PieceColor { case white, black }
enum PieceKind { case king, queen, rook, bishop, knight, pawn }

struct Piece: Hashable {
    let kind: PieceKind
    let color: PieceColor

    /// Name of the vector image in Assets.xcassets/Pieces, e.g. "wK".
    var assetName: String {
        let c = color == .white ? "w" : "b"
        let k: String
        switch kind {
        case .king: k = "K"
        case .queen: k = "Q"
        case .rook: k = "R"
        case .bishop: k = "B"
        case .knight: k = "N"
        case .pawn: k = "P"
        }
        return c + k
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
