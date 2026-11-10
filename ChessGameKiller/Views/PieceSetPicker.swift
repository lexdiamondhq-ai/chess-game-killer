import SwiftUI

/// A grid of piece-set tiles, drawn like the app icon tiles; tapping one changes the pieces on
/// the 3D board, and the preview at the top of Settings with them.
struct PieceSetPicker: View {
    @Binding var selection: PieceSet
    let accent: Color

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(PieceSet.allCases) { set in
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { selection = set }
                } label: {
                    tile(set)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(set.title) pieces")
                .accessibilityAddTraits(set == selection ? .isSelected : [])
            }
        }
        .padding(14)
    }

    private func tile(_ set: PieceSet) -> some View {
        let isOn = set == selection
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return VStack(spacing: 8) {
            set.preview
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent, lineWidth: isOn ? 2 : 0)
                }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            Text(set.title)
                .font(.app(.caption, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }
}
