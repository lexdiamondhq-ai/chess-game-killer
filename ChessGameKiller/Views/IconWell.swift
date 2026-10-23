import SwiftUI

/// The small square that holds a row's icon, as the home screen draws its icons: a dark,
/// slightly sunken well with the symbol in soft ivory ink, not a tile tinted in the accent.
/// Used by the New Game sheet, Challenge a friend and Settings, so every sheet matches the home.
struct IconWell<Icon: View>: View {
    var size: CGFloat = 34
    var radius: CGFloat = 11
    var isDark = true
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        icon()
            .foregroundStyle(isDark ? Color(red: 0.965, green: 0.945, blue: 0.91).opacity(0.82) : Color.primary.opacity(0.78))
            .frame(width: size, height: size)
            .background(Color.black.opacity(isDark ? 0.34 : 0.07), in: shape)
            .overlay {
                // a fine dark line inside the top edge and a faint light one at the bottom: a well, not a button
                shape.strokeBorder(
                    LinearGradient(colors: [Color.black.opacity(isDark ? 0.45 : 0.12), Color.white.opacity(isDark ? 0.09 : 0.5)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }
}
