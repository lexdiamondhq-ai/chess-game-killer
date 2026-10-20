import ChessKit
import Foundation

/// A position being set up by hand or read from a photo, before it is analyzed.
/// Unlike a game, it can be anything while it's being edited; `problems` says
/// what has to be fixed before Stockfish can look at it.
struct PositionDraft: Equatable {
    /// A piece without a square, as it sits in the editor's palette.
    struct Token: Hashable {
        let kind: Piece.Kind
        let color: Piece.Color

        init(_ kind: Piece.Kind, _ color: Piece.Color) {
            self.kind = kind
            self.color = color
        }

        /// FEN letter: uppercase for white, lowercase for black, "P" for pawns.
        var letter: Character {
            let upper: Character = kind == .pawn ? "P" : Character(kind.rawValue)
            return color == .white ? upper : Character(upper.lowercased())
        }

        init?(letter: Character) {
            let upper = String(letter).uppercased()
            let kind: Piece.Kind?
            if upper == "P" {
                kind = .pawn
            } else if upper == "" {
                kind = nil
            } else {
                kind = Piece.Kind(rawValue: upper)
            }
            guard let kind else { return nil }
            self.init(kind, letter.isUppercase ? .white : .black)
        }

        func piece(at square: Square) -> Piece {
            Piece(kind, color: color, square: square)
        }
    }

    /// Something that keeps the position from being analyzed.
    enum Problem: Equatable {
        case missingKing(Piece.Color)
        case extraKing(Piece.Color)
        case tooManyPieces(Piece.Color)
        case tooManyPawns(Piece.Color)
        case pawnOnEdgeRank
        case waitingSideInCheck(Piece.Color)

        /// Plain words, using the theme's names for the sides.
        func message(white: String, black: String) -> String {
            func name(_ color: Piece.Color) -> String { color == .white ? white : black }
            switch self {
            case .missingKing(let color): return "Add the \(name(color)) king."
            case .extraKing(let color): return "\(name(color)) can only have one king."
            case .tooManyPieces(let color): return "\(name(color)) has more than 16 pieces."
            case .tooManyPawns(let color): return "\(name(color)) has more than 8 pawns."
            case .pawnOnEdgeRank: return "Pawns can't stand on the first or last row."
            case .waitingSideInCheck(let color):
                return "\(name(color)) is in check, so it must be \(name(color))'s turn."
            }
        }
    }

    private(set) var placement: [Square: Token] = [:] {
        // Once the pieces are touched, the position's history is unknown again.
        didSet {
            castling = nil
            enPassant = nil
        }
    }
    var sideToMove: Piece.Color = .white {
        // An en passant capture is only there for the side whose turn it is.
        didSet { if sideToMove != oldValue { enPassant = nil } }
    }
    /// From a FEN: castling rights as the game has them, when they are fewer than
    /// the squares allow (like "-" or "Kq"). Nil when `castlingFEN` has it right.
    private(set) var castling: String?
    /// From a FEN: the en passant square, like "e3".
    private(set) var enPassant: String?

    init(placement: [Square: Token] = [:], sideToMove: Piece.Color = .white) {
        self.placement = placement
        self.sideToMove = sideToMove
    }

    static let empty = PositionDraft()
    static let standard = PositionDraft(fen: Position.standard.fen)!

    /// Reads a FEN. Castling rights and the en passant square are kept until the
    /// pieces are edited; the clocks are worked out again.
    init?(fen: String) {
        let fields = fen.split(separator: " ")
        guard let first = fields.first, let draft = PositionDraft(placement: String(first)) else { return nil }
        self = draft
        if fields.count > 1 {
            sideToMove = fields[1] == "b" ? .black : .white
        }
        if fields.count > 2 {
            // Only rights the squares still allow, so a king that moved and came back can't castle.
            var kept: String = castlingFEN.filter { $0 != "-" && fields[2].contains($0) }
            if kept.isEmpty { kept = "-" }
            if kept != castlingFEN { castling = kept }
        }
        if fields.count > 3, Self.isEnPassantSquare(fields[3]) {
            enPassant = String(fields[3])
        }
    }

    /// Whether a FEN en passant field names a square, like "e3" or "d6".
    private static func isEnPassantSquare(_ field: Substring) -> Bool {
        guard field.count == 2, let file = field.first, let rank = field.last else { return false }
        return "abcdefgh".contains(file) && "36".contains(rank)
    }

    /// Reads just a FEN placement field, like "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR".
    init?(placement field: String) {
        let rows = field.split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        var placement: [Square: Token] = [:]
        for (index, row) in rows.enumerated() {
            let rank = 7 - index
            var file = 0
            for character in row {
                if let skip = character.wholeNumberValue {
                    guard (1...8).contains(skip) else { return nil }
                    file += skip
                } else {
                    guard file < 8, let token = Token(letter: character) else { return nil }
                    placement[Square(file: file, rank: rank)] = token
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.init(placement: placement)
    }

    /// Which edge of a picture White's side of the board is on.
    enum WhiteSide: String, Decodable {
        case bottom, top, left, right
    }

    /// Eight rows of eight characters as seen in a picture, top row first:
    /// a FEN letter for a piece, anything else for an empty square.
    /// `whiteSide` says which way round the picture was taken.
    init?(rows: [String], whiteSide: WhiteSide) {
        guard rows.count == 8 else { return nil }
        var placement: [Square: Token] = [:]
        for (row, text) in rows.enumerated() {
            let characters = Array(text)
            guard characters.count == 8 else { return nil }
            for (column, character) in characters.enumerated() {
                guard let token = Token(letter: character) else { continue }
                let square: Square
                switch whiteSide {
                case .bottom: square = Square(file: column, rank: 7 - row)
                case .top: square = Square(file: 7 - column, rank: row)
                // White sits on the left facing right, so the a-file runs along the top.
                case .left: square = Square(file: row, rank: column)
                case .right: square = Square(file: 7 - row, rank: 7 - column)
                }
                placement[square] = token
            }
        }
        self.init(placement: placement)
    }

    // MARK: Editing

    subscript(square: Square) -> Token? {
        get { placement[square] }
        set { placement[square] = newValue }
    }

    mutating func clear() {
        placement = [:]
    }

    /// Turns the board around, for a photo taken from the other side.
    mutating func rotate() {
        var turned: [Square: Token] = [:]
        for (square, token) in placement {
            turned[Square(file: 7 - square.fileIndex, rank: 7 - square.rankIndex)] = token
        }
        placement = turned
    }

    var isEmpty: Bool { placement.isEmpty }

    var pieces: [Piece] {
        placement.map { $0.value.piece(at: $0.key) }
    }

    // MARK: Checking

    var problems: [Problem] {
        var problems: [Problem] = []
        for color in [Piece.Color.white, .black] {
            let tokens = placement.values.filter { $0.color == color }
            let kings = tokens.filter { $0.kind == .king }.count
            if kings == 0 { problems.append(.missingKing(color)) }
            if kings > 1 { problems.append(.extraKing(color)) }
            if tokens.count > 16 { problems.append(.tooManyPieces(color)) }
            if tokens.filter({ $0.kind == .pawn }).count > 8 { problems.append(.tooManyPawns(color)) }
        }
        if placement.contains(where: { $0.value.kind == .pawn && ($0.key.rankIndex == 0 || $0.key.rankIndex == 7) }) {
            problems.append(.pawnOnEdgeRank)
        }
        let waiting = sideToMove.opposite
        if problems.isEmpty, isInCheck(waiting) {
            problems.append(.waitingSideInCheck(waiting))
        }
        return problems
    }

    var isValid: Bool { problems.isEmpty }

    func isInCheck(_ color: Piece.Color) -> Bool {
        guard let king = placement.first(where: { $0.value == Token(.king, color) })?.key else { return false }
        return isAttacked(king, by: color.opposite)
    }

    /// Whether any piece of `color` attacks `target`.
    func isAttacked(_ target: Square, by color: Piece.Color) -> Bool {
        let tf = target.fileIndex
        let tr = target.rankIndex

        func token(_ file: Int, _ rank: Int) -> Token? {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
            return placement[Square(file: file, rank: rank)]
        }

        // Pawns attack diagonally forward, so look one rank behind the target.
        let pawnRank = color == .white ? tr - 1 : tr + 1
        for df in [-1, 1] where token(tf + df, pawnRank) == Token(.pawn, color) {
            return true
        }

        let knightJumps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        for (df, dr) in knightJumps where token(tf + df, tr + dr) == Token(.knight, color) {
            return true
        }

        for df in -1...1 {
            for dr in -1...1 where (df, dr) != (0, 0) {
                if token(tf + df, tr + dr) == Token(.king, color) { return true }
            }
        }

        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (directions, slider) in [(straight, Piece.Kind.rook), (diagonal, Piece.Kind.bishop)] {
            for (df, dr) in directions {
                var file = tf + df
                var rank = tr + dr
                while (0..<8).contains(file), (0..<8).contains(rank) {
                    if let found = placement[Square(file: file, rank: rank)] {
                        if found.color == color, found.kind == slider || found.kind == .queen { return true }
                        break
                    }
                    file += df
                    rank += dr
                }
            }
        }
        return false
    }

    // MARK: FEN

    var placementFEN: String {
        (0..<8).reversed().map { rank in
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let token = placement[Square(file: file, rank: rank)] {
                    if empty > 0 { row += "\(empty)" }
                    empty = 0
                    row.append(token.letter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += "\(empty)" }
            return row
        }
        .joined(separator: "/")
    }

    /// Castling is allowed wherever king and rook still stand on their starting squares.
    var castlingFEN: String {
        var rights = ""
        if placement[.e1] == Token(.king, .white) {
            if placement[.h1] == Token(.rook, .white) { rights += "K" }
            if placement[.a1] == Token(.rook, .white) { rights += "Q" }
        }
        if placement[.e8] == Token(.king, .black) {
            if placement[.h8] == Token(.rook, .black) { rights += "k" }
            if placement[.a8] == Token(.rook, .black) { rights += "q" }
        }
        return rights.isEmpty ? "-" : rights
    }

    var fen: String {
        "\(placementFEN) \(sideToMove == .white ? "w" : "b") \(castling ?? castlingFEN) \(enPassant ?? "-") 0 1"
    }

    /// The position as a game can use it, when it is valid.
    var position: Position? {
        isValid ? Position(fen: fen) : nil
    }

    /// Whether the side to move has no legal moves (checkmate or stalemate).
    var isFinished: Bool {
        guard let position else { return false }
        let board = Board(position: position)
        return !position.pieces.contains { piece in
            piece.color == sideToMove && !board.legalMoves(forPieceAt: piece.square).isEmpty
        }
    }
}
