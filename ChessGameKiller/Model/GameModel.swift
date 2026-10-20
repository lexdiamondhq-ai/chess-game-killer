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
    /// What the starting position really is. ChessKit only judges check and mate as a
    /// move is made; handed a position whole, it looks at the side that isn't moving,
    /// so a start in check would read as quiet.
    private var startState: Board.State = .active
    /// How many of each piece each side began with, so the rails show only what was taken.
    private var startCounts: [Piece.Color: [Piece.Kind: Int]] = [:]
    /// Castling rights ChessKit keeps after the rook was captured on its home square,
    /// as FEN letters. Rights never come back, so a home square without its own rook
    /// settles it for good.
    private var lostCastling: Set<Character> = []

    private struct Snapshot {
        let board: Board
        let lastMove: LastMove?
        let ledger: PieceLedger?
        let lostCastling: Set<Character>
    }

    /// Starts from the standard position, or any other (useful for lessons and tests).
    init(position: Position = .standard) {
        board = Board(position: position)
        ledger = PieceLedger(startingFrom: position)
        startState = Self.stateAtStart(of: board)
        startCounts = Self.counts(in: position)
        noteLostCastling()
        syncPieces()
    }

    // MARK: Reading the position

    var sideToMove: Piece.Color { board.position.sideToMove }

    /// Whose turn it is as a player sees it: the promoting side until it has chosen a piece.
    var activeColor: Piece.Color { pendingPromotion?.piece.color ?? sideToMove }

    /// The position as FEN, without the castling rights ChessKit keeps for a rook
    /// that was captured on its home square.
    var fen: String {
        let raw = board.position.fen
        guard !lostCastling.isEmpty else { return raw }
        var fields = raw.split(separator: " ").map(String.init)
        guard fields.count == 6 else { return raw }
        fields[2].removeAll { lostCastling.contains($0) }
        if fields[2].isEmpty { fields[2] = "-" }
        return fields.joined(separator: " ")
    }

    func piece(at square: Square) -> Piece? {
        board.position.piece(at: square)
    }

    /// The board's state, with the starting position judged for the side to move.
    var state: Board.State { history.isEmpty ? startState : board.state }

    var isGameOver: Bool {
        switch state {
        case .checkmate, .draw: return true
        default: return false
        }
    }

    /// The winner, if the game ended in checkmate.
    var winner: Piece.Color? {
        if case .checkmate(let loser) = state { return loser.opposite }
        return nil
    }

    private static let pieceValues: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9]

    /// What `color` has taken: each kind of the opponent's pieces missing from the
    /// board with how many are gone, biggest first. Kinds with none taken are left out.
    /// A side with more of a kind than it started with has promoted pawns, and those
    /// pawns were not taken.
    func captured(by color: Piece.Color) -> [CapturedCount] {
        let start = startCounts[color.opposite] ?? [:]
        var onBoard: [Piece.Kind: Int] = [:]
        for placed in pieces where placed.piece.color == color.opposite {
            onBoard[placed.piece.kind, default: 0] += 1
        }
        let promoted = onBoard.reduce(0) { $0 + max(0, $1.value - (start[$1.key] ?? 0)) }
        let order: [Piece.Kind] = [.queen, .rook, .bishop, .knight, .pawn]
        return order.compactMap { kind in
            var count = (start[kind] ?? 0) - (onBoard[kind] ?? 0)
            if kind == .pawn { count -= promoted }
            return count > 0 ? CapturedCount(kind: kind, count: count) : nil
        }
    }

    /// How far ahead `color` is in material, in pawns. Negative when behind.
    func materialLead(for color: Piece.Color) -> Int {
        pieces.reduce(0) { $0 + (Self.pieceValues[$1.piece.kind] ?? 0) * ($1.piece.color == color ? 1 : -1) }
    }

    var canUndo: Bool { !history.isEmpty }

    /// Number of moves played (by both sides) that can be taken back.
    var plyCount: Int { history.count }

    /// Whether a person is the one to move now.
    var isHumanTurn: Bool { humanColors.contains(sideToMove) }

    /// The square of the king that is in check, if any.
    var checkedKing: Square? {
        let color: Piece.Color
        switch state {
        case .check(let c), .checkmate(let c): color = c
        default: return nil
        }
        return board.position.pieces.first { $0.kind == .king && $0.color == color }?.square
    }

    var status: String { status(white: "White", black: "Black") }

    /// Whose turn it is or how the game ended, using the theme's names for the sides.
    func status(white: String, black: String) -> String {
        func name(_ color: Piece.Color) -> String { color == .white ? white : black }
        switch state {
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
            targets = Set(board.legalMoves(forPieceAt: square).filter { !isLostCastling(from: square, to: $0) })
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
        guard
            piece(at: from)?.color == sideToMove, board.canMove(pieceAt: from, to: to),
            !isLostCastling(from: from, to: to)
        else { return false }

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
        lostCastling = snapshot.lostCastling
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
        startState = Self.stateAtStart(of: board)
        startCounts = Self.counts(in: position)
        lostCastling = []
        noteLostCastling()
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
        let before = Snapshot(board: board, lastMove: lastMove, ledger: ledger, lostCastling: lostCastling)
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
            let id = nextEventID
            nextEventID += 1
            captureEvents.append(CaptureEvent(id: id, piece: captured))
            if captureEvents.count > 6 { captureEvents.removeFirst(captureEvents.count - 6) }
            // The explosion is over in under a second. After that the event only costs
            // drawing time, and would burst again if the board were rebuilt. Ids never
            // repeat, so a removal that lands after a new game finds nothing.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.captureEvents.removeAll { $0.id == id }
            }
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
        noteLostCastling()
        syncPieces()
    }

    private func clearSelection() {
        selected = nil
        targets = []
    }

    /// The home square of each castling right's rook, by FEN letter.
    private static let rookHomes: [(letter: Character, square: Square, color: Piece.Color)] = [
        ("K", .h1, .white), ("Q", .a1, .white), ("k", .h8, .black), ("q", .a8, .black),
    ]

    /// Marks the castling rights whose rook is no longer on its home square. ChessKit
    /// only drops a right when the king or that rook moves, not when the rook is taken.
    private func noteLostCastling() {
        for home in Self.rookHomes
        where board.position.piece(at: home.square) != Piece(.rook, color: home.color, square: home.square) {
            lostCastling.insert(home.letter)
        }
    }

    /// Whether a king move is a castling ChessKit still offers although that rook was taken.
    private func isLostCastling(from: Square, to: Square) -> Bool {
        guard piece(at: from)?.kind == .king else { return false }
        switch (from, to) {
        case (.e1, .g1): return lostCastling.contains("K")
        case (.e1, .c1): return lostCastling.contains("Q")
        case (.e8, .g8): return lostCastling.contains("k")
        case (.e8, .c8): return lostCastling.contains("q")
        default: return false
        }
    }

    /// How many of each piece each side has in `position`.
    private static func counts(in position: Position) -> [Piece.Color: [Piece.Kind: Int]] {
        var counts: [Piece.Color: [Piece.Kind: Int]] = [:]
        for piece in position.pieces {
            counts[piece.color, default: [:]][piece.kind, default: 0] += 1
        }
        return counts
    }

    /// The state of a position handed to the board whole. ChessKit judges the side that
    /// just moved, which at the start is the side that is waiting, so check, mate and
    /// stalemate are worked out here for the side to move. (A waiting side with no
    /// moves is reported as stalemate by ChessKit for the same reason, so that is
    /// judged again too.)
    private static func stateAtStart(of board: Board) -> Board.State {
        guard board.state == .active || board.state == .draw(reason: .stalemate) else { return board.state }
        let position = board.position
        let side = position.sideToMove
        let hasMoves = position.pieces.contains { piece in
            piece.color == side && !board.legalMoves(forPieceAt: piece.square).isEmpty
        }
        let inCheck = PositionDraft(fen: position.fen)?.isInCheck(side) ?? false
        if !hasMoves { return inCheck ? .checkmate(color: side) : .draw(reason: .stalemate) }
        if position.hasInsufficientMaterial { return .draw(reason: .insufficientMaterial) }
        return inCheck ? .check(color: side) : .active
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
