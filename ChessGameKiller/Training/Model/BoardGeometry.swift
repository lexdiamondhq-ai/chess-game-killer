import ChessKit

/// Who attacks what on a board. Pseudo-legal (pins are ignored), which is
/// plenty for the coach to name a pattern; the engine decides what's best.
struct BoardGeometry {
    let pieces: [Square: Piece]

    init(position: Position) {
        pieces = Dictionary(position.pieces.map { ($0.square, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init?(fen: String) {
        guard let position = Position(fen: fen) else { return nil }
        self.init(position: position)
    }

    private init(pieces: [Square: Piece]) {
        self.pieces = pieces
    }

    // MARK: Values

    /// Points: pawn 1, knight and bishop 3, rook 5, queen 9. The king is never traded.
    static func value(_ kind: Piece.Kind) -> Int {
        switch kind {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// For "is the attacker cheaper than its target": the king counts as priceless.
    static func exchangeValue(_ kind: Piece.Kind) -> Int {
        kind == .king ? 100 : value(kind)
    }

    static func name(_ kind: Piece.Kind) -> String {
        switch kind {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    // MARK: Attacks

    func piece(at square: Square) -> Piece? { pieces[square] }

    func king(of color: Piece.Color) -> Square? {
        pieces.first { $0.value.kind == .king && $0.value.color == color }?.key
    }

    /// Squares the piece on `square` attacks.
    func attacks(from square: Square) -> [Square] {
        guard let piece = pieces[square] else { return [] }
        let f = square.fileIndex
        let r = square.rankIndex
        switch piece.kind {
        case .pawn:
            let dr = piece.color == .white ? 1 : -1
            return [(-1, dr), (1, dr)].compactMap { Self.square(f + $0.0, r + $0.1) }
        case .knight:
            return [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
                .compactMap { Self.square(f + $0.0, r + $0.1) }
        case .king:
            return [(1, 1), (1, 0), (1, -1), (0, 1), (0, -1), (-1, 1), (-1, 0), (-1, -1)]
                .compactMap { Self.square(f + $0.0, r + $0.1) }
        case .bishop, .rook, .queen:
            return Self.directions(for: piece.kind).flatMap { ray(from: square, step: $0) }
        }
    }

    /// Squares along one direction until (and including) the first piece.
    func ray(from square: Square, step: (Int, Int)) -> [Square] {
        var result: [Square] = []
        var f = square.fileIndex + step.0
        var r = square.rankIndex + step.1
        while let next = Self.square(f, r) {
            result.append(next)
            if pieces[next] != nil { break }
            f += step.0
            r += step.1
        }
        return result
    }

    func attackers(of square: Square, by color: Piece.Color) -> [Square] {
        pieces.filter { $0.value.color == color && attacks(from: $0.key).contains(square) }.map(\.key)
    }

    func isDefended(_ square: Square, by color: Piece.Color) -> Bool {
        !attackers(of: square, by: color).isEmpty
    }

    /// Whether the piece on `square` could be won right away: attacked and
    /// undefended, or attacked by something cheaper.
    func isHanging(_ square: Square) -> Bool {
        guard let piece = pieces[square], piece.kind != .king else { return false }
        let enemy = piece.color.opposite
        let attackers = attackers(of: square, by: enemy)
        guard !attackers.isEmpty else { return false }
        if !isDefended(square, by: piece.color) { return true }
        let cheapest = attackers.compactMap { pieces[$0].map { Self.exchangeValue($0.kind) } }.min() ?? 100
        return cheapest < Self.value(piece.kind)
    }

    func hangingPieces(of color: Piece.Color) -> [Square] {
        pieces.filter { $0.value.color == color && isHanging($0.key) }
            .sorted { Self.value($0.value.kind) > Self.value($1.value.kind) }
            .map(\.key)
    }

    /// What the piece on `square` hits that's worth hitting: the king, anything
    /// worth more than it, or anything undefended (pawns only if undefended).
    func forkTargets(from square: Square) -> [Square] {
        guard let attacker = pieces[square] else { return [] }
        return attacks(from: square).filter { target in
            guard let piece = pieces[target], piece.color != attacker.color else { return false }
            if piece.kind == .king { return true }
            if Self.value(piece.kind) > Self.value(attacker.kind) { return true }
            return Self.value(piece.kind) >= 3 && !isDefended(target, by: piece.color)
        }
    }

    /// Two enemy pieces lined up behind each other in front of the slider on
    /// `square`: a pin when the back one is worth more, a skewer when the front one is.
    func lineups(from square: Square) -> [(front: Square, back: Square)] {
        guard let slider = pieces[square], [.bishop, .rook, .queen].contains(slider.kind) else { return [] }
        var result: [(front: Square, back: Square)] = []
        for step in Self.directions(for: slider.kind) {
            let first = ray(from: square, step: step)
            guard let front = first.last, let frontPiece = pieces[front], frontPiece.color != slider.color else { continue }
            let beyond = ray(from: front, step: step)
            guard let back = beyond.last, let backPiece = pieces[back], backPiece.color != slider.color else { continue }
            result.append((front, back))
        }
        return result
    }

    // MARK: What-ifs

    /// The board after moving a piece. Handles captures, castling's rook and
    /// promotion; good enough for naming patterns, not a rules engine.
    func applying(from: Square, to: Square, promotion: Piece.Kind? = nil) -> BoardGeometry {
        var next = pieces
        guard var moving = next.removeValue(forKey: from) else { return self }
        // En passant: a pawn moving diagonally to an empty square takes the pawn beside it.
        if moving.kind == .pawn, from.fileIndex != to.fileIndex, next[to] == nil,
           let passed = Self.square(to.fileIndex, from.rankIndex) {
            next[passed] = nil
        }
        if moving.kind == .king, abs(from.fileIndex - to.fileIndex) == 2 {
            let rank = from.rankIndex
            let kingside = to.fileIndex > from.fileIndex
            if let rookFrom = Self.square(kingside ? 7 : 0, rank), let rookTo = Self.square(kingside ? 5 : 3, rank),
               var rook = next.removeValue(forKey: rookFrom) {
                rook.square = rookTo
                next[rookTo] = rook
            }
        }
        if moving.kind == .pawn, to.rankIndex == 0 || to.rankIndex == 7 {
            moving.kind = promotion ?? .queen
        }
        moving.square = to
        next[to] = moving
        return BoardGeometry(pieces: next)
    }

    func applying(uci: String) -> BoardGeometry {
        guard let squares = Notation.squares(of: uci) else { return self }
        var promotion: Piece.Kind?
        if uci.count == 5, let letter = uci.last {
            promotion = Piece.Kind(rawValue: letter.uppercased())
        }
        return applying(from: squares.from, to: squares.to, promotion: promotion)
    }

    // MARK: Helpers

    static func square(_ file: Int, _ rank: Int) -> Square? {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return Square(file: file, rank: rank)
    }

    static func directions(for kind: Piece.Kind) -> [(Int, Int)] {
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        switch kind {
        case .bishop: return diagonal
        case .rook: return straight
        case .queen: return diagonal + straight
        default: return []
        }
    }

    /// "rook and queen", "king, rook and knight".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
