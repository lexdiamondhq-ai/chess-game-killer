import ChessKit
import Foundation

/// The Traffic Light habit as a drill: in a real position, find every check the side to
/// move can give, every piece of theirs it can take, and every piece of its own in danger.
/// The rules decide every answer, so nothing here is a judgment call.
enum BoardScan {
    /// What one scan asks the player to find.
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case checks, captures, threats

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checks: return "Checks"
            case .captures: return "Captures"
            case .threats: return "Threats"
            }
        }

        /// The one-line instruction under the board.
        var instruction: String {
            switch self {
            case .checks: return "Tap every square where you can give check."
            case .captures: return "Tap every piece of theirs you can take."
            case .threats: return "Tap every piece of yours in danger: attacked by something cheaper, or attacked and not defended."
            }
        }

        /// The Traffic Light's lights: red is what they threaten, yellow is your checks and captures.
        var light: Int { self == .threats ? 0 : 1 }

        var symbol: String {
            switch self {
            case .checks: return "crown.fill"
            case .captures: return "scope"
            case .threats: return "exclamationmark.shield.fill"
            }
        }
    }

    /// A round scans for one kind throughout, or for all three in turn.
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case checks, captures, threats, mixed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checks: return "Checks"
            case .captures: return "Captures"
            case .threats: return "Threats"
            case .mixed: return "Mixed"
            }
        }

        /// What the mode's tile says under its name.
        var detail: String {
            switch self {
            case .checks: return "Every check you can give"
            case .captures: return "Every piece you can take"
            case .threats: return "Every piece of yours in danger"
            case .mixed: return "All three, one at a time"
            }
        }

        var symbol: String {
            switch self {
            case .checks: return Kind.checks.symbol
            case .captures: return Kind.captures.symbol
            case .threats: return Kind.threats.symbol
            case .mixed: return "shuffle"
            }
        }

        /// The kind asked for at each of `count` positions. Mixed takes the three in turn,
        /// beginning at `start`, so the kind changes with every position.
        func kinds(count: Int, start: Int = 0) -> [Kind] {
            switch self {
            case .checks: return Array(repeating: .checks, count: count)
            case .captures: return Array(repeating: .captures, count: count)
            case .threats: return Array(repeating: .threats, count: count)
            case .mixed: return (0..<count).map { Kind.allCases[($0 + start) % Kind.allCases.count] }
            }
        }
    }

    /// One square to find.
    struct Target: Hashable, Sendable {
        let square: Square
        /// Where the check, capture or attack comes from: the arrow shown when it's missed.
        let from: Square
        /// What the coach calls it: a move like "Nf6+", or a piece like "their knight on c6".
        let name: String
    }

    // MARK: Finding the targets

    /// The squares to find for `kind`, or nil when the position doesn't suit that scan.
    static func targets(_ kind: Kind, in position: Position) -> [Target]? {
        switch kind {
        case .checks: return checks(in: position)
        case .captures: return captures(in: position)
        case .threats: return threats(in: position)
        }
    }

    /// Every square a legal move of the side to move lands on with check, discovered
    /// checks and every promotion included; two pieces checking on one square make one
    /// square. Nil when castling gives check, since the rook gives it but the king moves.
    static func checks(in position: Position) -> [Target]? {
        let board = Board(position: position)
        let me = position.sideToMove
        let geometry = BoardGeometry(position: position)
        guard let theirKing = geometry.king(of: me.opposite) else { return [] }
        var found: [Square: (piece: Piece, uci: String)] = [:]
        for piece in position.pieces where piece.color == me {
            for to in board.legalMoves(forPieceAt: piece.square) {
                for promotion in promotions(for: piece, to: to) {
                    let after = geometry.applying(from: piece.square, to: to, promotion: promotion)
                    guard !after.attackers(of: theirKing, by: me).isEmpty else { continue }
                    if piece.kind == .king, abs(to.fileIndex - piece.square.fileIndex) == 2 { return nil }
                    let uci = piece.square.notation + to.notation + (promotion?.rawValue.lowercased() ?? "")
                    // The cheapest piece names the square: the check a player most often misses.
                    if let kept = found[to], BoardGeometry.exchangeValue(kept.piece.kind) <= BoardGeometry.exchangeValue(piece.kind) {
                        continue
                    }
                    found[to] = (piece, uci)
                }
            }
        }
        return found
            .map { square, check in
                var copy = board
                let san = TrainingChess.play(check.uci, on: &copy)?.san ?? check.uci
                return Target(square: square, from: check.piece.square, name: san)
            }
            .sorted { $0.square.rawValue < $1.square.rawValue }
    }

    /// Every piece of theirs the side to move can legally take. En passant counts,
    /// and the square to tap is the pawn being taken, not the square the capturer lands on.
    static func captures(in position: Position) -> [Target] {
        let board = Board(position: position)
        let me = position.sideToMove
        var found: [Square: Piece] = [:]
        for piece in position.pieces where piece.color == me {
            for to in board.legalMoves(forPieceAt: piece.square) {
                guard let victim = victimSquare(of: piece, to: to, in: position) else { continue }
                if let kept = found[victim], BoardGeometry.exchangeValue(kept.kind) <= BoardGeometry.exchangeValue(piece.kind) {
                    continue
                }
                found[victim] = piece
            }
        }
        return found
            .compactMap { square, capturer in
                guard let victim = position.piece(at: square) else { return nil }
                return Target(square: square, from: capturer.square,
                              name: "their \(BoardGeometry.name(victim.kind)) on \(square.notation)")
            }
            .sorted { $0.square.rawValue < $1.square.rawValue }
    }

    /// Every piece of the side to move that's in danger: one they could take right now
    /// (if it were their turn) with something cheaper, or take and not be taken back.
    /// Legal moves decide both, so a pinned attacker doesn't count, a pinned defender
    /// doesn't defend, a defender behind the attacker (an x-ray) does, and a king only
    /// defends a square they don't also cover. Nil when the side to move is in check:
    /// then the check is the threat.
    static func threats(in position: Position) -> [Target]? {
        let me = position.sideToMove
        let them = me.opposite
        let geometry = BoardGeometry(position: position)
        guard let king = geometry.king(of: me), geometry.attackers(of: king, by: them).isEmpty,
              let theirTurn = passingTheMove(position) else { return nil }
        let board = Board(position: theirTurn)
        var found: [Square: Piece] = [:]
        for attacker in theirTurn.pieces where attacker.color == them {
            for to in board.legalMoves(forPieceAt: attacker.square) {
                guard let victim = theirTurn.piece(at: to), victim.color == me, victim.kind != .king else { continue }
                if let kept = found[to], BoardGeometry.exchangeValue(kept.kind) <= BoardGeometry.exchangeValue(attacker.kind) {
                    continue
                }
                let cheaper = BoardGeometry.exchangeValue(attacker.kind) < BoardGeometry.exchangeValue(victim.kind)
                if cheaper || !canTakeBack(on: to, after: attacker.square, in: board) {
                    found[to] = attacker
                }
            }
        }
        return found
            .compactMap { square, attacker in
                guard let piece = position.piece(at: square) else { return nil }
                return Target(square: square, from: attacker.square,
                              name: "your \(BoardGeometry.name(piece.kind)) on \(square.notation)")
            }
            .sorted { $0.square.rawValue < $1.square.rawValue }
    }

    // MARK: Helpers

    /// The pieces a pawn can become on the last rank, or just the move itself.
    private static func promotions(for piece: Piece, to: Square) -> [Piece.Kind?] {
        guard piece.kind == .pawn, to.rankIndex == 0 || to.rankIndex == 7 else { return [nil] }
        return [.queen, .rook, .bishop, .knight]
    }

    /// The square of the piece a legal move takes, if it takes one.
    private static func victimSquare(of piece: Piece, to: Square, in position: Position) -> Square? {
        if let occupant = position.piece(at: to) {
            return occupant.color == piece.color ? nil : to
        }
        // A pawn moving diagonally to an empty square takes en passant: the pawn beside it.
        guard piece.kind == .pawn, to.fileIndex != piece.square.fileIndex else { return nil }
        let passed = Square(file: to.fileIndex, rank: piece.square.rankIndex)
        guard let pawn = position.piece(at: passed), pawn.color != piece.color, pawn.kind == .pawn else { return nil }
        return passed
    }

    /// The same position with the other side to move, as if this side passed.
    /// No en passant: that right belongs to the side whose turn it really is.
    static func passingTheMove(_ position: Position) -> Position? {
        var fields = position.fen.split(separator: " ").map(String.init)
        guard fields.count >= 4 else { return nil }
        fields[1] = position.sideToMove == .white ? "b" : "w"
        fields[3] = "-"
        return Position(fen: fields.joined(separator: " "))
    }

    /// Whether, after the capture from `from` on `square`, the other side can legally take back.
    private static func canTakeBack(on square: Square, after from: Square, in board: Board) -> Bool {
        var after = board
        guard TrainingChess.play(from.notation + square.notation, on: &after) != nil else { return true }
        let side = after.position.sideToMove
        return after.position.pieces.contains { piece in
            piece.color == side && after.legalMoves(forPieceAt: piece.square).contains(square)
        }
    }
}
