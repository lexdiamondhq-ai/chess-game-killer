import ChessKit
import SwiftUI

/// The board in lessons and drills: the game board's look (squares or the
/// pre-rendered 3D board, and its pieces), plus the coach's arrows, glowing
/// squares and little labels.
struct TrainingBoardView: View {
    let game: GameModel
    let theme: BoardTheme
    var flipped = false
    var arrows: [BoardArrow] = []
    var marks: [SquareMark] = []
    var labels: [SquareLabel] = []
    /// Taps on squares. Nil makes the board look-only.
    var onTap: ((Square) -> Void)?

    @AppStorage("haptics") private var hapticsOn = true

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = theme.frameInset(side: side)
            let sq = (side - inset * 2) / 8
            let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                // Only the board is cut to its rounded corners, so a tall piece on the far rank
                // may rise a little above the frame.
                ZStack {
                    if let art = theme.boardArt {
                        BoardArt(name: art, flipped: flipped)
                    }
                    if let surface = theme.surface {
                        LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(corner)
                ZStack(alignment: .topLeading) {
                    squares(size: sq)
                    markLayer(size: sq)
                    pieceLayer(size: sq)
                    arrowLayer(size: sq)
                    labelLayer(size: sq)
                }
                .frame(width: sq * 8, height: sq * 8)
                .padding(inset)
            }
            .frame(width: side, height: side)
            .overlay {
                if let edge = theme.boardEdge {
                    corner.strokeBorder(edge, lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) { explosions(size: sq).padding(inset) }
            .background {
                ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                    corner.fill(color)
                        .blur(radius: sq * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                        .offset(y: theme.isDark ? 0 : sq * 0.08)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: game.moveCount) { _, _ in hapticsOn }
        // Capture events are dropped once the explosion is over, which changes the
        // trigger a second time; only a new capture should thump.
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: game.captureEvents.last?.id) { _, new in
            hapticsOn && new != nil
        }
    }

    // MARK: Layout

    private func cell(of square: Square) -> (column: Int, row: Int) {
        flipped
            ? (7 - square.fileIndex, square.rankIndex)
            : (square.fileIndex, 7 - square.rankIndex)
    }

    private func center(of square: Square, size: CGFloat) -> CGPoint {
        let cell = cell(of: square)
        return CGPoint(x: (CGFloat(cell.column) + 0.5) * size, y: (CGFloat(cell.row) + 0.5) * size)
    }

    private func square(column: Int, row: Int) -> Square {
        flipped
            ? Square(file: 7 - column, rank: row)
            : Square(file: column, rank: 7 - row)
    }

    /// A square from its name, or nil if the name isn't one.
    private func square(named name: String) -> Square? {
        let files: ClosedRange<Character> = "a"..."h"
        let ranks: ClosedRange<Character> = "1"..."8"
        guard name.count == 2, let file = name.first, let rank = name.last,
              files.contains(file), ranks.contains(rank) else { return nil }
        return Square(name)
    }

    // MARK: Squares

    private func squares(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        squareView(square(column: column, row: row), column: column, row: row, size: size)
                    }
                }
            }
        }
    }

    private func squareView(_ square: Square, column: Int, row: Int, size: CGFloat) -> some View {
        let isLight = (square.fileIndex + square.rankIndex) % 2 == 1
        let labelColor = isLight ? theme.labelOnLight : theme.labelOnDark
        let occupant = game.piece(at: square)
        let isTarget = game.targets.contains(square)
        let ringWidth = size * 0.035

        return ZStack {
            Rectangle().fill(theme.squareFill(isLight: isLight))
            if let gridLine = theme.gridLine {
                Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
            }
            if let last = game.lastMove, last.from == square || last.to == square {
                Rectangle().fill(theme.lastMove)
                if let ring = theme.lastMoveRing {
                    Rectangle().strokeBorder(ring, lineWidth: ringWidth)
                }
            }
            if game.selected == square {
                Rectangle().fill(theme.selected)
                if let ring = theme.selectedRing {
                    Rectangle().strokeBorder(ring, lineWidth: ringWidth)
                        .shadow(color: ring, radius: size * 0.08)
                }
            }
            if game.checkedKing == square {
                CheckSquareMark(color: theme.check, size: size)
            }
            if column == 0 {
                coordinate("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
            }
            if row == 7 {
                coordinate(square.file.rawValue, size: size, color: labelColor, alignment: .bottomTrailing)
            }
            if isTarget {
                Group {
                    if occupant == nil {
                        Circle().fill(theme.hint).frame(width: size * 0.3, height: size * 0.3)
                    } else {
                        Circle().strokeBorder(theme.hint, lineWidth: size * 0.08).padding(size * 0.02)
                    }
                }
                .shadow(color: theme.hintGlow ?? .clear, radius: theme.hintGlow == nil ? 0 : size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onTap else { return }
            withAnimation(.snappy(duration: 0.22)) { onTap(square) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(square, occupant: occupant, isTarget: isTarget))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private func coordinate(_ text: String, size: CGFloat, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: size * 0.2, weight: .semibold, design: .themed))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(size * 0.05)
    }

    private func accessibilityLabel(_ square: Square, occupant: Piece?, isTarget: Bool) -> String {
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if isTarget { parts.append(occupant == nil ? "move here" : "capture") }
        if let label = labels.first(where: { $0.square == square.notation }) { parts.append(label.text) }
        if marks.contains(where: { $0.square == square.notation }) { parts.append("highlighted") }
        return parts.joined(separator: ", ")
    }

    // MARK: Glowing squares

    private func markLayer(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(uniqueMarks, id: \.self) { mark in
                if let square = square(named: mark.square) {
                    let color = (mark.color ?? .yellow).color(on: theme)
                    let cell = cell(of: square)
                    ZStack {
                        Rectangle().fill(color.opacity(theme.isDark ? 0.26 : 0.34))
                        Rectangle()
                            .strokeBorder(color, lineWidth: size * 0.055)
                            .shadow(color: theme.glows ? color : .clear, radius: size * 0.12)
                    }
                    .frame(width: size, height: size)
                    .offset(x: CGFloat(cell.column) * size, y: CGFloat(cell.row) * size)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
        .frame(width: size * 8, height: size * 8, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: uniqueMarks)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var uniqueMarks: [SquareMark] {
        var seen = Set<SquareMark>()
        return marks.filter { seen.insert($0).inserted }
    }

    // MARK: Pieces

    private func pieceLayer(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.pieces) { placed in
                PieceImage(piece: placed.piece, theme: theme, size: size, onBoard: true)
                    .scaleEffect(game.selected == placed.square ? 1.08 : 1)
                    .position(center(of: placed.square, size: size))
                    // Nearer rows draw last, so tall 3D pieces overlap the ones behind them.
                    .zIndex(Double(cell(of: placed.square).row))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .animation(.snappy(duration: 0.35), value: game.pieces)
        // A lesson or drill that jumps to another position hands the board a fresh
        // model, whose piece ids start over. Tie the layer to the model so the old
        // pieces fade out and the new ones fade in, instead of each id sliding to
        // whatever piece now holds its number.
        .transition(.opacity)
        .id(ObjectIdentifier(game))
        .animation(.easeInOut(duration: 0.25), value: ObjectIdentifier(game))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Arrows and labels

    private func arrowLayer(size: CGFloat) -> some View {
        ZStack {
            ForEach(uniqueArrows, id: \.self) { arrow in
                if let from = square(named: arrow.from), let to = square(named: arrow.to) {
                    CoachArrow(
                        from: center(of: from, size: size),
                        to: center(of: to, size: size),
                        squareSize: size,
                        dashed: arrow.dashed ?? false,
                        color: (arrow.color ?? .green).color(on: theme),
                        glows: theme.glows
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(width: size * 8, height: size * 8)
        .animation(.easeInOut(duration: 0.25), value: uniqueArrows)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var uniqueArrows: [BoardArrow] {
        var seen = Set<BoardArrow>()
        return arrows.filter { seen.insert($0).inserted }
    }

    private func labelLayer(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.self) { label in
                if let square = square(named: label.square) {
                    let color = (label.color ?? .blue).color(on: theme)
                    let cell = cell(of: square)
                    Text(label.text)
                        .font(.system(size: size * 0.24, weight: .heavy, design: .themed))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(theme.isDark ? Color.black : Color.white)
                        .padding(.horizontal, size * 0.07)
                        .frame(minWidth: size * 0.38, minHeight: size * 0.34)
                        .background(color, in: Capsule())
                        .shadow(color: theme.glows ? color.opacity(0.9) : .black.opacity(0.25),
                                radius: theme.glows ? size * 0.1 : 2, y: theme.glows ? 0 : 1)
                        .position(x: (CGFloat(cell.column) + 0.76) * size, y: (CGFloat(cell.row) + 0.24) * size)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .frame(width: size * 8, height: size * 8, alignment: .topLeading)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: labels)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Captures

    private func explosions(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.captureEvents) { event in
                CaptureFall(piece: event.piece, theme: theme, size: size, seed: event.id)
                    .position(center(of: event.piece.square, size: size))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The coach's arrow: solid, or dashed for "maybe" moves and threats.
struct CoachArrow: View {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat
    let dashed: Bool
    let color: Color
    let glows: Bool

    var body: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length
        let uy = dy / length
        let headLength = squareSize * 0.4
        let headWidth = squareSize * 0.46
        let shaftWidth = squareSize * (dashed ? 0.12 : 0.15)
        let start = CGPoint(x: from.x + ux * squareSize * 0.2, y: from.y + uy * squareSize * 0.2)
        let tip = CGPoint(x: to.x - ux * squareSize * 0.1, y: to.y - uy * squareSize * 0.1)
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)

        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: base)
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: shaftWidth,
                lineCap: dashed ? .butt : .round,
                dash: dashed ? [shaftWidth * 1.6, shaftWidth * 1.1] : []
            ))
            Path { path in
                path.move(to: tip)
                path.addLine(to: CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2))
                path.addLine(to: CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2))
                path.closeSubpath()
            }
            .fill(color)
        }
        .opacity(glows ? 1 : 0.88)
        .shadow(color: glows ? color.opacity(0.85) : .black.opacity(0.18), radius: glows ? squareSize * 0.1 : 1.5)
    }
}
