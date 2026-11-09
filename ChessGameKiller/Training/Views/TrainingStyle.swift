import ChessKit
import SwiftUI

// Shared look for the screens around the board (training, puzzles, Today's Move and the
// sheets): the home's own room, glass and buttons, in the Light, Middle or Dark the reader
// picked for the home. On the older home they keep the board theme's style instead:
// paper and soft shadows on light boards, glass and glow on dark ones.

extension HomeTone {
    /// The home's colors for a screen around a board drawn in `theme`, or nil on the older
    /// home, where the screens keep the board's own room.
    static func screen(for theme: BoardTheme, sheet: Bool, mode: HomeToneMode) -> HomeTone? {
        guard sheet else { return nil }
        return .of(theme.sculptedLook ?? .gilded, mode: mode)
    }
}

extension BoardTheme {
    /// The home's colors on the screens around this board (see `HomeTone.screen`), as saved.
    var screenTone: HomeTone? {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: HomeToneMode.key).flatMap(HomeToneMode.init(rawValue:)) ?? .defaultMode
        return HomeTone.screen(for: self, sheet: HomeLayout.usesSheet(defaults), mode: mode)
    }

    /// Whether the page around the board is dark: the home's tone, or the board's own room.
    /// The board itself still goes by `isDark`.
    var screenIsDark: Bool { screenTone.map { $0.scheme == .dark } ?? isDark }

    /// The frame's letters and numbers: the look's own pale ink, or a dark one where the frame's
    /// clear glass sits on a light page and the pale ink would be lost.
    func frameLabel(on scheme: ColorScheme) -> Color {
        isDark && scheme == .light ? Color.black.opacity(0.5) : labelOnDark
    }
}

/// Puts a screen in the home's colors: its light or dark, and the pieces' metal for links and
/// controls. Follows the home's setting as it changes.
private struct ScreenScheme: ViewModifier {
    let theme: BoardTheme
    @AppStorage(HomeLayout.key) private var sheet = HomeLayout.defaultOn
    @AppStorage(HomeToneMode.key) private var mode = HomeToneMode.defaultMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if let tone = HomeTone.screen(for: theme, sheet: sheet, mode: mode) {
            content
                .preferredColorScheme(tone.scheme)
                .tint(tone.metal)
        } else {
            content.preferredColorScheme(theme.isDark ? .dark : nil)
        }
    }
}

extension View {
    /// The screen's light or dark: the home's, or the board's on the older home.
    func screenScheme(_ theme: BoardTheme) -> some View {
        modifier(ScreenScheme(theme: theme))
    }
}

extension TrainingColor {
    func color(on theme: BoardTheme) -> Color {
        Color(hex: hex(on: theme))
    }

    /// The color as 0xRRGGBB: brighter on a dark screen. The 3D board takes it this way.
    func hex(on theme: BoardTheme) -> UInt32 {
        if theme.screenIsDark {
            switch self {
            case .red: return 0xFF4D6D
            case .yellow: return 0xF7D046
            case .green: return 0x3DFF9A
            case .blue: return 0x5AA9FF
            case .violet: return 0xB98CFF
            case .teal: return 0x50F0E6
            case .orange: return 0xFF9A3C
            case .pink: return 0xFF5AC8
            }
        }
        switch self {
        case .red: return 0xD93636
        case .yellow: return 0xE9A800
        case .green: return 0x2E9E48
        case .blue: return 0x2F74E0
        case .violet: return 0x7B4AE2
        case .teal: return 0x0E9688
        case .orange: return 0xEE7A12
        case .pink: return 0xDB3F86
        }
    }
}

extension BoardTheme {
    /// The training screens' main color: the home's metal, or the board's own accent.
    var trainingAccent: Color { screenTone?.metal ?? accent ?? .accentColor }

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

/// The room behind the training views: the home's, or on the older home the game screen's.
struct TrainingBackdrop: View {
    let theme: BoardTheme
    @AppStorage(HomeLayout.key) private var sheet = HomeLayout.defaultOn
    @AppStorage(HomeToneMode.key) private var mode = HomeToneMode.defaultMode

    var body: some View {
        if let tone = HomeTone.screen(for: theme, sheet: sheet, mode: mode) {
            HomeBackdrop(tone: tone)
        } else {
            ThemeBackdrop(theme: theme)
        }
    }
}

/// A rounded card: the home's glass, with a fine edge in the tint when there is one. On the
/// older home, the app's shared glass on the dark boards (see GlassPane), paper with a soft
/// shadow on light ones, and Neon keeps its colored edge and halo.
struct TrainingCard: ViewModifier {
    let theme: BoardTheme
    var tint: Color?
    var cornerRadius: CGFloat = 22
    @AppStorage(HomeLayout.key) private var sheet = HomeLayout.defaultOn
    @AppStorage(HomeToneMode.key) private var mode = HomeToneMode.defaultMode

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let edge = tint ?? theme.trainingAccent
        if let tone = HomeTone.screen(for: theme, sheet: sheet, mode: mode) {
            content
                .homePane(shape, tone: tone)
                .overlay {
                    if let tint {
                        shape.strokeBorder(tint.opacity(0.55), lineWidth: 1).allowsHitTesting(false)
                    }
                }
        } else if theme.isDark, !theme.glows {
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

/// A big rounded button: the home's ivory button, or its clear glass one when not prominent
/// (a tint fills it instead, for an answer's color). On the older home, the board's accent:
/// solid on the executive looks, Neon's glowing gradient on Neon.
struct TrainingButtonStyle: ButtonStyle {
    let theme: BoardTheme
    var prominent = true
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        TrainingButton(theme: theme, prominent: prominent, tint: tint, configuration: configuration)
    }
}

private struct TrainingButton: View {
    let theme: BoardTheme
    let prominent: Bool
    let tint: Color?
    let configuration: ButtonStyleConfiguration
    @AppStorage(HomeLayout.key) private var sheet = HomeLayout.defaultOn
    @AppStorage(HomeToneMode.key) private var mode = HomeToneMode.defaultMode

    var body: some View {
        if let tone = HomeTone.screen(for: theme, sheet: sheet, mode: mode) {
            homeButton(tone)
        } else {
            boardButton
        }
    }

    private func homeButton(_ tone: HomeTone) -> some View {
        configuration.label
            .font(.app(.headline))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            // A quiet button keeps the page's ink: a tint (a hint's yellow) only colors its edge
            // and fill, since a pale tint would be lost as text on a light page.
            .foregroundStyle(prominent ? (tint == nil ? tone.onIvory : (tone.scheme == .dark ? Color.black : Color.white))
                             : tone.ink)
            .background {
                if prominent, let tint {
                    Capsule().fill(tint)
                } else if prominent {
                    HomeIvoryFill(tone: tone)
                } else {
                    Capsule()
                        .fill((tint ?? tone.ink).opacity(configuration.isPressed ? 0.2 : (tint == nil ? 0.08 : 0.16)))
                        .overlay { Capsule().strokeBorder((tint ?? tone.ink).opacity(tint == nil ? 0.18 : 0.5), lineWidth: 0.75) }
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }

    private var boardButton: some View {
        let color = tint ?? theme.trainingAccent
        return configuration.label
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

    @Environment(\.colorScheme) private var colorScheme

    /// Leo's ring when he isn't reacting: Neon's glass gradient, or the board's own
    /// accent (gold on Fabergé, amber on Blueprint), the page's metal on a light page.
    private var restingRing: [Color] {
        if theme.id == .neon {
            return [Color(hex: 0x19C6CF), Color(hex: 0x9B4BEA), Color(hex: 0xE04BC4), Color(hex: 0x19C6CF)]
        }
        let accent = colorScheme == .dark ? (theme.accent ?? theme.trainingAccent) : theme.trainingAccent
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
