import SwiftUI

/// How a rival's words look under its name on the game screen (Alex, 2026-11-08). Its taunt
/// and its remarks wrap to two lines, so the whole line is read and never cut off.
///
/// - The Ashen King, the last of them, speaks in bold blood red, in Creepster's dripping letters.
/// - The rivals below him speak in tarnished silver (New Rocker): old iron script, dark and
///   gloomy, in heavy shadow (Alex picked it from the variations, 2026-11-08).
///
/// Both fonts are SIL OFL, bundled in Rivals/Fonts.
struct RivalLetters: ViewModifier {
    enum Voice {
        /// The Ashen King.
        case blood
        /// Every other rival.
        case gloom

        init(_ level: MatchController.Level) {
            self = level == .grandmaster ? .blood : .gloom
        }
    }

    let voice: Voice
    let theme: BoardTheme

    /// Half again as large as the person's line, and a touch more: both faces run small.
    static let size: CGFloat = 13 * 1.6

    private var font: Font {
        switch voice {
        case .blood: return .custom("Creepster-Regular", size: Self.size, relativeTo: .footnote)
        case .gloom: return .custom("NewRocker-Regular", size: Self.size - 0.8, relativeTo: .footnote)
        }
    }

    /// Blood bright enough to read on the dark glass and deeper on the light looks; tarnished
    /// silver on dark, a near-black slate on light.
    private var ink: Color {
        switch voice {
        case .blood: return theme.isDark ? Color(red: 0.88, green: 0.08, blue: 0.11) : Color(red: 0.66, green: 0.03, blue: 0.06)
        case .gloom: return theme.isDark ? Color(red: 0.62, green: 0.64, blue: 0.67) : Color(red: 0.24, green: 0.24, blue: 0.26)
        }
    }

    /// Blood has a faint wet sheen; silver sits in heavy shadow.
    private var halo: Color {
        switch voice {
        case .blood: return ink.opacity(theme.isDark ? 0.4 : 0.2)
        case .gloom: return .black.opacity(theme.isDark ? 0.95 : 0.25)
        }
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(ink)
            .shadow(color: halo, radius: voice == .gloom ? 8 : 5)
            .shadow(color: .black.opacity(theme.isDark ? 0.6 : 0.15), radius: 0, y: 1)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }
}

extension View {
    /// The rival's taunt and remarks: blood red for the Ashen King, tarnished silver for the rest.
    func rivalLetters(_ voice: RivalLetters.Voice, theme: BoardTheme) -> some View {
        modifier(RivalLetters(voice: voice, theme: theme))
    }
}
