import ChessKit
import Foundation

/// The Traffic Light habit, worked through for the position on the board.
/// Red: what are they threatening? Yellow: my checks, captures and attacks.
/// Green: is everything of mine safe before I move?
struct TrafficLightScan: Equatable {
    let red: [String]
    let yellow: [String]
    let green: [String]

    /// Looks at the position from the side to move. `lastMove` is the
    /// opponent's move that led here, when there was one.
    init?(fen: String, lastMove: LastMove?) {
        guard let position = Position(fen: fen) else { return nil }
        let board = Board(position: position)
        let geometry = BoardGeometry(position: position)
        let me = position.sideToMove
        let them = me.opposite

        red = Self.threats(board: board, geometry: geometry, me: me, them: them, lastMove: lastMove)
        yellow = Self.chances(board: board, geometry: geometry)
        green = Self.safety(geometry: geometry, me: me, them: them)
    }

    // MARK: Red: their threats

    private static func threats(
        board: Board, geometry: BoardGeometry, me: Piece.Color, them: Piece.Color, lastMove: LastMove?
    ) -> [String] {
        var lines: [String] = []
        var mentioned = Set<Square>()

        if let king = geometry.king(of: me), let checker = geometry.attackers(of: king, by: them).first,
           let piece = geometry.piece(at: checker) {
            lines.append("You're in check from the \(name(piece)) on \(checker.notation). That comes first.")
        }

        if let lastMove, let mover = geometry.piece(at: lastMove.to), mover.color == them {
            let hits = geometry.attacks(from: lastMove.to).filter { square in
                guard let target = geometry.piece(at: square), target.color == me, target.kind != .king else { return false }
                return geometry.isHanging(square)
                    || BoardGeometry.value(target.kind) > BoardGeometry.value(mover.kind)
            }
            if !hits.isEmpty {
                mentioned.formUnion(hits)
                lines.append("Their \(name(mover)) on \(lastMove.to.notation) attacks your \(list(hits, on: geometry)).")
            }
        }

        if !isInCheck(board), let threat = mateThreat(in: board.position) {
            lines.append("Danger: they threaten checkmate with \(threat).")
        }

        for square in geometry.hangingPieces(of: me) where !mentioned.contains(square) {
            guard let piece = geometry.piece(at: square), lines.count < 4 else { continue }
            lines.append("Your \(name(piece)) on \(square.notation) can be taken.")
        }

        if lines.isEmpty {
            lines.append("No threats right now. Nothing of yours is under attack.")
        }
        return lines
    }

    /// A move that would be checkmate if it were their turn.
    static func mateThreat(in position: Position) -> String? {
        var fields = position.fen.split(separator: " ").map(String.init)
        guard fields.count >= 4 else { return nil }
        fields[1] = fields[1] == "w" ? "b" : "w"
        fields[3] = "-"
        guard let passed = Position(fen: fields.joined(separator: " ")) else { return nil }
        let board = Board(position: passed)
        for uci in TrainingChess.legalMoves(in: board) {
            var copy = board
            if let move = TrainingChess.play(uci, on: &copy), move.checkState == .checkmate {
                return move.san
            }
        }
        return nil
    }

    // MARK: Yellow: my chances

    private static func chances(board: Board, geometry: BoardGeometry) -> [String] {
        var checks: [String] = []
        var captures: [String] = []
        for uci in TrainingChess.legalMoves(in: board) {
            var copy = board
            guard let move = TrainingChess.play(uci, on: &copy) else { continue }
            if TrainingChess.givesCheck(move) {
                checks.append(move.san)
            }
            if case .capture(let victim) = move.result {
                let defended = geometry.isDefended(victim.square, by: victim.color)
                let cheaper = BoardGeometry.value(move.piece.kind) < BoardGeometry.value(victim.kind)
                if !defended {
                    captures.append("\(move.san) (free \(BoardGeometry.name(victim.kind)))")
                } else if cheaper {
                    captures.append("\(move.san) (wins material)")
                } else {
                    captures.append(move.san)
                }
            }
        }

        var lines: [String] = []
        if !checks.isEmpty {
            lines.append("Checks: \(checks.prefix(4).joined(separator: ", ")).")
        }
        if !captures.isEmpty {
            // The juiciest captures first.
            let sorted = captures.sorted { a, b in rank(a) < rank(b) }
            lines.append("Captures: \(sorted.prefix(4).joined(separator: ", ")).")
        }
        if lines.isEmpty {
            lines.append("No checks or captures. Find your least active piece and give it a job.")
        } else {
            lines.append("Check each one: does it win something, or just trade?")
        }
        return lines
    }

    private static func rank(_ capture: String) -> Int {
        if capture.contains("(free") { return 0 }
        if capture.contains("(wins") { return 1 }
        return 2
    }

    // MARK: Green: is it safe?

    private static func safety(geometry: BoardGeometry, me: Piece.Color, them: Piece.Color) -> [String] {
        var lines: [String] = []
        let loose = geometry.pieces
            .filter { $0.value.color == me && $0.value.kind != .king && $0.value.kind != .pawn }
            .filter { !geometry.isDefended($0.key, by: me) && geometry.attackers(of: $0.key, by: them).isEmpty }
            .sorted { BoardGeometry.value($0.value.kind) > BoardGeometry.value($1.value.kind) }
            .prefix(2)
        for (square, piece) in loose {
            lines.append("Your \(name(piece)) on \(square.notation) has no defender. Loose pieces drop off.")
        }
        lines.append("Before you let go of a piece: can anything take it for free on its new square?")
        return lines
    }

    // MARK: Helpers

    private static func isInCheck(_ board: Board) -> Bool {
        switch board.state {
        case .check, .checkmate: return true
        default: return false
        }
    }

    private static func name(_ piece: Piece) -> String {
        BoardGeometry.name(piece.kind)
    }

    private static func list(_ squares: [Square], on geometry: BoardGeometry) -> String {
        let sorted = squares.sorted {
            BoardGeometry.value(geometry.piece(at: $0)?.kind ?? .pawn) > BoardGeometry.value(geometry.piece(at: $1)?.kind ?? .pawn)
        }
        return BoardGeometry.list(sorted.compactMap { square in
            geometry.piece(at: square).map { "\(BoardGeometry.name($0.kind)) on \(square.notation)" }
        })
    }
}
