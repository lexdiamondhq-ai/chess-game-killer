import SwiftUI

struct BoardView: View {
    let board: Board
    var theme: BoardTheme = .walnut

    private let files = ["a", "b", "c", "d", "e", "f", "g", "h"]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sq = side / 8
            VStack(spacing: 0) {
                ForEach((0..<8).reversed(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            square(rank: rank, file: file, size: sq)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: sq * 0.25, y: sq * 0.08)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func square(rank: Int, file: Int, size: CGFloat) -> some View {
        let isLight = (rank + file) % 2 == 1
        let labelColor = isLight ? theme.dark : theme.light
        return ZStack {
            Rectangle().fill(isLight ? theme.light : theme.dark)

            if let piece = board.squares[rank][file] {
                Image(piece.assetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(size * 0.04)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.02)
                    .accessibilityLabel("\(piece.color) \(piece.kind)")
            }

            // Coordinates in the corners, like a printed board.
            if file == 0 {
                Text("\(rank + 1)")
                    .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(size * 0.05)
            }
            if rank == 0 {
                Text(files[file])
                    .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.05)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    BoardView(board: .starting).padding()
}
