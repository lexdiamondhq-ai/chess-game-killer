import ChessKit
import SwiftUI
import UIKit

/// The interactive board: tap a piece to see its moves, tap a dot to play.
/// With hints on, the coach's picks are marked by corner brackets on the piece and a
/// ringed dot where it should go. A taken piece tips over and falls away.
struct BoardView: View {
    let match: MatchController
    var theme: BoardTheme = .neon
    /// An earlier position the player is looking back at. Only the 3D board shows it
    /// itself; the flat board has it laid over the top instead.
    var browsing: Position?
    var endBrowsing: (() -> Void)?

    @AppStorage("haptics") private var hapticsOn = true
    /// The player's army, so veteran pieces show their glow, scar and name.
    @Environment(ArmyStore.self) private var army: ArmyStore?

    /// The sculpted looks play on a real 3D board unless the player asked for them flat.
    @AppStorage("sculpted3D") private var sculpted3D = true

    private var game: GameModel { match.game }
    private var flipped: Bool { match.isBoardFlipped }

    var body: some View {
        if Self.playsIn3D(theme, setting: sculpted3D) {
            SculptedBoardView(match: match, theme: theme, browsing: browsing, endBrowsing: endBrowsing)
        } else {
            flatBoard
        }
    }

    /// Whether this look plays on the real 3D board, given the "3D pieces" setting.
    static func playsIn3D(_ theme: BoardTheme, setting: Bool) -> Bool {
        theme.sculptedLook != nil && setting && SculptedAssets.shared.isLoaded
    }

    /// Width over height of the board: the 3D board, seen at an angle, is wider than tall.
    static func aspect(_ theme: BoardTheme, setting: Bool) -> CGFloat {
        playsIn3D(theme, setting: setting) ? SculptedBoardView.aspect : 1
    }

    private var flatBoard: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = theme.frameInset(side: side)
            let sq = (side - inset * 2) / 8
            let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
            ZStack(alignment: .topLeading) {
                // Only the board itself is cut to its rounded corners: a tall piece on the far
                // rank may rise a little above the frame, as it would on a real board.
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
                    pieces(size: sq)
                    nameTag(size: sq)
                    CheckCalloutLayer(game: game, color: theme.check) { square in
                        calloutPoint(over: square, size: sq)
                    }
                    .frame(width: sq * 8, height: sq * 8)
                    // A flag that falls mid-promotion puts the pawn back; this just makes sure
                    // the picker never outlives the game.
                    if let promotion = game.pendingPromotion, !match.isOver {
                        PromotionPicker(color: promotion.piece.color, theme: theme, squareSize: sq) { kind in
                            withAnimation(.snappy(duration: 0.2)) { match.promote(to: kind) }
                        }
                        .transition(.opacity)
                    }
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
            // Falling pieces sit outside the clip, so one on the edge can fall past it.
            .overlay(alignment: .topLeading) { captures(size: sq).padding(inset) }
            .background {
                // Soft shadow or colored glow (Neon) around the board.
                ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                    corner.fill(color)
                        .blur(radius: sq * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                        .offset(y: theme.isDark ? 0 : sq * 0.08)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: game.moveCount) { _, _ in hapticsOn }
        .sensoryFeedback(.warning, trigger: game.personInCheck) { _, new in hapticsOn && new != nil }
        // Capture events are dropped once the fall is over, which changes the
        // trigger a second time; only a new capture should thump.
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: game.captureEvents.last?.id) { _, new in
            hapticsOn && new != nil
        }
    }

    // MARK: Layout

    /// Where a square is drawn: column 0 is the left edge, row 0 the top.
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

    // MARK: Squares, highlights and hints

    /// The pieces the coach suggests moving, true for the best move's piece.
    private var hintedPieces: [Square: Bool] {
        match.hints.reduce(into: [:]) { result, hint in result[hint.from] = (result[hint.from] ?? false) || hint.rank == 0 }
    }

    /// Where the selected piece's suggested moves land, true for the best one.
    private var hintedTargets: [Square: Bool] {
        guard let selected = game.selected else { return [:] }
        return match.hints.filter { $0.from == selected }
            .reduce(into: [:]) { result, hint in result[hint.to] = (result[hint.to] ?? false) || hint.rank == 0 }
    }

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
        let hintedTarget = isTarget ? hintedTargets[square] : nil
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
                        .shadow(color: theme.glows ? ring : .clear, radius: size * 0.08)
                }
            }
            if game.checkedKing == square {
                CheckSquareMark(color: theme.check, size: size)
            }
            // The coach's pick: brackets in the corners, clear of the coordinates.
            if let isBest = hintedPieces[square] {
                HintBrackets(color: theme.hint, size: size, skipTopLeading: column == 0, skipBottomTrailing: row == 7)
                    .opacity(isBest ? 1 : 0.5)
            }

            // Coordinates in the corners, like a printed board.
            if column == 0 {
                coordinate("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
            }
            if row == 7 {
                coordinate(square.file.rawValue, size: size, color: labelColor, alignment: .bottomTrailing)
            }

            // Where the selected piece can go: a dot on empty squares, a ring around captures.
            if isTarget {
                MoveDot(occupied: occupant != nil, hint: hintedTarget, color: theme.hint, glow: theme.hintGlow, size: size)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { match.tap(square) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(square, occupant: occupant, isTarget: isTarget, hinted: hintedTarget))
        .accessibilityAddTraits(.isButton)
    }

    private func coordinate(_ text: String, size: CGFloat, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: size * 0.2, weight: .semibold, design: .themed))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(size * 0.05)
    }

    private func accessibilityLabel(_ square: Square, occupant: Piece?, isTarget: Bool, hinted: Bool?) -> String {
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if isTarget { parts.append(occupant == nil ? "move here" : "capture") }
        if let hinted { parts.append(hinted ? "the coach's best move" : "the coach's second choice") }
        if let hint = match.hints.first(where: { $0.from == square }) {
            parts.append(hint.rank == 0 ? "best move \(hint.san)" : "second best move \(hint.san)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Pieces

    /// Pieces sit in their own layer so they can slide between squares.
    private func pieces(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.pieces) { placed in
                PieceImage(piece: placed.piece, theme: theme, size: size, onBoard: true)
                    .modifier(VeteranAura(rank: armyRank(of: placed), piece: placed.piece, theme: theme, size: size))
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
        // The computer's moves arrive without a tap, so animate every change here.
        .animation(.snappy(duration: 0.3), value: game.pieces)
        .animation(.snappy(duration: 0.45), value: flipped)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Army

    private func armyRank(of placed: PlacedPiece) -> ArmyRank {
        guard let army, let slot = army.slot(of: placed, in: match) else { return .recruit }
        return army.record(for: slot).rank
    }

    /// The selected piece's name, floating above it (below it on the top row).
    @ViewBuilder
    private func nameTag(size: CGFloat) -> some View {
        if let army, let square = game.selected,
           let placed = game.pieces.first(where: { $0.square == square }),
           let slot = army.slot(of: placed, in: match),
           let name = army.record(for: slot).name {
            let rank = army.record(for: slot).rank
            let center = center(of: square, size: size)
            let onTop = cell(of: square).row == 0
            // The board is clipped at its edge, so the capsule is kept inside it by
            // its measured width rather than a fixed number of squares.
            NameTagPlacement(x: center.x, y: center.y + size * (onTop ? 0.8 : (theme.spritePieces ? -1.15 : -0.75))) {
                ArmyNameTag(name: name, rank: rank, color: rank.color(for: placed.piece, theme: theme))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .frame(width: size * 8, height: size * 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Where the check callout floats: over the king's head, or under its foot on the top row.
    private func calloutPoint(over square: Square, size: CGFloat) -> CGPoint {
        let center = center(of: square, size: size)
        let onTop = cell(of: square).row == 0
        return CGPoint(x: center.x, y: center.y + size * (onTop ? 0.85 : (theme.spritePieces ? -1.2 : -0.8)))
    }

    // MARK: Captures

    /// Each taken piece falls where it stood, away from the piece that took it.
    private func captures(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.captureEvents) { event in
                CaptureFall(piece: event.piece, theme: theme, size: size, seed: event.id,
                            away: fallDirection(of: event))
                    .position(center(of: event.piece.square, size: size))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Which way a taken piece falls on screen: away from the side the capture came from.
    /// Nil for a capture straight up or down the board.
    private func fallDirection(of event: CaptureEvent) -> CGFloat? {
        guard let from = event.from else { return nil }
        let dx = cell(of: event.piece.square).column - cell(of: from).column
        return dx == 0 ? nil : (dx > 0 ? 1 : -1)
    }
}

/// Centers its one child over a point, shifted inward as far as needed to keep
/// the whole child within the bounds. A child wider than the bounds is centered.
struct NameTagPlacement: Layout {
    var x: CGFloat
    var y: CGFloat

    private static let margin: CGFloat = 2

    /// The point animates, so the tag slides when the selection moves to another piece.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let tag = subviews.first else { return }
        let half = tag.sizeThatFits(.unspecified).width / 2
        let lowest = bounds.minX + half + Self.margin
        let highest = bounds.maxX - half - Self.margin
        let centerX = lowest <= highest ? min(max(bounds.minX + x, lowest), highest) : bounds.midX
        tag.place(at: CGPoint(x: centerX, y: bounds.minY + y), anchor: .center, proposal: .unspecified)
    }
}

/// An arrow from one square to another. Solid for the best move, dashed for the runner-up.
struct MoveArrow: View {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat
    let isBest: Bool
    let color: Color
    let glow: Color?

    var body: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length
        let uy = dy / length
        let headLength = squareSize * (isBest ? 0.42 : 0.36)
        let headWidth = squareSize * (isBest ? 0.5 : 0.42)
        let shaftWidth = squareSize * (isBest ? 0.17 : 0.11)
        // Start a little off the piece's center, stop at the arrowhead.
        let start = CGPoint(x: from.x + ux * squareSize * 0.18, y: from.y + uy * squareSize * 0.18)
        let tip = CGPoint(x: to.x - ux * squareSize * 0.08, y: to.y - uy * squareSize * 0.08)
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)

        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: base)
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: shaftWidth,
                lineCap: isBest ? .round : .butt,
                dash: isBest ? [] : [shaftWidth * 1.6, shaftWidth * 1.1]
            ))

            Path { path in
                path.move(to: tip)
                path.addLine(to: CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2))
                path.addLine(to: CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2))
                path.closeSubpath()
            }
            .fill(color)
        }
        .shadow(color: glow?.opacity(isBest ? 0.9 : 0.6) ?? .black.opacity(0.15),
                radius: glow == nil ? 1 : squareSize * (isBest ? 0.12 : 0.08))
    }
}

/// Where the selected piece can go: a dot on an empty square, a ring around a piece it
/// can take. The coach's pick gets a halo ring (fainter for the runner-up), so it stands
/// out among the other dots without an arrow across the board.
struct MoveDot: View {
    let occupied: Bool
    /// Nil for an ordinary move; true for the coach's best move, false for its second choice.
    var hint: Bool? = nil
    let color: Color
    var glow: Color? = nil
    let size: CGFloat

    var body: some View {
        ZStack {
            if occupied {
                if let hint {
                    Circle().fill(color.opacity(hint ? 0.24 : 0.14)).padding(size * 0.02)
                }
                Circle().strokeBorder(color, lineWidth: size * (hint == true ? 0.1 : 0.08)).padding(size * 0.02)
            } else {
                if let hint {
                    Circle()
                        .strokeBorder(color.opacity(hint ? 1 : 0.55), lineWidth: size * (hint ? 0.05 : 0.04))
                        .frame(width: size * 0.66, height: size * 0.66)
                }
                Circle().fill(color).frame(width: size * 0.3, height: size * 0.3)
            }
        }
        .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : size * 0.1)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .accessibilityHidden(true)
    }
}

/// Four brackets in a square's corners: the piece the coach would move.
struct HintBrackets: View {
    let color: Color
    let size: CGFloat
    /// The corners where the board prints its coordinates.
    var skipTopLeading = false
    var skipBottomTrailing = false

    var body: some View {
        let line = size * 0.05
        let inset = size * 0.08
        let arm = size * 0.2
        Path { path in
            let low = inset, high = size - inset
            if !skipTopLeading {
                path.move(to: CGPoint(x: low, y: low + arm))
                path.addLine(to: CGPoint(x: low, y: low))
                path.addLine(to: CGPoint(x: low + arm, y: low))
            }
            path.move(to: CGPoint(x: high - arm, y: low))
            path.addLine(to: CGPoint(x: high, y: low))
            path.addLine(to: CGPoint(x: high, y: low + arm))
            if !skipBottomTrailing {
                path.move(to: CGPoint(x: high, y: high - arm))
                path.addLine(to: CGPoint(x: high, y: high))
                path.addLine(to: CGPoint(x: high - arm, y: high))
            }
            path.move(to: CGPoint(x: low + arm, y: high))
            path.addLine(to: CGPoint(x: low, y: high))
            path.addLine(to: CGPoint(x: low, y: high - arm))
        }
        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}

/// A taken piece leaving the board: it tips over away from the piece that took it,
/// slides a touch and fades, and a soft ring of dust spreads where it stood.
/// Lessons and drills use it too.
struct CaptureFall: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat
    /// Picks the side it falls to when `away` doesn't say.
    let seed: Int
    /// Which way it falls on screen: 1 to the right, -1 to the left.
    var away: CGFloat? = nil

    /// The piece is tipping over.
    @State private var falling = false
    /// It has hit the board: the dust rises.
    @State private var landed = false
    /// The dust has spread and is settling.
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var turn: CGFloat { away ?? (seed % 2 == 0 ? 1 : -1) }
    /// Where the foot meets the square, as a fraction of the square: the renders stand
    /// a little below the middle, the flat pieces at the bottom.
    private var footY: CGFloat { theme.spritePieces ? 0.65 : 0.9 }
    /// A rook or a queen lands harder.
    private var heavy: Bool { piece.kind == .queen || piece.kind == .rook }

    var body: some View {
        // The far edge of the foot, which the piece pivots on as it goes over.
        let pivot = UnitPoint(x: 0.5 + 0.2 * turn, y: footY)
        let motion = !reduceMotion
        ZStack {
            dust
            PieceImage(piece: piece, theme: theme, size: size, onBoard: true)
                .rotationEffect(.degrees(falling && motion ? 80 * turn : 0), anchor: pivot)
                .animation(.easeIn(duration: 0.26), value: falling)
                .offset(x: landed && motion ? turn * size * 0.12 : 0)
                .scaleEffect(landed ? 0.86 : 1, anchor: pivot)
                .opacity(landed ? 0 : 1)
                .animation(.easeOut(duration: motion ? 0.26 : 0.2), value: landed)
        }
        .frame(width: size * 3, height: size * 3)
        .task {
            // After the first frame, so it moves from where it stood.
            falling = true
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 190))
            landed = true
            try? await Task.sleep(for: .milliseconds(70))
            settled = true
        }
    }

    /// A soft ring of dust on the board around the foot, seen at the same slant as the pieces.
    @ViewBuilder
    private var dust: some View {
        if !reduceMotion {
            let spread: CGFloat = heavy ? 2.1 : 1.7
            Ellipse()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: size * (settled ? 0.015 : 0.06))
                .frame(width: size * 0.8, height: size * 0.34)
                .scaleEffect(settled ? spread : 0.75)
                .opacity(settled ? 0 : (landed ? (heavy ? 0.75 : 0.55) : 0))
                .blur(radius: size * 0.02)
                .offset(y: size * (footY - 0.5))
                .animation(settled ? .easeOut(duration: 0.5) : .easeOut(duration: 0.07), value: settled)
                .animation(.easeOut(duration: 0.07), value: landed)
        }
    }
}

/// One piece drawn in the theme's style: a colored glow on Neon,
/// a 3D sprite standing on its square on the pre-rendered themes.
struct PieceImage: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat
    /// On a board, a 3D sprite rises above its square; elsewhere it is fitted into `size`.
    var onBoard = false

    var body: some View {
        if theme.spritePieces {
            sprite
        } else {
            flat
        }
    }

    /// The render, set so the piece's foot stands just below the square's center (on a board)
    /// or so a king fills the frame (anywhere else).
    private var sprite: some View {
        let name = theme.imageName(for: piece)
        let frame = SpriteFrame.of(name)
        let scale = onBoard ? frame.boardScale : frame.fittedScale
        return Color.clear
            .frame(width: size, height: size)
            .overlay {
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: size * frame.width * scale, height: size * frame.height * scale)
                    .offset(y: size * (onBoard ? frame.boardOffset : frame.fittedOffset))
            }
    }

    @ViewBuilder
    private var flat: some View {
        let glow = piece.color == .white ? theme.whiteGlow : theme.blackGlow
        Image(theme.imageName(for: piece))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .padding(size * 0.04)
            .frame(width: size, height: size)
            .shadow(color: glow?.opacity(0.95) ?? .black.opacity(0.18),
                    radius: glow == nil ? size * 0.02 : size * 0.025,
                    y: glow == nil ? size * 0.02 : 0)
            .shadow(color: glow?.opacity(0.6) ?? .clear, radius: glow == nil ? 0 : size * 0.09)
    }
}

/// Where the piece stands in a sprite picture, so it can be set on its square or fitted into a frame.
/// Lengths are in squares, as rendered (400 pixels to a square).
struct SpriteFrame: Equatable {
    /// The picture's size.
    let width: CGFloat
    let height: CGFloat
    /// How far below the picture's top edge the piece's foot is.
    let foot: CGFloat
    /// On a board: how much larger than the square the piece is drawn, and how far below the
    /// square's center its foot stands.
    let boardScale: CGFloat
    let lift: CGFloat
    /// Off the board, the tallest piece fills the frame: its reach above its foot and below it.
    let reach: CGFloat
    let below: CGFloat

    /// The picture's center on a board, from the square's center.
    var boardOffset: CGFloat { lift - (foot - height / 2) * boardScale }
    /// Fitted into a frame one square tall.
    var fittedScale: CGFloat { 1 / (reach + below) }
    var fittedOffset: CGFloat { -fittedScale * ((foot - height / 2) + (below - reach) / 2) }

    /// The side-on renders (560 x 760, seen from 28 degrees up), where every piece reads by its outline.
    static let sideOn = SpriteFrame(width: 1.4, height: 1.9, foot: 1.5, boardScale: 1.12, lift: 0.22, reach: 1.3, below: 0.2)
    /// The earlier renders (520 x 568, seen from higher up).
    static let fromAbove = SpriteFrame(width: 1.3, height: 1.42, foot: 1.0, boardScale: 1.22, lift: 0.15, reach: 0.964, below: 0.24)

    @MainActor private static var known: [String: SpriteFrame] = [:]

    /// The frame of the named picture, told by its shape: the side-on renders are much taller than wide.
    @MainActor static func of(_ name: String) -> SpriteFrame {
        if let frame = known[name] { return frame }
        let size = UIImage(named: name)?.size ?? .zero
        let frame = size.width > 0 && size.height / size.width > 1.25 ? sideOn : fromAbove
        known[name] = frame
        return frame
    }
}

/// The pre-rendered board picture's squares, set in a glass frame. The picture is
/// turned around when the board is flipped, which keeps the light and dark squares where they belong.
struct BoardArt: View {
    let name: String
    let flipped: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // The picture is 9 squares wide: half a square of frame on each side.
            let inset = side / 18
            ZStack {
                BoardGlass()
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .frame(width: side, height: side)
                    .mask { Rectangle().padding(inset) }
                    // The stone sits in the glass, a little below its surface.
                    .shadow(color: .black.opacity(0.5), radius: side * 0.012, y: side * 0.004)
                // A fine bright line where the glass meets the stone.
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
                    .padding(inset - side * 0.007)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// Clear glass around the board: the app's own glass, as the player lines and the dock use it,
/// only clearer, so the backdrop's light shows through the frame.
struct BoardGlass: View {
    var body: some View {
        GlassSurface(shape: Rectangle(), weight: .clear)
    }
}

/// Lets the player choose what a pawn becomes on the last rank.
struct PromotionPicker: View {
    let color: Piece.Color
    let theme: BoardTheme
    let squareSize: CGFloat
    let choose: (Piece.Kind) -> Void

    private let kinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing: squareSize * 0.15) {
                ForEach(kinds, id: \.self) { kind in
                    Button { choose(kind) } label: {
                        PieceImage(piece: Piece(kind, color: color, square: .a1), theme: theme, size: squareSize)
                            .padding(squareSize * 0.08)
                            .frame(width: squareSize * 1.25, height: squareSize * 1.25)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: squareSize * 0.2, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Promote to \(String(describing: kind))")
                }
            }
        }
        .frame(width: squareSize * 8, height: squareSize * 8)
    }
}

#Preview("Neon") {
    BoardView(match: MatchController(engine: nil, sounds: nil), theme: .neon)
        .padding()
        .background(NeonBackdrop())
}
