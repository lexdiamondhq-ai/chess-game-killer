import SwiftUI

/// The way into Challenge a friend from the New Game sheet: one compact row, in the same
/// frosted card as the sheet's match card, with the same dark icon tile as its rows.
struct ChallengeEntryRow: View {
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphTile(theme: theme) { Glyph(name: Glyphs.challenge, size: 22) }
                (Text("Challenge a friend")
                    .font(.system(.callout, design: theme.challengeDesign).weight(.bold))
                    .foregroundStyle(.primary)
                    + Text("  ·  by text or email")
                    .font(.system(.footnote, design: theme.challengeDesign))
                    .foregroundStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(minHeight: 60)
            .background {
                shape
                    .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                    .overlay { shape.strokeBorder(Color.primary.opacity(theme.isDark ? 0.12 : 0.08), lineWidth: 1) }
                    .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.08), radius: 16, y: 6)
            }
            .contentShape(shape)
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel("Challenge a friend, by text or email")
    }
}
