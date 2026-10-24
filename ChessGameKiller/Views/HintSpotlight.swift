import ChessKit
import SwiftUI
import UIKit

/// Move hints as a spotlight: the rest of the board dims, the piece the coach would move and
/// the square it should go to stay lit, and the move is said in words under the board.
/// Only the best move is ever lit, so there is one thing to look at.
enum HintSpotlight {
    /// The warm light on the two lit squares, the same on every look.
    static let gold = Color(red: 1, green: 0.84, blue: 0.47)
    static let uiGold = UIColor(red: 1, green: 0.84, blue: 0.47, alpha: 1)
    /// How dark the unlit squares get.
    static let dim: Double = 0.5
    /// The 3D board's lit stone reads brighter, so it dims a little more.
    static let dim3D: Double = 0.62
    /// One beat of the target's breathing, in seconds.
    static let beat: Double = 0.9
}

/// The coach's move in plain words: "Knight takes the queen", "Pawn to e4, check",
/// "Castle kingside".
enum HintWords {
    static func phrase(san: String, mover: Piece.Kind?, taken: Piece.Kind?) -> String {
        var ending = ""
        if san.hasSuffix("#") {
            ending = ", checkmate"
        } else if san.hasSuffix("+") {
            ending = ", check"
        }
        if san.hasPrefix("O-O-O") { return "Castle queenside" + ending }
        if san.hasPrefix("O-O") { return "Castle kingside" + ending }

        let name = (mover.map(Self.name) ?? "piece").capitalized
        let square = Self.destination(in: san)
        var words: String
        if san.contains("x") {
            // En passant takes a pawn that isn't on the square the pawn lands on.
            words = "\(name) takes the \(taken.map(Self.name) ?? "pawn")"
        } else {
            words = square.map { "\(name) to \($0)" } ?? name
        }
        if let promotion = Self.promotion(in: san) {
            words += ", becomes a \(Self.name(promotion))"
        }
        return words + ending
    }

    static func phrase(for hint: MoveHint, in game: GameModel) -> String {
        phrase(san: hint.san, mover: game.piece(at: hint.from)?.kind, taken: game.piece(at: hint.to)?.kind)
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

    /// The landing square in standard notation, like "e4" in "Nxe4+".
    private static func destination(in san: String) -> String? {
        let letters = Array(san)
        for index in stride(from: letters.count - 2, through: 0, by: -1) {
            let file = letters[index], rank = letters[index + 1]
            if ("a"..."h").contains(file), ("1"..."8").contains(rank) {
                return String([file, rank])
            }
        }
        return nil
    }

    private static func promotion(in san: String) -> Piece.Kind? {
        guard let equals = san.firstIndex(of: "=") else { return nil }
        let letter = san[san.index(after: equals)...].first
        switch letter {
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return nil
        }
    }
}

/// A lit square's light. The piece's square glows softly; the square it should go to has a
/// bright ring that breathes.
struct SpotlightMark: View {
    let size: CGFloat
    let isTarget: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let gold = HintSpotlight.gold
        ZStack {
            RadialGradient(colors: [gold.opacity(isTarget ? 0.42 : 0.34), gold.opacity(0)],
                           center: .center, startRadius: 0, endRadius: size * 0.62)
            if isTarget {
                let line = size * 0.055
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                    .strokeBorder(gold, lineWidth: line)
                    .padding(size * 0.04)
                    .shadow(color: gold.opacity(0.9), radius: size * 0.08)
                    .opacity(breathing ? 0.55 : 1)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard isTarget, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: HintSpotlight.beat).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
