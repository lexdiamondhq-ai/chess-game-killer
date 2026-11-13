import SwiftUI

/// The ways to play a person from the New Game sheet, which is the one door to every game
/// (Alex, 2026-11-11: New game, A friend and Online felt like one screen). Play a friend and,
/// when the app can reach other players, Play online, as rows of one frosted card in the same
/// style as the sheet's match card. Each opens its own screen, as before.
struct ChallengeEntryRow: View {
    let theme: BoardTheme
    let action: () -> Void
    /// Opens Play online. Nil leaves only Play a friend.
    var online: (() -> Void)? = nil
    /// Players waiting online now, when known.
    var waiting: Int? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) {
            row(glyph: Glyphs.challenge, title: "Play a friend", detail: "by username or link",
                label: "Play a friend, by username or link", action: action)
            if let online {
                Divider()
                    .overlay(Color.primary.opacity(0.06))
                    .padding(.leading, 58)
                row(glyph: Glyphs.online, title: "Play online", detail: onlineDetail,
                    label: "Play online, \(onlineDetail)", action: online)
            }
        }
        .background {
            shape
                .fill(theme.screenIsDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .overlay { shape.strokeBorder(Color.primary.opacity(theme.screenIsDark ? 0.12 : 0.08), lineWidth: 1) }
                .shadow(color: .black.opacity(theme.screenIsDark ? 0.3 : 0.08), radius: 16, y: 6)
        }
        .clipShape(shape)
    }

    private var onlineDetail: String {
        guard let waiting, waiting > 0 else { return "someone at your level" }
        return waiting == 1 ? "1 waiting now" : "\(waiting) waiting now"
    }

    private func row(glyph: String, title: String, detail: String, label: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphTile(theme: theme) { Glyph(name: glyph, size: 22) }
                (Text(title)
                    .font(.app(.callout, weight: .bold))
                    .foregroundStyle(.primary)
                    + Text("  ·  \(detail)")
                    .font(.app(.footnote))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel(label)
    }
}
