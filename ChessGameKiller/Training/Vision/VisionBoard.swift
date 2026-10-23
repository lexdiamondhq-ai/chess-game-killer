import ChessKit
import SwiftUI

/// Where the squares sit on a board drawn the way TrainingBoardView draws it, so the
/// vision screens can draw on it and take taps from it: the frame around the squares on
/// the pictured boards, the size of a square, and which square is where from either side.
struct VisionBoardLayout {
    /// The whole board, frame included.
    let side: CGFloat
    /// The frame around the squares: half a square on the pictured boards, none on drawn ones.
    let inset: CGFloat
    let squareSize: CGFloat
    let flipped: Bool

    init(side: CGFloat, theme: BoardTheme, flipped: Bool) {
        self.side = side
        inset = theme.frameInset(side: side)
        squareSize = (side - inset * 2) / 8
        self.flipped = flipped
    }

    /// The column and row a square is drawn in, counted from the top left.
    func cell(of square: Square) -> (column: Int, row: Int) {
        flipped
            ? (7 - square.fileIndex, square.rankIndex)
            : (square.fileIndex, 7 - square.rankIndex)
    }

    /// The square drawn in a column and row.
    func square(column: Int, row: Int) -> Square {
        flipped
            ? Square(file: 7 - column, rank: row)
            : Square(file: column, rank: 7 - row)
    }

    /// The middle of a square, from the board's top left corner, frame included.
    func center(of square: Square) -> CGPoint {
        let cell = cell(of: square)
        return CGPoint(x: inset + (CGFloat(cell.column) + 0.5) * squareSize,
                       y: inset + (CGFloat(cell.row) + 0.5) * squareSize)
    }
}

/// The coordinates drill's board: the theme's squares with no letters or numbers on
/// them, and a soft flash on each square tapped, in the accent when right and red when wrong.
struct VisionBoard: View {
    let theme: BoardTheme
    var flipped = false
    var flashes: [CoordinatesDrill.Flash] = []
    /// Taps on squares. Nil makes the board look-only.
    var onTap: ((Square) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let layout = VisionBoardLayout(side: min(geo.size.width, geo.size.height), theme: theme, flipped: flipped)
            let corner = RoundedRectangle(cornerRadius: layout.squareSize * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                if let art = theme.boardArt {
                    BoardArt(name: art, flipped: flipped)
                }
                if let surface = theme.surface {
                    LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                squares(layout)
                    .padding(layout.inset)
                flashLayer(layout)
            }
            .frame(width: layout.side, height: layout.side)
            .clipShape(corner)
            .overlay {
                if let edge = theme.boardEdge {
                    corner.strokeBorder(edge, lineWidth: 1)
                }
            }
            .background {
                ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                    corner.fill(color)
                        .blur(radius: layout.squareSize * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                        .offset(y: theme.isDark ? 0 : layout.squareSize * 0.08)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func squares(_ layout: VisionBoardLayout) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        squareView(layout.square(column: column, row: row), size: layout.squareSize)
                    }
                }
            }
        }
    }

    private func squareView(_ square: Square, size: CGFloat) -> some View {
        let isLight = (square.fileIndex + square.rankIndex) % 2 == 1
        return ZStack {
            Rectangle().fill(theme.squareFill(isLight: isLight))
            if let gridLine = theme.gridLine {
                Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(square) }
        .accessibilityElement()
        .accessibilityLabel(square.notation)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    /// Each flash lights up at once and fades as the drill drops it.
    private func flashLayer(_ layout: VisionBoardLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(flashes) { flash in
                let color = flash.right ? theme.trainingAccent : TrainingColor.red.color(on: theme)
                let center = layout.center(of: flash.square)
                Rectangle()
                    .fill(color.opacity(flash.right ? 0.5 : 0.6))
                    .frame(width: layout.squareSize, height: layout.squareSize)
                    .shadow(color: theme.glows ? color : .clear, radius: layout.squareSize * 0.15)
                    .position(center)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(width: layout.side, height: layout.side, alignment: .topLeading)
        .animation(.easeOut(duration: 0.35), value: flashes)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the player has marked on a board scan, drawn over TrainingBoardView in the same
/// places: a soft ring in the accent on each square found, a small red cross on each
/// slip and, once the position is revealed, a dashed amber ring on each square missed.
struct ScanMarks: View {
    let theme: BoardTheme
    let flipped: Bool
    let found: Set<Square>
    let slips: [Square]
    let missed: [Square]

    var body: some View {
        GeometryReader { geo in
            let layout = VisionBoardLayout(side: min(geo.size.width, geo.size.height), theme: theme, flipped: flipped)
            let size = layout.squareSize
            ZStack(alignment: .topLeading) {
                ForEach(missed, id: \.self) { square in
                    missedRing(size: size)
                        .position(layout.center(of: square))
                        .transition(.opacity)
                }
                ForEach(found.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { square in
                    foundRing(size: size)
                        .position(layout.center(of: square))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ForEach(slips, id: \.self) { square in
                    let center = layout.center(of: square)
                    slipCross(size: size)
                        .position(x: center.x + size * 0.27, y: center.y - size * 0.27)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: layout.side, height: layout.side, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.snappy(duration: 0.25), value: found)
        .animation(.snappy(duration: 0.25), value: slips)
        .animation(.easeOut(duration: 0.3), value: missed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func foundRing(size: CGFloat) -> some View {
        let accent = theme.trainingAccent
        let shape = RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
        return ZStack {
            shape.fill(accent.opacity(0.16))
            shape.strokeBorder(accent, lineWidth: size * 0.06)
        }
        .padding(size * 0.04)
        .frame(width: size, height: size)
        .shadow(color: theme.glows ? accent.opacity(0.8) : .clear, radius: size * 0.12)
    }

    private func missedRing(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
            .strokeBorder(TrainingColor.orange.color(on: theme),
                          style: StrokeStyle(lineWidth: size * 0.06, dash: [size * 0.16, size * 0.1]))
            .padding(size * 0.04)
            .frame(width: size, height: size)
    }

    private func slipCross(size: CGFloat) -> some View {
        let red = TrainingColor.red.color(on: theme)
        return Image(systemName: "xmark")
            .font(.system(size: size * 0.17, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size * 0.32, height: size * 0.32)
            .background(red, in: Circle())
            .shadow(color: theme.glows ? red : .black.opacity(0.3), radius: theme.glows ? size * 0.1 : 2, y: theme.glows ? 0 : 1)
    }
}
