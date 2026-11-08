import SwiftUI

/// The rival's voice on the game screen: its taunt and its remarks in bold blood red, in
/// Creepster's dripping letters (Alex, 2026-11-08: "bold red with dripping letters"). Wrapped
/// to two lines, so the whole line is read and never cut off.
///
/// Creepster (SIL OFL, Rivals/Fonts) is narrow and its letters run small for their size, so it
/// is set a little larger than the line's own type.
struct BloodLetters: ViewModifier {
    let theme: BoardTheme

    /// The footnote's size, half again as large as the person's line, and a touch more for Creepster.
    static let size: CGFloat = 13 * 1.6

    /// Bright enough to read on the dark glass, deeper on the light looks.
    private var blood: Color {
        theme.isDark ? Color(red: 0.88, green: 0.08, blue: 0.11) : Color(red: 0.66, green: 0.03, blue: 0.06)
    }

    func body(content: Content) -> some View {
        content
            .font(.custom("Creepster-Regular", size: Self.size, relativeTo: .footnote))
            .foregroundStyle(blood)
            // A faint wet sheen around the letters, and a dark edge under them so they sit in the glass.
            .shadow(color: blood.opacity(theme.isDark ? 0.4 : 0.2), radius: 5)
            .shadow(color: .black.opacity(theme.isDark ? 0.55 : 0.15), radius: 0, y: 1)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// The rival's taunt and remarks, in dripping blood red.
    func bloodLetters(_ theme: BoardTheme) -> some View {
        modifier(BloodLetters(theme: theme))
    }
}
