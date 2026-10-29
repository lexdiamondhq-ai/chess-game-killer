import SwiftUI

/// A round badge for a move grade, like a star for the best move or "??" for a blunder.
struct GradeBadge: View {
    let grade: MoveReview.Grade
    var glows = false
    /// The look it sits on: away from Neon the grade takes its calm color. Without one, the bright one.
    var theme: BoardTheme? = nil

    private var color: Color { theme.map { grade.color(on: $0) } ?? grade.color }

    var body: some View {
        ZStack {
            Circle().fill(color)
            switch grade.mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 17, weight: .bold))
            case .text(let text):
                Text(text)
                    .font(.app(size: 16, weight: .heavy))
            }
        }
        .foregroundStyle(.black.opacity(0.8))
        .frame(width: 38, height: 38)
        .shadow(color: glows ? color.opacity(0.8) : .clear, radius: 8)
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

    /// The grade's color on a look. Neon keeps the bright ones; every other look gets
    /// calmer tones that sit with its wood and stone, and a mate takes the look's accent.
    func color(on theme: BoardTheme) -> Color {
        if theme.glows { return color }
        switch self {
        case .checkmate: return theme.accent ?? .accentColor
        case .best: return Color(hex: 0x7FC8A0)
        case .excellent: return Color(hex: 0x7CC0B2)
        case .good: return Color(hex: 0x8AB6C8)
        case .inaccuracy: return Color(hex: 0xD4B05C)
        case .mistake: return Color(hex: 0xD88C52)
        case .blunder: return Color(hex: 0xD46A6A)
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
