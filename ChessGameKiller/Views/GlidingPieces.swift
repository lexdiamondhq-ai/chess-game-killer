import ChessKit
import SwiftUI

/// Keeps each piece's identity from one position to the next, so a board can slide a piece to
/// its new square instead of swapping one picture for another. A piece still on its square stays
/// who it was; a piece that moved takes the identity of the nearest piece of its kind and color
/// that left its square; anything else (a promotion, a piece set up by hand) is new and fades in.
final class PieceIdentities {
    /// A position's pieces with their identities, and which of them just moved.
    struct Arrangement: Equatable {
        var pieces: [PlacedPiece] = []
        /// Pieces that changed square since the last position: drawn above a piece they take.
        var moving: Set<Int> = []
    }

    private var arrangement = Arrangement()
    private var key: String?
    private var nextID = 0

    /// The pieces with their identities. Asking again for the same position (`key`, such as its
    /// placement FEN) gives the same answer, so a view can ask every time it draws.
    func arrange(_ pieces: [Piece], key: String) -> Arrangement {
        guard key != self.key else { return arrangement }
        let previous = arrangement.pieces
        let placed = Self.match(pieces, to: previous, nextID: &nextID)
        let before = Dictionary(previous.map { ($0.id, $0.square) }, uniquingKeysWith: { first, _ in first })
        let moving = Set(placed.compactMap { item -> Int? in
            guard let was = before[item.id], was != item.square else { return nil }
            return item.id
        })
        self.key = key
        arrangement = Arrangement(pieces: placed, moving: moving)
        return arrangement
    }

    /// `pieces` with the identities of `previous`: same piece on the same square first, then the
    /// closest pairs of the same kind and color, so after several moves at once (stepping back to
    /// the start, say) every piece travels as little as it can.
    static func match(_ pieces: [Piece], to previous: [PlacedPiece], nextID: inout Int) -> [PlacedPiece] {
        var unmatched = previous
        var result: [PlacedPiece] = []
        var moved: [Piece] = []
        for piece in pieces {
            if let i = unmatched.firstIndex(where: { $0.piece == piece }) {
                result.append(PlacedPiece(id: unmatched[i].id, piece: piece))
                unmatched.remove(at: i)
            } else {
                moved.append(piece)
            }
        }
        var pairs: [(distance: Int, moved: Int, from: Int)] = []
        for (m, piece) in moved.enumerated() {
            for (u, old) in unmatched.enumerated() where old.piece.kind == piece.kind && old.piece.color == piece.color {
                let dx = piece.square.fileIndex - old.square.fileIndex
                let dz = piece.square.rankIndex - old.square.rankIndex
                pairs.append((dx * dx + dz * dz, m, u))
            }
        }
        pairs.sort { ($0.distance, $0.moved, $0.from) < ($1.distance, $1.moved, $1.from) }
        var placedMoved = Set<Int>()
        var usedFrom = Set<Int>()
        for pair in pairs where !placedMoved.contains(pair.moved) && !usedFrom.contains(pair.from) {
            placedMoved.insert(pair.moved)
            usedFrom.insert(pair.from)
            result.append(PlacedPiece(id: unmatched[pair.from].id, piece: moved[pair.moved]))
        }
        for (m, piece) in moved.enumerated() where !placedMoved.contains(m) {
            result.append(PlacedPiece(id: nextID, piece: piece))
            nextID += 1
        }
        return result.sorted { $0.id < $1.id }
    }
}

/// How pieces travel on the boards that draw a position (the analyzer, the editor, the home's
/// small boards): one smooth glide with no bounce, a taken piece fading as the other arrives.
enum PieceGlide {
    static let move: Animation = .smooth(duration: 0.38)
    static let insertion: AnyTransition = .opacity.combined(with: .scale(scale: 0.6))
    static let removal: AnyTransition = .opacity.animation(.easeOut(duration: 0.16).delay(0.12))
}

/// A position's pieces in a layer of their own above the squares, each standing on its square
/// and gliding to its next one. Nearer rows draw last, so a tall piece overlaps the one behind it.
struct GlidingPieces: View {
    let arrangement: PieceIdentities.Arrangement
    let theme: BoardTheme
    let squareSize: CGFloat
    let flipped: Bool
    /// Pieces drawn as ghosts: moves that could have been.
    var ghosts: Set<Square> = []
    var ghostColor: Color = .yellow
    /// The piece picked up, drawn a little larger.
    var selected: Square? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(arrangement.pieces) { item in
                let square = item.square
                let isGhost = ghosts.contains(square)
                PieceImage(piece: item.piece, theme: theme, size: squareSize, onBoard: true)
                    .opacity(isGhost ? 0.62 : 1)
                    .shadow(color: isGhost ? ghostColor.opacity(0.9) : .clear, radius: squareSize * 0.12)
                    .scaleEffect(square == selected ? PieceImage.liftedScale : 1)
                    .position(BoardTapResolver.center(of: square, squareSize: squareSize, flipped: flipped))
                    .zIndex(depth(of: square) + (arrangement.moving.contains(item.id) ? 0.5 : 0))
                    .transition(.asymmetric(insertion: PieceGlide.insertion, removal: PieceGlide.removal))
            }
        }
        .frame(width: squareSize * 8, height: squareSize * 8, alignment: .topLeading)
        .animation(PieceGlide.move, value: arrangement.pieces)
        .animation(.snappy(duration: 0.2), value: selected)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Back rows first, and left to right within a row.
    private func depth(of square: Square) -> Double {
        let column = flipped ? 7 - square.fileIndex : square.fileIndex
        let row = flipped ? square.rankIndex : 7 - square.rankIndex
        return Double(row * 8 + column)
    }
}
