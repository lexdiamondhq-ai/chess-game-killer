import ChessKit
import Foundation
import Observation

/// A piece with a stable identity, so the board can animate it sliding
/// from square to square instead of popping in and out.
/// How many of one kind of piece a side has captured.
struct CapturedCount: Identifiable, Equatable {
    let kind: Piece.Kind
    let count: Int

    var id: Piece.Kind { kind }
}

struct PlacedPiece: Identifiable, Equatable {
    let id: Int
    let piece: Piece

    var square: Square { piece.square }
}

struct LastMove: Equatable {
    let from: Square
    let to: Square
}

/// A captured piece, so the board can blow it up where it stood.
struct CaptureEvent: Identifiable, Equatable {
    let id: Int
    let piece: Piece
}

/// The move that was just completed, with what the coach and sounds need.
struct PlayedMove: Equatable {
    /// Engine notation, like "e2e4".
    let uci: String
    /// Standard notation, like "Nf3" or "exd5+".
    let san: String
    let color: Piece.Color
    /// The position before the move, as FEN.
    let fenBefore: String
    let isCapture: Bool
    let isCastle: Bool
    let givesCheck: Bool
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
    private(set) var lastPlayed: PlayedMove?
    /// Recent captures, newest last. Old ones are dropped.
    private(set) var captureEvents: [CaptureEvent] = []
    /// Every move played so far in standard notation, like ["e4", "e5", "Nf3"].
    private(set) var moves: [String] = []
    /// Where each piece started and what it did this game, for the player's army.
    /// Nil when the game began from a set-up position.
    private(set) var ledger: PieceLedger?
    /// Colors a person moves by tapping. The computer's color is left out.
    var humanColors: Set<Piece.Color> = [.white, .black]

    /// Snapshots taken before each move, for undo.
    private var history: [Snapshot] = []
    private var nextPieceID = 0
    private var nextEventID = 0
    private var fenBeforePendingMove: String?

    private struct Snapshot {
        let board: Board
        let lastMove: LastMove?
        let ledger: PieceLedger?
    }

    /// Starts from the standard position, or any other (useful for lessons and tests).
    init(position: Position = .standard) {
        board = Board(position: position)
        ledger = PieceLedger(startingFrom: position)
        syncPieces()
    }

    // MARK: Reading the position

    var sideToMove: Piece.Color { board.position.sideToMove }

    var fen: String { board.position.fen }

    func piece(at square: Square) -> Piece? {
        board.position.piece(at: square)
    }

    var isGameOver: Bool {
        switch board.state {
        case .checkmate, .draw: return true
        default: return false
        }
    }

    /// The winner, if the game ended in checkmate.
    var winner: Piece.Color? {
        if case .checkmate(let loser) = board.state { return loser.opposite }
        return nil
    }

    /// How many of each piece are in a full set, pawns included.
    private static let fullSet: [Piece.Kind: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]
    private static let pieceValues: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9]

    /// What `color` has taken: each kind of the opponent's pieces missing from the
    /// board with how many are gone, biggest first. Kinds with none taken are left out.
    func captured(by color: Piece.Color) -> [CapturedCount] {
        var counts = Self.fullSet
        for placed in pieces where placed.piece.color == color.opposite {
            counts[placed.piece.kind, default: 0] -= 1
        }
        let order: [Piece.Kind] = [.queen, .rook, .bishop, .knight, .pawn]
        return order.compactMap { kind in
            let count = counts[kind] ?? 0
            return count > 0 ? CapturedCount(kind: kind, count: count) : nil
        }
    }

    /// How far ahead `color` is in material, in pawns. Negative when behind.
    func materialLead(for color: Piece.Color) -> Int {
        material(captured(by: color)) - material(captured(by: color.opposite))
    }

    private func material(_ taken: [CapturedCount]) -> Int {
        taken.reduce(0) { $0 + (Self.pieceValues[$1.kind] ?? 0) * $1.count }
    }

    var canUndo: Bool { !history.isEmpty }

    /// Number of moves played (by both sides) that can be taken back.
    var plyCount: Int { history.count }

    /// Whether a person is the one to move now.
    var isHumanTurn: Bool { humanColors.contains(sideToMove) }

    /// The square of the king that is in check, if any.
    var checkedKing: Square? {
        let color: Piece.Color
        switch board.state {
        case .check(let c), .checkmate(let c): color = c
        default: return nil
        }
        return board.position.pieces.first { $0.kind == .king && $0.color == color }?.square
    }

    var status: String { status(white: "White", black: "Black") }

    /// Whose turn it is or how the game ended, using the theme's names for the sides.
    func status(white: String, black: String) -> String {
        func name(_ color: Piece.Color) -> String { color == .white ? white : black }
        switch board.state {
        case .checkmate(let loser):
            return "Checkmate. \(name(loser.opposite)) wins"
        case .draw(let reason):
            return "Draw by \(reason.displayName)"
        case .check(let color):
            return "\(name(color)) is in check"
        case .promotion:
            return "Choose a piece"
        case .active:
            return "\(name(sideToMove)) to move"
        }
    }

    // MARK: Playing

    /// Handles a tap on a square: select a piece, move it, or clear the selection.
    func tap(_ square: Square) {
        guard pendingPromotion == nil, !isGameOver, isHumanTurn else { return }

        if let from = selected, targets.contains(square) {
            play(from: from, to: square, promotion: nil)
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
        let completed = board.completePromotion(of: move, to: kind)
        pendingPromotion = nil
        finishMove(completed)
    }

    /// Plays a move given in engine notation ("e2e4", "e7e8q"). Returns false if it isn't legal.
    @discardableResult
    func playEngineMove(_ uci: String) -> Bool {
        guard uci.count >= 4, pendingPromotion == nil, !isGameOver else { return false }
        let from = Square(String(uci.prefix(2)))
        let to = Square(String(uci.dropFirst(2).prefix(2)))
        guard piece(at: from)?.color == sideToMove, board.canMove(pieceAt: from, to: to) else { return false }

        var promotion: Piece.Kind = .queen
        if uci.count == 5, let letter = uci.last, let kind = Piece.Kind(rawValue: letter.uppercased()) {
            promotion = kind
        }
        return play(from: from, to: to, promotion: promotion)
    }

    /// Takes back the last move, or cancels a promotion in progress.
    func undo() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        lastMove = snapshot.lastMove
        ledger = snapshot.ledger
        lastPlayed = nil
        if pendingPromotion == nil { _ = moves.popLast() }
        pendingPromotion = nil
        clearSelection()
        syncPieces()
    }

    /// Starts again from the standard position, or any other (like one set up from a photo).
    func newGame(from position: Position = .standard) {
        history.removeAll()
        board = Board(position: position)
        ledger = PieceLedger(startingFrom: position)
        lastMove = nil
        lastPlayed = nil
        pendingPromotion = nil
        captureEvents = []
        moves = []
        clearSelection()
        syncPieces()
    }

    // MARK: Private

    /// Plays a move. `promotion` is used right away when given; otherwise the
    /// player is asked to choose.
    @discardableResult
    private func play(from: Square, to: Square, promotion: Piece.Kind?) -> Bool {
        let before = Snapshot(board: board, lastMove: lastMove, ledger: ledger)
        let fenBefore = fen
        guard let move = board.move(pieceAt: from, to: to) else {
            clearSelection()
            return false
        }
        history.append(before)
        lastMove = LastMove(from: from, to: to)
        fenBeforePendingMove = fenBefore
        clearSelection()

        if case .promotion(let pawnMove) = board.state {
            if let promotion {
                finishMove(board.completePromotion(of: pawnMove, to: promotion))
            } else {
                pendingPromotion = pawnMove
                syncPieces()
            }
        } else {
            finishMove(move)
        }
        return true
    }

    private func finishMove(_ move: Move) {
        var isCapture = false
        var isCastle = false
        switch move.result {
        case .capture(let captured):
            isCapture = true
            captureEvents.append(CaptureEvent(id: nextEventID, piece: captured))
            nextEventID += 1
            if captureEvents.count > 6 { captureEvents.removeFirst(captureEvents.count - 6) }
        case .castle:
            isCastle = true
        case .move:
            break
        }

        lastPlayed = PlayedMove(
            uci: move.lan,
            san: move.san,
            color: move.piece.color,
            fenBefore: fenBeforePendingMove ?? fen,
            isCapture: isCapture,
            isCastle: isCastle,
            givesCheck: move.checkState == .check || move.checkState == .checkmate
        )
        fenBeforePendingMove = nil
        if let before = history.last?.board.position {
            var mate = false
            if case .checkmate = board.state { mate = true }
            ledger?.record(from: before, to: board.position, endedInMate: mate)
        }
        moves.append(move.san)
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
