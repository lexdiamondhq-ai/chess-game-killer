import ChessKit
import SwiftUI
import XCTest
@testable import ChessGameKiller

/// Puzzles on the 3D board: the coach's arrows and squares as the scene draws them, in the
/// flat board's colors, and the board's size beside the flat one.
@MainActor
final class DrillBoardTests: XCTestCase {

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A coach's solid arrow is the flat board's arrow: a rounded tail just past the middle of its
    /// square, a straight shaft, and a head that stops short of the middle of the target.
    func testASolidArrowIsTheFlatBoardsArrowOnTheStone() throws {
        let outlines = SculptedBoardScene.arrowOutline(from: .a1, to: .a8, dashed: false)
        XCTAssertEqual(outlines.count, 3)
        let tail = outlines[0], shaft = outlines[1]
        let head = try XCTUnwrap(outlines.last)
        XCTAssertGreaterThan(tail.count, 12)
        XCTAssertEqual(shaft.count, 4)
        XCTAssertEqual(head.count, 3)
        // a1's middle is (-3.5, -3.5) and a8's (-3.5, 3.5): the tip stops 0.1 short of it.
        let tip = try XCTUnwrap(head.max { $0.y < $1.y })
        XCTAssertEqual(tip.x, -3.5, accuracy: 0.0001)
        XCTAssertEqual(tip.y, 3.4, accuracy: 0.0001)
        // The shaft starts 0.2 past a1's middle, rounded there, and reaches a hair into the head.
        XCTAssertEqual(try XCTUnwrap(shaft.map(\.y).min()), -3.5 + 0.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(tail.map(\.y).min()), -3.5 + 0.2 - 0.075, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(shaft.map(\.y).max()), try XCTUnwrap(head.map(\.y).min()) + 0.03, accuracy: 0.0001)
        // The head is 0.46 across, the shaft 0.15, as on the flat board.
        let xs = head.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.max()) - XCTUnwrap(xs.min()), 0.46, accuracy: 0.0001)
        let shaftXs = shaft.map(\.x)
        XCTAssertEqual(try XCTUnwrap(shaftXs.max()) - XCTUnwrap(shaftXs.min()), 0.15, accuracy: 0.0001)

        // Seamless, the parts only touch: a half-round tail behind the shaft, the shaft up to the
        // head's base, so a see-through arrow shows no darker overlaps.
        let seamless = SculptedBoardScene.arrowOutline(from: .a1, to: .a8, dashed: false, seamless: true)
        XCTAssertEqual(seamless.count, 3)
        let cap = seamless[0], body = seamless[1], point = seamless[2]
        XCTAssertEqual(try XCTUnwrap(cap.map(\.y).max()), -3.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(cap.map(\.y).min()), -3.375, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(body.map(\.y).min()), -3.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(body.map(\.y).max()), try XCTUnwrap(point.map(\.y).min()), accuracy: 0.0001)
    }

    /// Analysis's arrows are flight paths: they bow to one side and rise off the stone at their
    /// middle, landing back on it at the tip. The best is fuller than the next and lands on a ring.
    func testAnalysisArrowsFlyAndTheBestLandsOnARing() throws {
        let best = SculptedCoachArrow(from: .e2, to: .e4, color: ArrowColors.best, analysis: true)
        let next = SculptedCoachArrow(from: .d2, to: .d4, color: ArrowColors.next, dashed: true, analysis: true,
                                      best: false)
        // The next best is a row of round dots, then its head.
        let dots = SculptedBoardScene.arrowOutline(from: .d2, to: .d4, dashed: true, proportions: next.proportions)
        XCTAssertGreaterThan(dots.count, 4)
        XCTAssertTrue(dots.dropLast().allSatisfy { $0.count == 16 })
        XCTAssertEqual(try XCTUnwrap(dots.last).count, 3)
        XCTAssertGreaterThan(best.proportions.shaft, next.proportions.shaft)
        XCTAssertGreaterThan(best.proportions.headWidth, next.proportions.headWidth)
        XCTAssertEqual(ArrowColors.tail(of: ArrowColors.best), ArrowColors.bestTail)
        XCTAssertEqual(ArrowColors.tail(of: ArrowColors.next), ArrowColors.nextTail)
        // Any other color lifts toward white.
        XCTAssertEqual(ArrowColors.tail(of: 0x000000), 0x616161)

        // e2 to e4 runs straight up the e-file, x 0.5: the shaft bows off it at its middle.
        let outlines = SculptedBoardScene.arrowOutline(from: .e2, to: .e4, dashed: false, proportions: best.proportions)
        XCTAssertEqual(outlines.count, 3)
        let shaft = outlines[1]
        XCTAssertGreaterThan(shaft.count, 20)
        let off = shaft.map { abs($0.x - 0.5) }.max() ?? 0
        XCTAssertGreaterThan(off, 0.1)
        XCTAssertLessThan(off, 0.3)
        // Its ends stay on the file.
        let (tail, tip) = ArrowOutline.ends(from: CGPoint(x: 0.5, y: -2.5), to: CGPoint(x: 0.5, y: -0.5), unit: 1,
                                            proportions: best.proportions)
        XCTAssertEqual(tail.y, -2.26, accuracy: 0.0001)
        XCTAssertEqual(tip.y, -0.58, accuracy: 0.0001)
        XCTAssertEqual(ArrowOutline.along(tail, tail: tail, tip: tip), 0)
        XCTAssertEqual(ArrowOutline.along(tip, tail: tail, tip: tip), 1)
        // It rises most at its middle and touches down at both ends.
        let middle = CGPoint(x: 0.5, y: (tail.y + tip.y) / 2)
        XCTAssertEqual(ArrowOutline.height(of: tail, tail: tail, tip: tip, proportions: best.proportions), 0, accuracy: 0.0001)
        XCTAssertEqual(ArrowOutline.height(of: tip, tail: tail, tip: tip, proportions: best.proportions), 0, accuracy: 0.0001)
        XCTAssertEqual(ArrowOutline.height(of: middle, tail: tail, tip: tip, proportions: best.proportions),
                       best.proportions.rise * (tip.y - tail.y), accuracy: 0.0001)

        // The best lands on a ring; the next has only its shadow under it. A coach's arrow has neither.
        let bestLayers = SculptedBoardScene.arrowLayers(best)
        let nextLayers = SculptedBoardScene.arrowLayers(next)
        XCTAssertEqual(bestLayers.stone.count, 3)
        XCTAssertGreaterThan(bestLayers.ground.count, nextLayers.ground.count)
        XCTAssertEqual(nextLayers.ground.count, 2)
        // They are see-through, with no edge to show through them.
        XCTAssertTrue(bestLayers.edge.isEmpty)
        XCTAssertFalse(SculptedBoardScene.arrowLayers(SculptedCoachArrow(from: .e2, to: .e4, color: 0x2E9E48)).edge.isEmpty)
        XCTAssertTrue(SculptedBoardScene.arrowLayers(SculptedCoachArrow(from: .e2, to: .e4, color: 0x2E9E48)).ground.isEmpty)
    }

    /// Dashed, the shaft is a row of short bars, every one between the tail and the head,
    /// and the head comes last.
    func testADashedArrowIsARowOfBarsAndAHead() throws {
        let outlines = SculptedBoardScene.arrowOutline(from: .g1, to: .g7, dashed: true)
        XCTAssertGreaterThan(outlines.count, 5)
        let head = try XCTUnwrap(outlines.last)
        XCTAssertEqual(head.count, 3)
        let tip = try XCTUnwrap(head.max { $0.y < $1.y })
        XCTAssertEqual(tip.y, 2.5 - 0.1, accuracy: 0.0001)
        let base = 2.4 - 0.4
        for bar in outlines.dropLast() {
            XCTAssertEqual(bar.count, 4)
            for corner in bar {
                XCTAssertEqual(corner.x, 2.5, accuracy: 0.071)
                XCTAssertGreaterThanOrEqual(corner.y, -3.5 + 0.2 - 0.0001)
                XCTAssertLessThanOrEqual(corner.y, base + 0.0001)
            }
        }
    }

    /// A knight's arrow runs straight from its square to the target, as on the flat board.
    func testAKnightsArrowGoesStraightToItsSquare() throws {
        let outline = try XCTUnwrap(SculptedBoardScene.arrowOutline(from: .g1, to: .f3, dashed: false).last)
        let f3 = CGPoint(x: 1.5, y: -1.5)
        let tip = try XCTUnwrap(outline.min { distance($0, f3) < distance($1, f3) })
        XCTAssertEqual(distance(tip, f3), 0.1, accuracy: 0.0001)
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

    /// Analysis on the 3D board: the best move is a fuller arrow and the next best a slimmer one,
    /// never more than two, and the pieces go to the scene to be matched, as they have no ids.
    func testAnalysisShowsItsTwoBestMovesOnThe3DBoard() {
        let hints = [
            MoveHint(rank: 0, from: .g8, to: .f6, san: "Nf6", uci: "g8f6", evaluation: .centipawns(30)),
            MoveHint(rank: 1, from: .d7, to: .d6, san: "d6", uci: "d7d6", evaluation: .centipawns(20)),
            MoveHint(rank: 2, from: .c7, to: .c6, san: "c6", uci: "c7c6", evaluation: .centipawns(10)),
        ]
        XCTAssertEqual(SculptedPositionBoard.arrows(hints), [
            SculptedCoachArrow(from: .d7, to: .d6, color: ArrowColors.next, dashed: true, analysis: true, best: false),
            SculptedCoachArrow(from: .g8, to: .f6, color: ArrowColors.best, analysis: true),
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
