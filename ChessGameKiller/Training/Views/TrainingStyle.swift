import ChessKit
import SwiftUI

// Shared look for the training screens, drawn in the board theme's style:
// paper and soft shadows on light boards, glass and glow on dark ones.

extension TrainingColor {
    func color(on theme: BoardTheme) -> Color {
        if theme.isDark {
            switch self {
            case .red: return Color(hex: 0xFF4D6D)
            case .yellow: return Color(hex: 0xF7D046)
            case .green: return Color(hex: 0x3DFF9A)
            case .blue: return Color(hex: 0x5AA9FF)
            case .violet: return Color(hex: 0xB98CFF)
            case .teal: return Color(hex: 0x50F0E6)
            case .orange: return Color(hex: 0xFF9A3C)
            case .pink: return Color(hex: 0xFF5AC8)
            }
        }
        switch self {
        case .red: return Color(hex: 0xD93636)
        case .yellow: return Color(hex: 0xE9A800)
        case .green: return Color(hex: 0x2E9E48)
        case .blue: return Color(hex: 0x2F74E0)
        case .violet: return Color(hex: 0x7B4AE2)
        case .teal: return Color(hex: 0x0E9688)
        case .orange: return Color(hex: 0xEE7A12)
        case .pink: return Color(hex: 0xDB3F86)
        }
    }
}

extension BoardTheme {
    /// The training screens' main color.
    var trainingAccent: Color { accent ?? .accentColor }

    func trainingTone(_ tone: LessonPlayer.Tone) -> Color {
        switch tone {
        case .coach: return trainingAccent
        case .success: return TrainingColor.green.color(on: self)
        case .wrong: return TrainingColor.orange.color(on: self)
        case .hint: return TrainingColor.yellow.color(on: self)
        }
    }

    func trainingTone(_ tone: DrillRunner.Tone) -> Color {
        switch tone {
        case .coach: return trainingAccent
        case .success: return TrainingColor.green.color(on: self)
        case .wrong: return TrainingColor.orange.color(on: self)
        case .hint: return TrainingColor.yellow.color(on: self)
        }
    }
}

/// The screen behind the training views: the same backdrop as the game screen.
struct TrainingBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        ThemeBackdrop(theme: theme)
    }
}

/// A rounded card: the app's shared glass on the dark boards (see GlassPane), paper with a
/// soft shadow on light ones. Neon keeps its colored edge and halo.
struct TrainingCard: ViewModifier {
    let theme: BoardTheme
    var tint: Color?
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let edge = tint ?? theme.trainingAccent
        if theme.isDark, !theme.glows {
            content.glassPane(shape, tint: tint)
        } else {
            content.background {
                if theme.isDark {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.strokeBorder(
                                LinearGradient(colors: [edge.opacity(0.85), edge.opacity(0.12)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: edge.opacity(0.28), radius: 14)
                } else {
                    shape
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay {
                            if let tint {
                                shape.strokeBorder(tint.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
                }
            }
        }
    }
}

extension View {
    func trainingCard(_ theme: BoardTheme, tint: Color? = nil, cornerRadius: CGFloat = 22) -> some View {
        modifier(TrainingCard(theme: theme, tint: tint, cornerRadius: cornerRadius))
    }
}

/// A big rounded button in the board's accent: solid on the executive looks, Neon's
/// glowing gradient on Neon.
struct TrainingButtonStyle: ButtonStyle {
    let theme: BoardTheme
    var prominent = true
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let color = tint ?? theme.trainingAccent
        configuration.label
            .font(.app(.headline))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .foregroundStyle(prominent ? (theme.isDark ? Color.black : Color.white) : color)
            .background {
                Capsule()
                    .fill(prominent ? AnyShapeStyle(fill(color)) : AnyShapeStyle(color.opacity(theme.isDark ? 0.16 : 0.12)))
                    .shadow(color: prominent && theme.glows ? color.opacity(0.55) : .clear, radius: 12)
            }
            .overlay {
                if !prominent, theme.isDark {
                    Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private func fill(_ color: Color) -> LinearGradient {
        if theme.glows, tint == nil {
            return LinearGradient(colors: [Color(hex: 0x7CF7FF), Color(hex: 0xB98CFF)],
                                  startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [color, color], startPoint: .leading, endPoint: .trailing)
    }
}

/// The coach's portrait: a piece from the board's own set in a ring, the knight for Leo and the queen for Vera.
struct CoachAvatar: View {
    let theme: BoardTheme
    var size: CGFloat = 44
    /// The ring's color, to react to answers.
    var tint: Color?
    /// Whose portrait: the picked coach unless one is named (the picker shows both).
    var coach: Coach?

    /// Leo's ring when he isn't reacting: Neon's glass gradient, or the board's own
    /// accent (gold on Fabergé, amber on Blueprint).
    private var restingRing: [Color] {
        if theme.id == .neon {
            return [Color(hex: 0x19C6CF), Color(hex: 0x9B4BEA), Color(hex: 0xE04BC4), Color(hex: 0x19C6CF)]
        }
        let accent = theme.trainingAccent
        return [accent, accent.opacity(0.55), accent]
    }

    /// Behind the knight: Neon's night blue, or the board's dark side (midnight, ink).
    private var face: Color {
        theme.id == .neon ? Color(hex: 0x0B0D1E) : theme.blackSide
    }

    var body: some View {
        let ring = tint.map { [$0, $0.opacity(0.6), $0] } ?? restingRing
        ZStack {
            Circle().fill(face)
            // Leo is the knight, Vera the queen.
            PieceImage(piece: Piece((coach ?? Coach.current).piece, color: .white, square: .g1), theme: theme, size: size * 0.78)
            Circle().strokeBorder(AngularGradient(colors: ring, center: .center), lineWidth: max(2, size * 0.06))
        }
        .frame(width: size, height: size)
        .shadow(color: theme.glows ? (tint ?? (theme.id == .neon ? Color(hex: 0x9B4BEA) : theme.trainingAccent)).opacity(0.55) : .black.opacity(0.12),
                radius: theme.glows ? size * 0.18 : 3, y: theme.glows ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: tint)
        .accessibilityHidden(true)
    }
}

/// A ring that fills as a skill is mastered.
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: progress)
    }
}

/// The three lights of the habit: red, yellow, green.
struct TrafficLightDots: View {
    let theme: BoardTheme
    var size: CGFloat = 10
    /// Which light to brighten, or nil for all.
    var lit: Int?

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(Array([TrainingColor.red, .yellow, .green].enumerated()), id: \.offset) { index, light in
                let color = light.color(on: theme)
                let on = lit == nil || lit == index
                Circle()
                    .fill(color.opacity(on ? 1 : 0.25))
                    .frame(width: size, height: size)
                    .shadow(color: on && theme.glows ? color : .clear, radius: size * 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "White to move" with a dot in the side's color, or another short line. Instructions say
/// White and Black, as chess notation does, whatever the look calls its sides. It sits under the board,
/// never over the back rank, and keeps its space while hidden so nothing jumps.
struct TurnBadge: View {
    let theme: BoardTheme
    let side: Piece.Color
    var text: String?
    var showing = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.sideColor(side))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 10, height: 10)
            Text(text ?? "\(side.displayName) to move")
                .font(.app(.caption, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassPane(Capsule())
        .opacity(showing ? 1 : 0)
        .accessibilityHidden(!showing)
        .animation(.easeInOut(duration: 0.2), value: showing)
        .animation(.easeInOut(duration: 0.2), value: text)
    }
}

/// A small capsule label, like "+10 XP" or "Mixed".
struct TrainingChip: View {
    let text: String
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.app(.caption2, weight: .bold))
            }
            Text(text).font(.app(.caption, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

extension Rank {
    /// The piece this rank is named after, for its badge.
    var pieceKind: Piece.Kind {
        switch piece {
        case "knight": return .knight
        case "bishop": return .bishop
        case "rook": return .rook
        case "queen": return .queen
        case "king": return .king
        default: return .pawn
        }
    }
}
