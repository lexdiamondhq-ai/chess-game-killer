import ChessKit
import SwiftUI

// The board in Talk it through: the position as it stands, still, with the verdict being looked
// at lit on it. Its squares are tinted and its arrows drawn in the verdict's tone: green for good,
// red for danger, and the look's accent for what is only being shown.

/// An arrow between two real squares.
struct TalkPanelBoardArrow: Hashable {
    let from: Square
    let to: Square
    let tone: TalkArrow.Tone
}

/// What the board lights: one verdict's squares and arrows, or only the last move while nothing
/// has been checked.
struct TalkPanelLight: Equatable {
    let squares: [Square: TalkArrow.Tone]
    let arrows: [TalkPanelBoardArrow]
    /// The move that led here, shown faintly while no verdict is lit.
    let lastMove: [Square]

    /// With no check (or one Leo didn't understand), only the last move shows.
    init(check: TalkCheck?, focus: TalkFocus?, lastMove: String?) {
        guard let check, check.understood, let target = TalkPanelLogic.effectiveFocus(focus, in: check) else {
            squares = [:]
            arrows = []
            self.lastMove = Self.moveSquares(lastMove)
            return
        }
        let lit = check.highlights(for: target)
        let fallback: TalkArrow.Tone = TalkPanelLogic.tone(for: target, in: check)
        // Squares that aren't on the board are dropped, and so is an arrow drawn twice.
        var drawn: [TalkPanelBoardArrow] = []
        for arrow in lit.arrows {
            guard let from = TalkPanelLogic.square(arrow.from), let to = TalkPanelLogic.square(arrow.to),
                  from != to else { continue }
            let next = TalkPanelBoardArrow(from: from, to: to, tone: arrow.tone)
            if !drawn.contains(next) {
                drawn.append(next)
            }
        }
        var tinted: [Square: TalkArrow.Tone] = [:]
        for name in lit.squares {
            guard let square = TalkPanelLogic.square(name), tinted[square] == nil else { continue }
            tinted[square] = Self.tone(of: square, arrows: drawn, fallback: fallback)
        }
        squares = tinted
        arrows = drawn
        self.lastMove = []
    }

    /// A square takes the tone of the arrow that points at it, else of the one that leaves it,
    /// else of the verdict's first arrow, so each verdict reads as one picture. With no arrows it
    /// takes the verdict's own tone.
    private static func tone(of square: Square, arrows: [TalkPanelBoardArrow],
                             fallback: TalkArrow.Tone) -> TalkArrow.Tone {
        if let ending = arrows.first(where: { $0.to == square }) { return ending.tone }
        if let leaving = arrows.first(where: { $0.from == square }) { return leaving.tone }
        if let first = arrows.first { return first.tone }
        return fallback
    }

    /// The two squares of a move like "e2e4"; a promotion's letter is ignored.
    private static func moveSquares(_ uci: String?) -> [Square] {
        guard let uci, uci.count >= 4 else { return [] }
        let letters: [Character] = Array(uci)
        let from: Square? = TalkPanelLogic.square(String(letters[0...1]))
        let to: Square? = TalkPanelLogic.square(String(letters[2...3]))
        guard let from, let to else { return [] }
        return [from, to]
    }
}

/// The still board with a verdict lit on it. It only shows; it never takes a tap.
/// It is the same board as everywhere else in the app: the real 3D board, tilted or flat from
/// above with the Tilted / Flat switch under it, when the look has one and 3D pieces are on;
/// otherwise the flat board.
struct TalkPanelBoard: View {
    let fen: String
    let flipped: Bool
    let light: TalkPanelLight
    let theme: BoardTheme
    /// How wide the flat board is, which is as tall. The 3D board takes `TrainingBoardView.sideRoom`
    /// more, edge to edge as in a game.
    let side: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.tilted

    var body: some View {
        if BoardView.playsIn3D(theme, setting: sculpted3D) {
            sculptedBoard
        } else {
            flatBoard
        }
    }

    private var flatBoard: some View {
        PositionBoard(draft: draft, theme: theme, flipped: flipped, tints: tints)
            .overlay { arrowLayer }
            .animation(motion, value: light)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The position")
            .accessibilityAddTraits(.isImage)
            .frame(width: side, height: side)
            .boardHeadroom(theme: theme, side: side)
    }

    /// The verdict's squares and arrows lie on the stone, as the coach's do in lessons and drills.
    private var sculptedBoard: some View {
        let width: CGFloat = DrillBoard.width3D(side: side)
        let framing: SculptedCamera.Framing = tilt.framing
        return VStack(spacing: 6) {
            SculptedPositionBoard(
                pieces: draft.pieces,
                theme: theme,
                flipped: flipped,
                lastMove: stoneLastMove,
                marks: stoneMarks,
                arrows: stoneArrows,
                framing: framing
            )
            .frame(width: width, height: DrillBoard.height3D(side: width, framing: framing))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The position")
            .accessibilityAddTraits(.isImage)
            HStack {
                Spacer(minLength: 0)
                BoardViewSwitch(theme: theme)
            }
            .frame(width: side)
        }
    }

    /// The move that led here, lit as the game lights it, while no verdict is.
    private var stoneLastMove: LastMove? {
        guard light.lastMove.count == 2 else { return nil }
        return LastMove(from: light.lastMove[0], to: light.lastMove[1])
    }

    /// The verdict's squares on the stone, in a steady order.
    private var stoneMarks: [SculptedCoachMark] {
        light.squares
            .map { SculptedCoachMark(square: $0.key, color: Self.hex($0.value, theme: theme)) }
            .sorted { $0.square.notation < $1.square.notation }
    }

    /// The verdict's arrows on the stone: solid, in the verdict's tone.
    private var stoneArrows: [SculptedCoachArrow] {
        light.arrows.map { SculptedCoachArrow(from: $0.from, to: $0.to, color: Self.hex($0.tone, theme: theme)) }
    }

    /// A tone as 0xRRGGBB in the colors the 3D board gives the coach in lessons and drills:
    /// green for good, red for danger, gold for what is only being shown.
    static func hex(_ tone: TalkArrow.Tone, theme: BoardTheme) -> UInt32 {
        switch tone {
        case .good: return TrainingColor.green.hex(on: theme)
        case .bad: return TrainingColor.red.hex(on: theme)
        case .info: return TrainingColor.yellow.hex(on: theme)
        }
    }

    private var draft: PositionDraft {
        PositionDraft(fen: fen) ?? PositionDraft.empty
    }

    private var tints: [Square: Color] {
        var tints: [Square: Color] = [:]
        for square in light.lastMove {
            tints[square] = theme.lastMove
        }
        for (square, tone) in light.squares {
            tints[square] = Self.tint(tone, theme: theme)
        }
        return tints
    }

    /// Strong enough to see on light and dark squares, soft enough that the piece stays clear.
    private static func tint(_ tone: TalkArrow.Tone, theme: BoardTheme) -> Color {
        let color: Color = TalkPanelPalette.tone(tone, theme: theme)
        switch tone {
        case .good, .bad: return color.opacity(0.42)
        case .info: return color.opacity(0.36)
        }
    }

    /// The arrows, laid out exactly as PositionBoard lays out its squares.
    private var arrowLayer: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let inset: CGFloat = theme.frameInset(side: side, coordinates: showsCoordinates)
            let cell: CGFloat = (side - inset * 2) / 8
            ZStack {
                ForEach(light.arrows, id: \.self) { arrow in
                    arrowView(arrow, side: side, inset: inset, cell: cell)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private func arrowView(_ arrow: TalkPanelBoardArrow, side: CGFloat, inset: CGFloat, cell: CGFloat) -> some View {
        let color: Color = TalkPanelPalette.tone(arrow.tone, theme: theme)
        let start: CGPoint = center(of: arrow.from, inset: inset, cell: cell)
        let end: CGPoint = center(of: arrow.to, inset: inset, cell: cell)
        let span: CGFloat = max(side, 1)
        // It grows out of the square it starts on.
        let anchor = UnitPoint(x: start.x / span, y: start.y / span)
        // Neon's arrows glow in their own color; the other looks get a soft shadow.
        let shade: Color = theme.glows ? color.opacity(0.8) : Color.black.opacity(0.4)
        let radius: CGFloat = theme.glows ? cell * 0.14 : cell * 0.05
        let drop: CGFloat = theme.glows ? 0 : cell * 0.03
        return TalkPanelArrowShape(from: start, to: end, cell: cell)
            .fill(color.opacity(0.94))
            .shadow(color: shade, radius: radius, y: drop)
            .transition(arrowTransition(anchor: anchor))
    }

    private func arrowTransition(anchor: UnitPoint) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.88, anchor: anchor))
    }

    /// A square's center inside the board's frame.
    private func center(of square: Square, inset: CGFloat, cell: CGFloat) -> CGPoint {
        let column: Int = flipped ? 7 - square.fileIndex : square.fileIndex
        let row: Int = flipped ? square.rankIndex : 7 - square.rankIndex
        return CGPoint(x: inset + (CGFloat(column) + 0.5) * cell, y: inset + (CGFloat(row) + 0.5) * cell)
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.86)
    }
}

/// One arrow as a single filled outline, so it stays crisp where shaft and head meet: a round
/// tail just off the piece, a slim shaft and a broad head that stops short of the target's center.
private struct TalkPanelArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    /// The side of one square.
    let cell: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx: CGFloat = to.x - from.x
        let dy: CGFloat = to.y - from.y
        let distance: CGFloat = hypot(dx, dy)
        guard distance > 1, cell > 0 else { return path }
        let ux: CGFloat = dx / distance
        let uy: CGFloat = dy / distance
        // A quarter turn from the arrow's direction.
        let nx: CGFloat = -uy
        let ny: CGFloat = ux
        let shaft: CGFloat = cell * 0.08
        let wing: CGFloat = cell * 0.25
        let start = CGPoint(x: from.x + ux * cell * 0.2, y: from.y + uy * cell * 0.2)
        let tip = CGPoint(x: to.x - ux * cell * 0.12, y: to.y - uy * cell * 0.12)
        let length: CGFloat = hypot(tip.x - start.x, tip.y - start.y)
        guard length > 1 else { return path }
        let head: CGFloat = min(cell * 0.42, length * 0.6)
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        // How far the tail's curve reaches back: a cubic this long draws a near-perfect half circle.
        let reach: CGFloat = shaft * 4 / 3

        func side(_ point: CGPoint, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: point.x + nx * offset, y: point.y + ny * offset)
        }

        let tailLeft: CGPoint = side(start, shaft)
        let tailRight: CGPoint = side(start, -shaft)
        path.move(to: tailLeft)
        path.addLine(to: side(base, shaft))
        path.addLine(to: side(base, wing))
        path.addLine(to: tip)
        path.addLine(to: side(base, -wing))
        path.addLine(to: side(base, -shaft))
        path.addLine(to: tailRight)
        path.addCurve(to: tailLeft,
                      control1: CGPoint(x: tailRight.x - ux * reach, y: tailRight.y - uy * reach),
                      control2: CGPoint(x: tailLeft.x - ux * reach, y: tailLeft.y - uy * reach))
        path.closeSubpath()
        return path
    }
}
