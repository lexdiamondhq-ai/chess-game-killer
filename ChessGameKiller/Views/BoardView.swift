import SwiftUI

struct BoardView: View {
    let board: Board

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) / 8
            VStack(spacing: 0) {
                ForEach((0..<8).reversed(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            ZStack {
                                Rectangle()
                                    .fill((rank + file) % 2 == 0 ? Color.brown : Color(white: 0.93))
                                if let piece = board.squares[rank][file] {
                                    Text(piece.symbol)
                                        .font(.system(size: size * 0.75))
                                }
                            }
                            .frame(width: size, height: size)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
