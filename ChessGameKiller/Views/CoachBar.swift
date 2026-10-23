import SwiftUI

/// A round badge for a move grade, like a star for the best move or "??" for a blunder.
struct GradeBadge: View {
    let grade: MoveReview.Grade
    var glows = false

    var body: some View {
        ZStack {
            Circle().fill(grade.color)
            switch grade.mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 17, weight: .bold))
            case .text(let text):
                Text(text)
                    .font(.system(size: 16, weight: .heavy, design: .themed))
            }
        }
        .foregroundStyle(.black.opacity(0.8))
        .frame(width: 38, height: 38)
        .shadow(color: glows ? grade.color.opacity(0.8) : .clear, radius: 8)
        .accessibilityHidden(true)
    }
}

/// A short line in the arrow's style, for the legend under the coach.
struct ArrowSample: View {
    let color: Color
    let dashed: Bool

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 2, y: 5))
            path.addLine(to: CGPoint(x: 24, y: 5))
        }
        .stroke(color, style: StrokeStyle(lineWidth: dashed ? 3 : 4, lineCap: dashed ? .butt : .round,
                                          dash: dashed ? [5, 3] : []))
        .frame(width: 26, height: 10)
        .accessibilityHidden(true)
    }
}

extension MoveReview.Grade {
    enum Mark {
        case symbol(String)
        case text(String)
    }

    var color: Color {
        switch self {
        case .checkmate: return Color(hex: 0xFFD54A)
        case .best: return Color(hex: 0x3DFF9A)
        case .excellent: return Color(hex: 0x5BE0B0)
        case .good: return Color(hex: 0x8FD7FF)
        case .inaccuracy: return Color(hex: 0xF7D046)
        case .mistake: return Color(hex: 0xFF9A3C)
        case .blunder: return Color(hex: 0xFF4D6D)
        }
    }

    /// Chess's own marks where they exist: ?! inaccuracy, ? mistake, ?? blunder.
    var mark: Mark {
        switch self {
        case .checkmate: return .symbol("crown.fill")
        case .best: return .symbol("star.fill")
        case .excellent: return .symbol("hand.thumbsup.fill")
        case .good: return .symbol("checkmark")
        case .inaccuracy: return .text("?!")
        case .mistake: return .text("?")
        case .blunder: return .text("??")
        }
    }
}
