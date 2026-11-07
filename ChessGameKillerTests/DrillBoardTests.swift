import ChessKit
import SwiftUI
import XCTest
@testable import ChessGameKiller

/// Puzzles on the 3D board: the coach's arrows and squares as the scene draws them, in the
/// flat board's colors, and the board's size beside the flat one.
@MainActor
final class DrillBoardTests: XCTestCase {

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A solid arrow is the flat board's arrow: a shaft from the dot just past the middle of its
    /// square, and a head that stops short of the middle of the target.
    func testASolidArrowIsTheFlatBoardsArrowOnTheStone() throws {
        let outlines = SculptedBoardScene.arrowOutline(from: .a1, to: .a8, dashed: false)
        XCTAssertEqual(outlines.count, 2)
        let shaft = try XCTUnwrap(outlines.first)
        let head = try XCTUnwrap(outlines.last)
        XCTAssertEqual(shaft.count, 4)
        XCTAssertEqual(head.count, 3)
        // a1's middle is (-3.5, -3.5) and a8's (-3.5, 3.5): the tip stops 0.08 short of it.
        let tip = try XCTUnwrap(head.max { $0.y < $1.y })
        XCTAssertEqual(tip.x, -3.5, accuracy: 0.0001)
        XCTAssertEqual(tip.y, 3.42, accuracy: 0.0001)
        // The shaft starts at the dot, 0.3 past a1's middle, and meets the head's base.
        XCTAssertEqual(try XCTUnwrap(shaft.map(\.y).min()), -3.5 + 0.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(shaft.map(\.y).max()), try XCTUnwrap(head.map(\.y).min()), accuracy: 0.0001)
        // The head is 0.54 across, the shaft 0.18, as on the flat board.
        let xs = head.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.max()) - XCTUnwrap(xs.min()), 0.54, accuracy: 0.0001)
        let shaftXs = shaft.map(\.x)
        XCTAssertEqual(try XCTUnwrap(shaftXs.max()) - XCTUnwrap(shaftXs.min()), 0.18, accuracy: 0.0001)
    }

    /// Analysis's arrows are bolder, fade from a lighter blue at the tail to their own at the
    /// tip, and start at a white-ringed dot.
    func testAnalysisArrowsAreBoldAndFadeFromTheirTail() throws {
        let best = SculptedCoachArrow(from: .e2, to: .e4, color: ArrowColors.best, analysis: true)
        XCTAssertGreaterThan(best.proportions.shaft, ArrowOutline.Proportions.coach(dashed: false).shaft)
        XCTAssertGreaterThan(best.proportions.headWidth, ArrowOutline.Proportions.coach(dashed: false).headWidth)
        XCTAssertEqual(ArrowColors.tail(of: ArrowColors.best), ArrowColors.bestTail)
        XCTAssertEqual(ArrowColors.tail(of: ArrowColors.next), ArrowColors.nextTail)
        // Any other color lifts toward white.
        XCTAssertEqual(ArrowColors.tail(of: 0x000000), 0x616161)
        let layers = SculptedBoardScene.arrowLayers(best)
        XCTAssertEqual(layers.stone.count, 2)
        XCTAssertEqual(layers.edge.count, 2)
        XCTAssertEqual(layers.through.count, 2)
        // Along the arrow: 0 at the dot, 1 at the tip.
        let (tail, tip) = ArrowOutline.ends(from: CGPoint(x: 0.5, y: -2.5), to: CGPoint(x: 0.5, y: -0.5), unit: 1,
                                            proportions: best.proportions)
        XCTAssertEqual(tail.y, -2.2, accuracy: 0.0001)
        XCTAssertEqual(ArrowOutline.along(tail, tail: tail, tip: tip), 0)
        XCTAssertEqual(ArrowOutline.along(tip, tail: tail, tip: tip), 1)
    }

    /// Dashed, the shaft is a row of short bars, every one between the tail and the head,
    /// and the head comes last.
    func testADashedArrowIsARowOfBarsAndAHead() throws {
        let outlines = SculptedBoardScene.arrowOutline(from: .g1, to: .g7, dashed: true)
        XCTAssertGreaterThan(outlines.count, 5)
        let head = try XCTUnwrap(outlines.last)
        XCTAssertEqual(head.count, 3)
        let tip = try XCTUnwrap(head.max { $0.y < $1.y })
        XCTAssertEqual(tip.y, 2.5 - 0.08, accuracy: 0.0001)
        let base = 2.42 - 0.44
        for bar in outlines.dropLast() {
            XCTAssertEqual(bar.count, 4)
            for corner in bar {
                XCTAssertEqual(corner.x, 2.5, accuracy: 0.071)
                XCTAssertGreaterThanOrEqual(corner.y, -3.5 + 0.3 - 0.0001)
                XCTAssertLessThanOrEqual(corner.y, base + 0.0001)
            }
        }
    }

    /// A knight's arrow runs straight from its square to the target, as on the flat board.
    func testAKnightsArrowGoesStraightToItsSquare() throws {
        let outline = try XCTUnwrap(SculptedBoardScene.arrowOutline(from: .g1, to: .f3, dashed: false).last)
        let f3 = CGPoint(x: 1.5, y: -1.5)
        let tip = try XCTUnwrap(outline.min { distance($0, f3) < distance($1, f3) })
        XCTAssertEqual(distance(tip, f3), 0.08, accuracy: 0.0001)
    }

    /// The coach's squares and arrows keep the colors the flat board gives them on the look,
    /// yellow squares and green arrows when the drill names none; a square that isn't one is left out.
    func testTheCoachsMarksKeepTheFlatBoardsColors() {
        for look in [BoardTheme.ID.gilded, .midnight] {
            let theme = BoardTheme.named(look)
            let arrows = SculptedTrainingBoard.coachArrows([
                BoardArrow(from: "e2", to: "e4", color: .red, dashed: nil),
                BoardArrow(from: "g1", to: "f3", color: nil, dashed: true),
                BoardArrow(from: "z9", to: "e4", color: .blue, dashed: nil),
            ], theme: theme)
            XCTAssertEqual(arrows, [
                SculptedCoachArrow(from: .e2, to: .e4, color: TrainingColor.red.hex(on: theme)),
                SculptedCoachArrow(from: .g1, to: .f3, color: TrainingColor.green.hex(on: theme), dashed: true),
            ])
            let marks = SculptedTrainingBoard.coachMarks([SquareMark(square: "f7", color: .green), SquareMark(square: "d4", color: nil)],
                                                         theme: theme)
            XCTAssertEqual(marks, [SculptedCoachMark(square: .f7, color: TrainingColor.green.hex(on: theme)),
                                   SculptedCoachMark(square: .d4, color: TrainingColor.yellow.hex(on: theme))])
        }
        // The hex is the flat board's color.
        let theme = BoardTheme.named(.gilded)
        for color in TrainingColor.allCases {
            XCTAssertEqual(Color(hex: color.hex(on: theme)), color.color(on: theme))
        }
    }

    /// The 3D board fits where the flat board was: edge to edge, taking the room the flat board
    /// keeps beside it, never taller than wide, and tilted, shorter than the flat board.
    func testThe3DBoardFitsInTheFlatBoardsPlace() {
        for side: CGFloat in [300, 374, 560] {
            let width = DrillBoard.width3D(side: side)
            XCTAssertEqual(width, side + TrainingBoardView.sideRoom)
            let tilted = DrillBoard.height3D(side: width, framing: .standing)
            XCTAssertLessThan(tilted, side)
            XCTAssertGreaterThan(tilted, side * 0.8)
            let flat = DrillBoard.height3D(side: width, framing: .seated)
            XCTAssertLessThanOrEqual(flat, width)
            XCTAssertGreaterThan(flat, side * 0.95)
        }
    }

    /// A lesson's or a candidate's label on the 3D board sits in the far right corner of its own
    /// square as the camera sees it, tilted and flat, from either side, and inside the picture.
    func testLabelsSitOnTheirOwnSquareOnThe3DBoard() {
        let width = DrillBoard.width3D(side: 374)
        for framing in [SculptedCamera.Framing.standing, .seated] {
            let size = CGSize(width: width, height: DrillBoard.height3D(side: width, framing: framing))
            for flipped in [false, true] {
                let camera = SculptedCamera.fitted(aspect: Float(size.width / size.height), flipped: flipped, framing: framing)
                for square in [Square.a1, .h1, .a8, .h8, .e4, .d5] {
                    let frame = camera.frame(of: square, in: size)
                    let center = SculptedTrainingBoard.labelCenter(in: frame)
                    XCTAssertTrue(frame.contains(center), "\(square.notation) \(framing) flipped \(flipped)")
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(center))
                    XCTAssertGreaterThan(center.x, frame.midX)
                    XCTAssertLessThan(center.y, frame.midY)
                }
            }
        }
    }

    /// Analysis on the 3D board: the best move is a solid arrow and the next best a dashed one,
    /// never more than two, and the pieces go to the scene to be matched, as they have no ids.
    func testAnalysisShowsItsTwoBestMovesOnThe3DBoard() {
        let hints = [
            MoveHint(rank: 0, from: .g8, to: .f6, san: "Nf6", uci: "g8f6", evaluation: .centipawns(30)),
            MoveHint(rank: 1, from: .d7, to: .d6, san: "d6", uci: "d7d6", evaluation: .centipawns(20)),
            MoveHint(rank: 2, from: .c7, to: .c6, san: "c6", uci: "c7c6", evaluation: .centipawns(10)),
        ]
        XCTAssertEqual(SculptedPositionBoard.arrows(hints), [
            SculptedCoachArrow(from: .d7, to: .d6, color: ArrowColors.next, dashed: true, analysis: true),
            SculptedCoachArrow(from: .g8, to: .f6, color: ArrowColors.best, dashed: false, analysis: true),
        ])
        let board = SculptedPositionBoard(pieces: Position.standard.pieces, theme: .named(.gilded), flipped: true,
                                          hints: hints, framing: .seated)
        XCTAssertTrue(board.state.matchesPieces)
        XCTAssertTrue(board.state.flipped)
        XCTAssertEqual(board.state.framing, .seated)
        XCTAssertEqual(board.state.pieces.count, 32)
    }

    /// Every arrow, flat or 3D, gets a white edge: its outline grown evenly all round, so each
    /// side moves out by the edge's width and the tip stays a point just past the arrow's.
    func testAnArrowsEdgeIsItsOutlineGrownAllRound() throws {
        for dashed in [false, true] {
            let outlines = SculptedBoardScene.arrowOutline(from: .b1, to: .b6, dashed: dashed)
            for outline in outlines {
                let grown = ArrowOutline.grown(outline, by: 0.03)
                XCTAssertEqual(grown.count, outline.count)
                let xs = outline.map(\.x), grownXs = grown.map(\.x)
                // Straight up the b-file: each side moves out by the edge, a dash's square corners
                // exactly, the head's sharp corners a little further, short of a spike.
                let right = try XCTUnwrap(grownXs.max()) - XCTUnwrap(xs.max())
                let left = try XCTUnwrap(xs.min()) - XCTUnwrap(grownXs.min())
                for side in [right, left] {
                    if outline.count == 4 { XCTAssertEqual(side, 0.03, accuracy: 0.001) }
                    XCTAssertGreaterThanOrEqual(side, 0.03 - 0.001)
                    XCTAssertLessThan(side, 0.1)
                }
            }
            let head = try XCTUnwrap(outlines.last)
            let tip = try XCTUnwrap(head.max { $0.y < $1.y })
            let grownTip = try XCTUnwrap(ArrowOutline.grown(head, by: 0.03).max { $0.y < $1.y })
            XCTAssertGreaterThan(grownTip.y, tip.y)
            XCTAssertLessThan(grownTip.y, tip.y + 0.12)
        }
        // The flat boards draw the same arrow, in points.
        let flat = ArrowOutline.outlines(from: .zero, to: CGPoint(x: 0, y: 500), unit: 100, dashed: false,
                                         proportions: .coach(dashed: false))
        let inSquares = SculptedBoardScene.arrowOutline(from: .a1, to: .a6, dashed: false)
        XCTAssertEqual(flat.count, inSquares.count)
        XCTAssertEqual(try XCTUnwrap(flat.first).count, try XCTUnwrap(inSquares.first).count)
    }
}
