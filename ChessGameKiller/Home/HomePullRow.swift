import SwiftUI

/// The quick ways in that show over the board once the sheet is pulled down by its grabber:
/// a new game, a friend, Today's Move and Analyze, as four glass tiles with the gold icon over
/// the name. The strip under them already resumes or plays, so these are the other doors.
struct HomePullRow: View {
    struct Item: Identifiable {
        let id: String
        let glyph: String
        let title: String
        let action: () -> Void
    }

    let items: [Item]
    let tone: HomeTone

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Button(action: item.action) {
                    VStack(spacing: 7) {
                        Glyph(name: item.glyph, size: 26)
                            .foregroundStyle(tone.metal)
                        Text(item.title)
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(tone.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .homePane(RoundedRectangle(cornerRadius: 20, style: .continuous), tone: tone)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(HomePressStyle())
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, 16)
        // Four tiles share the width: past this size the names would no longer fit.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
