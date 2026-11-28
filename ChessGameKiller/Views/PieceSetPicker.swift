import SwiftUI

/// Settings > Pieces: one big card at a time, swiped through, and the set in the middle is the
/// one the board wears (Alex, 2026-11-27, pick A: "Swiping should change, slowly turning, show
/// the whole family"). The card in the middle is the real 3D set, slowly turning on a round of
/// the board's stone; the cards either side peek in, still. It took over from a 3x2 grid of small
/// tiles; those pictures stay as the card when the 3D pieces can't load.
struct PieceSetPicker: View {
    @Binding var selection: PieceSet
    /// The board the sets are shown on: the one picked under Board.
    let board: SculptedLook
    let accent: Color

    /// The card in the middle, as the swipe settles.
    @State private var centered: PieceSet?
    @State private var width: CGFloat = 340

    /// How much of the width the middle card takes; the rest is its neighbors peeking in.
    private static let share: CGFloat = 0.74
    private static let spacing: CGFloat = 12

    private var cardSide: CGFloat { (width * Self.share).rounded() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.spacing) {
                    ForEach(PieceSet.allCases) { set in
                        card(set)
                            .id(set)
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.4)) { centered = set }
                            }
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered)
            .safeAreaPadding(.horizontal, (width - cardSide) / 2)
            .frame(height: cardSide + 8)

            let shown = centered ?? selection
            VStack(spacing: 4) {
                Text(shown.title)
                    .font(.display(.title3, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(shown.blurb)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: shown)
            .accessibilityHidden(true)

            dots(shown)
                .padding(.top, 10)
        }
        .padding(.vertical, 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { centered = selection }
        // Swiping picks: the set that settles in the middle is the one the board wears.
        .onChange(of: centered) { _, set in
            guard let set, set != selection else { return }
            withAnimation(.easeInOut(duration: 0.35)) { selection = set }
        }
        // A pick made anywhere else brings its card round.
        .onChange(of: selection) { _, set in
            guard centered != set else { return }
            withAnimation(.snappy(duration: 0.4)) { centered = set }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pieces")
        .accessibilityValue("\(selection.title). \(selection.blurb)")
        .accessibilityAdjustableAction { direction in
            let all = PieceSet.allCases
            guard let index = all.firstIndex(of: selection) else { return }
            switch direction {
            case .increment where index + 1 < all.count: selection = all[index + 1]
            case .decrement where index > 0: selection = all[index - 1]
            default: break
            }
        }
    }

    private func card(_ set: PieceSet) -> some View {
        let isOn = set == (centered ?? selection)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return ZStack {
            // The dark of the tiles' studio, warming toward the stone.
            LinearGradient(colors: [Color(white: 0.04), Color(red: 0.16, green: 0.12, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
            if SculptedAssets.shared.isLoaded {
                PieceSetShowcaseView(look: set.dress(board), turning: isOn)
            } else {
                set.preview
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: cardSide, height: cardSide)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
        .padding(3)
        .overlay {
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .strokeBorder(accent, lineWidth: set == selection ? 2 : 0)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.2), value: set == selection)
    }

    /// Where the card in the middle sits among the six: a gold bar for it, dots for the rest.
    private func dots(_ shown: PieceSet) -> some View {
        HStack(spacing: 7) {
            ForEach(PieceSet.allCases) { set in
                Capsule()
                    .fill(set == shown ? accent : Color.secondary.opacity(0.3))
                    .frame(width: set == shown ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: shown)
        .accessibilityHidden(true)
    }
}
