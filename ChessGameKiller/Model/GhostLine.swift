import ChessKit
import Foundation

/// Ghost Vision: the engine's best line from the position on the board, a few moves ahead,
/// played out on a copy of the game so each step knows which pieces it moves and takes.
/// The board draws each step as see-through pieces, fainter the further ahead they are.
struct GhostLine: Equatable {
    /// One piece's move in a step: castling moves two.
    struct Move: Equatable {
        /// The piece as it lands (a promoted pawn is already its new piece), on its new square.
        let piece: Piece
        let from: Square

        var to: Square { piece.square }
    }

    /// One move of the line.
    struct Step: Equatable, Identifiable {
        /// 0 for the first move of the line.
        let index: Int
        let san: String
        let color: Piece.Color
        /// The moving piece first; with castling, the rook after the king.
        let moves: [Move]
        /// The piece this move takes, on the square it stood on (en passant included).
        let captured: Piece?

        var id: Int { index }
        /// The main piece's move: the one the trail is drawn for.
        var main: Move { moves[0] }
    }

    /// The position the line starts from.
    let fen: String
    let steps: [Step]
    /// The engine's score at the end of the line, for the side to move at its start.
    let evaluation: Evaluation
    /// The move number of the first step, for the strip of moves ("12. Nf3 d5 13. d4").
    let firstMoveNumber: Int

    /// How many moves ahead Ghost Vision looks: the player's move, the reply, and one more each.
    static let depth = 4

    /// Each step's opacity: fainter the further ahead.
    static let opacities: [Double] = [0.6, 0.4, 0.25, 0.15]

    /// The opacity of step `index` when the line is shown up to step `focus`: later steps are hidden.
    static func opacity(of index: Int, focus: Int) -> Double {
        guard index >= 0, index <= focus else { return 0 }
        return opacities[min(index, opacities.count - 1)]
    }

    /// Plays `line` out on a copy of the position, up to `depth` moves, stopping at the first
    /// move that doesn't fit. Nil when not even the first move does.
    static func build(fen: String, line: EngineLine, depth: Int = depth) -> GhostLine? {
        guard let position = Position(fen: fen) else { return nil }
        let probe = GameModel(position: position)
        var steps: [Step] = []
        for uci in line.moves.prefix(depth) {
            guard let squares = Notation.squares(of: uci), let mover = probe.piece(at: squares.from) else { break }
            let from = squares.from, to = squares.to
            let color = probe.sideToMove
            var captured = probe.piece(at: to).flatMap { $0.color == color ? nil : $0 }
            // En passant: a pawn stepping sideways onto an empty square takes the pawn beside it.
            if mover.kind == .pawn, from.fileIndex != to.fileIndex, captured == nil {
                captured = probe.piece(at: Square(file: to.fileIndex, rank: from.rankIndex))
            }
            guard probe.playEngineMove(uci), let played = probe.lastPlayed,
                  let landed = probe.piece(at: to), landed.color == color
            else { break }
            var moves = [Move(piece: landed, from: from)]
            // Castling: the rook comes round the king.
            if mover.kind == .king, abs(to.fileIndex - from.fileIndex) == 2 {
                let kingside = to.fileIndex > from.fileIndex
                let rookFrom = Square(file: kingside ? 7 : 0, rank: from.rankIndex)
                let rookTo = Square(file: kingside ? 5 : 3, rank: from.rankIndex)
                if let rook = probe.piece(at: rookTo), rook.kind == .rook {
                    moves.append(Move(piece: rook, from: rookFrom))
                }
            }
            steps.append(Step(index: steps.count, san: played.san, color: color, moves: moves, captured: captured))
        }
        guard !steps.isEmpty else { return nil }
        let fields = fen.split(separator: " ")
        let number = fields.count >= 6 ? Int(fields[5]) ?? 1 : 1
        return GhostLine(fen: fen, steps: steps, evaluation: line.evaluation, firstMoveNumber: max(1, number))
    }

    /// The line written out for the strip and VoiceOver, like "12. Nf3 d5 13. d4" or "12… d5 13. Nf3".
    func notation(upTo focus: Int? = nil) -> [String] {
        let last = min(focus ?? steps.count - 1, steps.count - 1)
        guard last >= 0 else { return [] }
        var number = firstMoveNumber
        var words: [String] = []
        for step in steps[0...last] {
            if step.color == .white {
                words.append("\(number). \(step.san)")
            } else {
                words.append(step.index == 0 ? "\(number)… \(step.san)" : step.san)
                number += 1
            }
        }
        return words
    }
}
