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
    /// Ghost Vision: hold the board to see the engine's line ahead. Nil where it isn't
    /// allowed, such as a game against a friend.
    var vision: GhostVision?

    @AppStorage("haptics") private var hapticsOn = true
    /// The player's army, so veteran pieces show their glow and scar.
    @Environment(ArmyStore.self) private var army: ArmyStore?

    /// The sculpted looks play on a real 3D board unless the player asked for them flat.
    @AppStorage("sculpted3D") private var sculpted3D = true
    /// Bumps a moment after each game the player wins, for the haptic.
    @State private var wins = 0

    private var game: GameModel { match.game }
    private var flipped: Bool { match.isBoardFlipped }

    var body: some View {
        Group {
            if Self.playsIn3D(theme, setting: sculpted3D) {
                SculptedBoardView(match: match, theme: theme, browsing: browsing, endBrowsing: endBrowsing, vision: vision)
            } else {
                flatBoard
            }
        }
        .modifier(GhostVisionGesture(vision: vision, match: match, enabled: browsing == nil))
        .overlay(alignment: .top) { ghostStrip }
    }

    /// The line's moves, just above the board while Ghost Vision is up.
    @ViewBuilder private var ghostStrip: some View {
        if let vision, vision.isHolding {
            GhostStrip(line: match.ghostLine, focus: vision.focus, theme: theme)
                .alignmentGuide(.top) { dimensions in dimensions[.bottom] + 8 }
                .transition(.opacity)
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
            flatBoard(side: min(geo.size.width, geo.size.height))
        }
        .aspectRatio(1, contentMode: .fit)
        // One tap as each move lands: firmer for a capture, a sharp knock for a check against the player.
        .sensoryFeedback(trigger: game.moveCount) { _, _ in
            hapticsOn ? MoveFeel(of: game).feedback(heavy: false) : nil
        }
        .sensoryFeedback(.selection, trigger: game.selected) { _, new in hapticsOn && new != nil }
        .sensoryFeedback(.success, trigger: wins) { _, _ in hapticsOn }
        .onChange(of: match.winner) { _, winner in
            guard let winner, game.humanColors.contains(winner) else { return }
            // A moment after the end, once the player has seen it.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                wins += 1
            }
        }
    }

    // The flat board is built from small typed pieces: one long SwiftUI expression here is
    // too slow for the newer Swift type checker, which then gives up.

    private func flatBoard(side: CGFloat) -> some View {
        let inset: CGFloat = theme.frameInset(side: side)
        let sq: CGFloat = (side - inset * 2) / 8
        let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
        return ZStack(alignment: .topLeading) {
            // Only the board itself is cut to its rounded corners: a tall piece on the far
            // rank may rise a little above the frame, as it would on a real board.
            boardSurface
                .frame(width: side, height: side)
                .clipShape(corner)
            boardContent(size: sq)
                .frame(width: sq * 8, height: sq * 8)
                .padding(inset)
            if theme.boardArt != nil {
                FrameCoordinates(flipped: flipped, inset: inset, squareSize: sq, color: theme.labelOnDark)
            }
        }
        .frame(width: side, height: side)
        .overlay { boardEdge(corner) }
        // Falling pieces sit outside the clip, so one on the edge can fall past it.
        .overlay(alignment: .topLeading) { captures(size: sq).padding(inset) }
        .background { boardGlow(corner, size: sq) }
    }

    @ViewBuilder private var boardSurface: some View {
        ZStack {
            if let art = theme.boardArt {
                BoardArt(name: art, flipped: flipped)
            }
            if let surface = theme.surface {
                LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private func boardContent(size sq: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            squares(size: sq)
            pieces(size: sq)
            if theme.spritePieces {
                dotsOverPieces(size: sq)
            }
            ghostLayer(size: sq)
            checkCallout(size: sq)
            // A flag that falls mid-promotion puts the pawn back; this just makes sure
            // the picker never outlives the game.
            if let promotion = game.pendingPromotion, !match.isOver {
                promotionPicker(color: promotion.piece.color, size: sq)
            }
        }
    }

    /// Ghost Vision's see-through pieces, while the player holds the board.
    @ViewBuilder private func ghostLayer(size sq: CGFloat) -> some View {
        if let vision, vision.isHolding, let line = match.ghostLine {
            GhostLayer(line: line, focus: vision.shownFocus(steps: line.steps.count), theme: theme, size: sq,
                       center: { (square: Square) -> CGPoint in center(of: square, size: sq) })
        }
    }

    private func checkCallout(size sq: CGFloat) -> some View {
        CheckCalloutLayer(game: game, color: calloutColor, anchor: { (square: Square) -> CGPoint in
            calloutPoint(over: square, size: sq)
        })
        // Each game starts with a fresh layer: the move count runs on across games.
        .id(match.gameNumber)
        .frame(width: sq * 8, height: sq * 8)
    }

    private func promotionPicker(color: Piece.Color, size sq: CGFloat) -> some View {
        PromotionPicker(
            color: color, theme: theme, squareSize: sq,
            cancel: { withAnimation(.snappy(duration: 0.2)) { match.cancelPromotion() } },
            choose: { (kind: Piece.Kind) in
                withAnimation(.snappy(duration: 0.2)) { match.promote(to: kind) }
            }
        )
        .transition(.opacity)
    }

    @ViewBuilder private func boardEdge(_ corner: RoundedRectangle) -> some View {
        if let edge = theme.boardEdge {
            corner.strokeBorder(edge, lineWidth: 1)
        }
    }

    /// Soft shadow or colored glow (Neon) around the board.
    private func boardGlow(_ corner: RoundedRectangle, size sq: CGFloat) -> some View {
        let dark: Bool = theme.isDark
        return ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { (index: Int, color: Color) in
            let blur: CGFloat = dark ? sq * (0.3 + 0.35 * CGFloat(index)) : sq * 0.25
            corner.fill(color)
                .blur(radius: blur)
                .offset(y: dark ? 0 : sq * 0.08)
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
        BoardTapResolver.center(of: square, squareSize: size, flipped: flipped)
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
        // One tap for the whole board, read where the finger landed: a tall piece's head
        // is drawn over the square behind it.
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            if vision?.swallowsTap == true { return }
            guard let tapped = tappedSquare(at: value.location, size: size) else { return }
            withAnimation(.snappy(duration: 0.22)) { match.tap(tapped) }
        })
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
                HintBrackets(color: theme.hint, size: size,
                             skipTopLeading: theme.boardArt == nil && column == 0,
                             skipBottomTrailing: theme.boardArt == nil && row == 7)
                    .opacity(isBest ? 1 : 0.5)
            }

            // Coordinates in the corners, like a printed board. A board picture has them in its frame.
            if theme.boardArt == nil {
                if column == 0 {
                    coordinate("\(square.rankIndex + 1)", size: size, color: labelColor, alignment: .topLeading)
                }
                if row == 7 {
                    coordinate(square.file.rawValue, size: size, color: labelColor, alignment: .bottomTrailing)
                }
            }

            // Where the selected piece can go: a dot on empty squares, corner wedges on captures.
            if isTarget {
                MoveDot(occupied: occupant != nil, hint: hintedTarget, color: theme.hint, glow: theme.hintGlow, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(square, occupant: occupant, isTarget: isTarget, hinted: hintedTarget))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            withAnimation(.snappy(duration: 0.22)) { match.tap(square) }
        }
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

    /// The square a tap on the squares means: see `BoardTapResolver`.
    private func tappedSquare(at point: CGPoint, size: CGFloat) -> Square? {
        var isSolid: ((Piece, CGPoint) -> Bool)?
        if theme.spritePieces {
            let theme = theme
            isSolid = { piece, offset in SpriteMasks.shared.isSolid(piece, in: theme, at: offset) }
        }
        return BoardTapResolver.square(
            at: point, squareSize: size, flipped: flipped,
            selected: game.selected, targets: game.targets,
            piece: { game.piece(at: $0) }, isSolid: isSolid
        )
    }

    // MARK: Pieces

    /// Pieces sit in their own layer so they can slide between squares.
    private func pieces(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.pieces) { placed in
                let place = cell(of: placed.square)
                PieceImage(piece: placed.piece, theme: theme, size: size, onBoard: true)
                    .modifier(VeteranAura(rank: armyRank(of: placed), piece: placed.piece, theme: theme, size: size))
                    .scaleEffect(game.selected == placed.square ? PieceImage.liftedScale : 1)
                    .position(center(of: placed.square, size: size))
                    // Nearer rows draw last, so tall 3D pieces overlap the ones behind them, and
                    // left to right within a row, so each soft shadow falls on the board, not on a piece.
                    .zIndex(Double(place.row) * 8 + Double(place.column))
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

    /// The move dots again, faintly over the pieces, so a dot behind a tall piece's head
    /// still shows through it.
    private func dotsOverPieces(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(game.targets), id: \.self) { target in
                MoveDot(occupied: game.piece(at: target) != nil, hint: hintedTargets[target], color: theme.hint, size: size)
                    .frame(width: size, height: size)
                    .position(center(of: target, size: size))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .opacity(0.4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Army

    private func armyRank(of placed: PlacedPiece) -> ArmyRank {
        guard let army, let slot = army.slot(of: placed, in: match) else { return .recruit }
        return army.record(for: slot).rank
    }

    // MARK: Check

    /// The callout's color: the check's red, or the look's own accent when the player gave mate.
    private var calloutColor: Color {
        if game.isCheckmate, let winner = game.winner, game.humanColors.contains(winner) {
            return theme.accent ?? theme.hint
        }
        return theme.check
    }

    /// Where the check callout floats: just over the king's head, or under its foot on the top row.
    private func calloutPoint(over square: Square, size: CGFloat) -> CGPoint {
        let middle = center(of: square, size: size)
        if cell(of: square).row == 0 {
            return CGPoint(x: middle.x, y: middle.y + size * 0.85)
        }
        // The callout is about 24 points tall: its middle sits 15 points over the head.
        return CGPoint(x: middle.x, y: pieceTop(on: square, size: size) - 15)
    }

    /// The top of the piece standing on a square: measured from its picture on the 3D sprites,
    /// the square's top edge for the flat pieces, which stay inside their squares.
    private func pieceTop(on square: Square, size: CGFloat) -> CGFloat {
        let middle = center(of: square, size: size)
        guard theme.spritePieces, let piece = game.piece(at: square),
              let top = SpriteMasks.shared.mask(named: theme.imageName(for: piece))?.top
        else { return middle.y - size * 0.5 }
        let rect = PieceImage.boardRect(of: theme.imageName(for: piece), squareSize: size)
        let scale = game.selected == square ? PieceImage.liftedScale : 1
        return middle.y + (rect.minY + top * rect.height) * scale
    }

    // MARK: Captures

    /// Each taken piece falls where it stood, away from the piece that took it.
    private func captures(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(game.captureEvents) { event in
                CaptureFall(piece: event.piece, theme: theme, size: size, seed: event.id,
                            away: CaptureFall.direction(of: event, flipped: flipped))
                    .position(center(of: event.piece.square, size: size))
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// How a move feels in the hand: one tap as it lands, firmer for a capture, a sharp knock
/// for a check against the player, and on the 3D board a heavy thud as a rook or queen falls.
enum MoveFeel: Equatable {
    case quiet, capture, bigCapture, check

    /// The move just played in `game`.
    init(of game: GameModel) {
        if game.personInCheck != nil {
            self = .check
        } else if game.lastPlayed?.isCapture == true {
            let taken = game.captureEvents.last?.piece.kind
            self = taken == .queen || taken == .rook ? .bigCapture : .capture
        } else {
            self = .quiet
        }
    }

    /// `heavy` on the 3D board, where a big capture shakes the board; flat, it is like any capture.
    func feedback(heavy: Bool) -> SensoryFeedback {
        switch self {
        case .quiet: return .impact(weight: .light)
        case .capture: return .impact(weight: .medium)
        case .bigCapture: return heavy ? .impact(weight: .heavy) : .impact(weight: .medium)
        case .check: return .impact(flexibility: .rigid, intensity: 0.8)
        }
    }
}

/// Centers its one child over a point, shifted inward as far as needed to keep
/// the whole child within the bounds. A child wider than the bounds is centered.
struct NameTagPlacement: Layout {
    var x: CGFloat
    var y: CGFloat

    private static let margin: CGFloat = 2

    /// The point animates, so the child slides when it moves to another square.
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

/// Where the selected piece can go: a dot on an empty square, and four wedges in the
/// corners of a square with a piece it can take, which that piece never covers. The coach's
/// pick gets a halo ring and its capture a soft wash (fainter for the runner-up), so it
/// stands out without an arrow across the board. A thin dark rim keeps every mark clear
/// on light squares.
struct MoveDot: View {
    let occupied: Bool
    /// Nil for an ordinary move; true for the coach's best move, false for its second choice.
    var hint: Bool? = nil
    let color: Color
    var glow: Color? = nil
    let size: CGFloat

    private static let rim = Color.black.opacity(0.32)

    var body: some View {
        let rim = max(1, size * 0.03)
        ZStack {
            if occupied {
                if let hint {
                    Circle().fill(color.opacity(hint ? 0.24 : 0.14)).padding(size * 0.08)
                }
                let leg = size * (hint == nil ? 0.22 : 0.26)
                // The rim runs along each wedge's long side; the others lie on the square's edges.
                CaptureCorners(leg: leg, band: rim * 1.414).fill(Self.rim)
                CaptureCorners(leg: leg).fill(color)
            } else {
                if let hint {
                    let line = size * (hint ? 0.05 : 0.04)
                    let halo = size * 0.66
                    Circle().strokeBorder(Self.rim, lineWidth: rim)
                        .frame(width: halo + rim * 2, height: halo + rim * 2)
                    Circle().strokeBorder(color.opacity(hint ? 1 : 0.55), lineWidth: line)
                        .frame(width: halo, height: halo)
                    Circle().strokeBorder(Self.rim, lineWidth: rim)
                        .frame(width: halo - line * 2, height: halo - line * 2)
                }
                let dot = size * 0.3
                Circle().strokeBorder(Self.rim, lineWidth: rim)
                    .frame(width: dot + rim * 2, height: dot + rim * 2)
                Circle().fill(color).frame(width: dot, height: dot)
            }
        }
        .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : size * 0.1)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .accessibilityHidden(true)
    }
}

/// Four right triangles in a square's corners, their two short sides `leg` long along the
/// square's edges. With `band`, only the strip along each long side, from `leg` out to
/// `leg + band` (measured along the edges): the dark rim drawn under the wedges.
struct CaptureCorners: Shape {
    var leg: CGFloat
    var band: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inner = band > 0 ? leg : 0
        let outer = band > 0 ? leg + band : leg
        let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
            (rect.maxX, rect.maxY, -1, -1), (rect.minX, rect.maxY, 1, -1),
        ]
        var path = Path()
        for corner in corners {
            path.move(to: CGPoint(x: corner.x + inner * corner.dx, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x + outer * corner.dx, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + outer * corner.dy))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + inner * corner.dy))
            path.closeSubpath()
        }
        return path
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
/// Lessons and drills use it too. Every frame is worked out from the time since it began,
/// so a board still settling its layout never drags the fall along.
struct CaptureFall: View {
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat
    /// Picks the side it falls to when `away` doesn't say.
    let seed: Int
    /// Which way it falls on screen: 1 to the right, -1 to the left.
    var away: CGFloat? = nil
    /// Holds the fall this many seconds in, for pictures of it; nil plays it.
    var frozenAt: TimeInterval? = nil

    @State private var start = Date()
    /// Set once the fall is over, so the timeline rests.
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the foot meets the square, as a fraction of the square: the renders stand
    /// a little below the middle, as their picture's frame says, the flat pieces at the bottom.
    private var footY: CGFloat {
        theme.spritePieces ? 0.5 + SpriteFrame.of(theme.imageName(for: piece)).lift : 0.9
    }

    var body: some View {
        if let frozenAt {
            pose(at: frozenAt)
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: done)) { timeline in
                pose(at: timeline.date.timeIntervalSince(start))
            }
            .task {
                // The dust has settled 0.76 s in.
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.76))
                done = true
            }
        }
    }

    /// Which way a taken piece falls on screen: away from the side the capture came from.
    /// Nil for a capture straight up or down the board.
    static func direction(of event: CaptureEvent, flipped: Bool) -> CGFloat? {
        guard let from = event.from else { return nil }
        let dx = event.piece.square.fileIndex - from.fileIndex
        guard dx != 0 else { return nil }
        return (dx > 0) != flipped ? 1 : -1
    }

    /// The fall `t` seconds in. It tips over for 0.26 s, slow at first, and hits the board at
    /// 0.19 s, where it slides a touch, shrinks and fades for 0.26 s. With Reduce Motion it
    /// only fades, for 0.2 s.
    private func pose(at t: TimeInterval) -> some View {
        let turn = away ?? (seed % 2 == 0 ? 1 : -1)
        // The far edge of the foot, which the piece pivots on as it goes over.
        let pivot = UnitPoint(x: 0.5 + 0.2 * turn, y: footY)
        let motion = !reduceMotion
        let tip = motion ? Self.progress(.easeIn, t, from: 0, length: 0.26) : 0
        let gone = Self.progress(.easeOut, t, from: motion ? 0.19 : 0, length: motion ? 0.26 : 0.2)
        return ZStack {
            if motion {
                dust(at: t)
            }
            PieceImage(piece: piece, theme: theme, size: size, onBoard: true)
                .rotationEffect(.degrees(Double(80 * turn * tip)), anchor: pivot)
                .offset(x: motion ? turn * size * 0.12 * gone : 0)
                .scaleEffect(motion ? 1 - 0.14 * gone : 1, anchor: pivot)
                .opacity(Double(1 - gone))
        }
        .frame(width: size * 3, height: size * 3)
    }

    /// A soft ring of dust on the board around the foot, seen at the same slant as the pieces.
    /// It rises in 0.07 s as the piece hits the board, then spreads and fades for 0.5 s.
    /// A rook or a queen lands harder.
    private func dust(at t: TimeInterval) -> some View {
        let heavy = piece.kind == .queen || piece.kind == .rook
        let spread: CGFloat = heavy ? 2.1 : 1.7
        let peak: CGFloat = heavy ? 0.75 : 0.55
        let rise: CGFloat = Self.progress(.easeOut, t, from: 0.19, length: 0.07)
        let settle: CGFloat = Self.progress(.easeOut, t, from: 0.26, length: 0.5)
        // Worked out one by one: as a single expression this took the type checker seconds.
        let line: CGFloat = size * (0.06 - 0.045 * settle)
        let scale: CGFloat = 0.75 + (spread - 0.75) * settle
        let fade: Double = Double(peak * rise * (1 - settle))
        let drop: CGFloat = size * (footY - 0.5)
        return Ellipse()
            .strokeBorder(Color.white.opacity(0.55), lineWidth: line)
            .frame(width: size * 0.8, height: size * 0.34)
            .scaleEffect(scale)
            .opacity(fade)
            .blur(radius: size * 0.02)
            .offset(y: drop)
    }

    /// How far along a step `length` seconds long, starting `start` seconds in, is at `t`, eased.
    private static func progress(_ curve: UnitCurve, _ t: TimeInterval, from start: TimeInterval,
                                 length: TimeInterval) -> CGFloat {
        CGFloat(curve.value(at: min(max((t - start) / length, 0), 1)))
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

    /// How much larger a picked-up piece is drawn, about its square's center.
    static let liftedScale: CGFloat = 1.08

    /// Where the named sprite picture stands on the board, relative to its square's center, for a
    /// square `squareSize` wide: as `sprite` draws it. The taps and the check callout take it from here.
    static func boardRect(of name: String, squareSize size: CGFloat) -> CGRect {
        boardRect(SpriteFrame.of(name), squareSize: size)
    }

    /// Where a picture with this frame stands on the board, relative to its square's center.
    static func boardRect(_ frame: SpriteFrame, squareSize size: CGFloat) -> CGRect {
        let width = size * frame.width * frame.boardScale
        let height = size * frame.height * frame.boardScale
        return CGRect(x: -width / 2, y: size * frame.boardOffset - height / 2, width: width, height: height)
    }

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
                    .lightPieceEdge(onBoard && piece.color == .white, size: size)
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

private extension View {
    /// On a board, a fine dark edge around a light piece keeps its outline crisp on the light squares,
    /// where ivory on cream would otherwise melt in. About half a point on a phone.
    @ViewBuilder
    func lightPieceEdge(_ on: Bool, size: CGFloat) -> some View {
        if on {
            shadow(color: .black.opacity(0.8), radius: size * 0.014)
        } else {
            self
        }
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
    /// How far the tallest piece on the far rank rises above the board's outer edge: its square's
    /// center is a square below that edge (half a square, then the frame's half square).
    var boardRise: CGFloat { max(0, reach * boardScale - lift - 1) }
    /// Fitted into a frame one square tall.
    var fittedScale: CGFloat { 1 / (reach + below) }
    var fittedOffset: CGFloat { -fittedScale * ((foot - height / 2) + (below - reach) / 2) }

    /// The side-on renders (560 x 760, seen from 28 degrees up), where every piece reads by its outline.
    /// Every set's king, cross included, stays within 1.2 squares above its foot and 0.15 below it.
    static let sideOn = SpriteFrame(width: 1.4, height: 1.9, foot: 1.5, boardScale: 1.2, lift: 0.24, reach: 1.2, below: 0.15)
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

/// Files along the bottom and ranks up the left side, printed in the glass frame around a
/// board picture, as on the 3D board, so no piece or shadow ever sits on them.
struct FrameCoordinates: View {
    let flipped: Bool
    /// The frame's width on each side.
    let inset: CGFloat
    let squareSize: CGFloat
    let color: Color

    private static let files = Array("abcdefgh")

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<8, id: \.self) { index in
                // Column `index` from the left, row `index` from the top.
                Text(String(Self.files[flipped ? 7 - index : index]))
                    .position(x: inset + (CGFloat(index) + 0.5) * squareSize, y: inset * 1.5 + squareSize * 8)
                Text("\(flipped ? index + 1 : 8 - index)")
                    .position(x: inset / 2, y: inset + (CGFloat(index) + 0.5) * squareSize)
            }
        }
        .font(.system(size: inset * 0.5, weight: .semibold, design: .themed))
        .foregroundStyle(color)
        .frame(width: inset * 2 + squareSize * 8, height: inset * 2 + squareSize * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lets the player choose what a pawn becomes on the last rank, over a dim backdrop that
/// fills the board. Tapping the backdrop is a change of mind: `cancel` puts the pawn back.
struct PromotionPicker: View {
    let color: Piece.Color
    let theme: BoardTheme
    let squareSize: CGFloat
    var cancel: (() -> Void)? = nil
    let choose: (Piece.Kind) -> Void

    private let kinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { cancel?() }
                .accessibilityElement()
                .accessibilityLabel("Cancel")
                .accessibilityHint("Puts the pawn back")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { cancel?() }
                .accessibilityHidden(cancel == nil)
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
                    .accessibilityAction(.escape) { cancel?() }
                }
            }
            // A tap between two pieces is a near miss, not a change of mind.
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Neon") {
    BoardView(match: MatchController(engine: nil, sounds: nil), theme: .neon)
        .padding()
        .background(NeonBackdrop())
}
