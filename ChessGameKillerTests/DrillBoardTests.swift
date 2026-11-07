import ChessKit
import SwiftUI
import XCTest
@testable import ChessGameKiller

/// Puzzles on the 3D board: the coach's arrows and squares as the scene draws them, in the
/// flat board's colors, and the board's size beside the flat one.
@MainActor
final class DrillBoardTests: XCTestCase {

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A solid arrow is one outline, the flat board's arrow: from just past the middle of its
    /// square, round at the tail, to a point short of the middle of the target.
    func testASolidArrowIsTheFlatBoardsArrowOnTheStone() throws {
        let outlines = SculptedBoardScene.arrowOutline(from: .a1, to: .a8, dashed: false)
        XCTAssertEqual(outlines.count, 1)
        let outline = try XCTUnwrap(outlines.first)
        // a1's middle is (-3.5, -3.5) and a8's (-3.5, 3.5): the tip stops 0.1 short of it.
        let tip = try XCTUnwrap(outline.max { $0.y < $1.y })
        XCTAssertEqual(tip.x, -3.5, accuracy: 0.0001)
        XCTAssertEqual(tip.y, 3.4, accuracy: 0.0001)
        // The round tail reaches back to 0.2 past a1's middle, less half the shaft.
        let back = try XCTUnwrap(outline.min { $0.y < $1.y })
        XCTAssertEqual(back.y, -3.5 + 0.2 - 0.075, accuracy: 0.0001)
        // The head is 0.46 across, the shaft 0.15, as on the flat board.
        let xs = outline.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.max()) - XCTUnwrap(xs.min()), 0.46, accuracy: 0.0001)
        let shaft = outline.filter { $0.y < -3 }.map(\.x)
        XCTAssertEqual(try XCTUnwrap(shaft.max()) - XCTUnwrap(shaft.min()), 0.15, accuracy: 0.0001)
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
                XCTAssertEqual(corner.x, 2.5, accuracy: 0.061)
                XCTAssertGreaterThanOrEqual(corner.y, -3.5 + 0.2 - 0.0001)
                XCTAssertLessThanOrEqual(corner.y, base + 0.0001)
            }
        }
    }

    /// A knight's arrow runs straight from its square to the target, as on the flat board.
    func testAKnightsArrowGoesStraightToItsSquare() throws {
        let outline = try XCTUnwrap(SculptedBoardScene.arrowOutline(from: .g1, to: .f3, dashed: false).first)
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

    /// Analysis on the 3D board: the best move is the lit arrow and the next best a plain one,
    /// never more than two, and the pieces go to the scene to be matched, as they have no ids.
    func testAnalysisShowsItsTwoBestMovesOnThe3DBoard() {
        let hints = [
            MoveHint(rank: 0, from: .g8, to: .f6, san: "Nf6", uci: "g8f6", evaluation: .centipawns(30)),
            MoveHint(rank: 1, from: .d7, to: .d6, san: "d6", uci: "d7d6", evaluation: .centipawns(20)),
            MoveHint(rank: 2, from: .c7, to: .c6, san: "c6", uci: "c7c6", evaluation: .centipawns(10)),
        ]
        XCTAssertEqual(SculptedPositionBoard.sceneHints(hints), [
            SculptedHint(from: .g8, to: .f6, isBest: true),
            SculptedHint(from: .d7, to: .d6, isBest: false),
        ])
        let board = SculptedPositionBoard(pieces: Position.standard.pieces, theme: .named(.gilded), flipped: true,
                                          hints: hints, framing: .seated)
        XCTAssertTrue(board.state.matchesPieces)
        XCTAssertTrue(board.state.flipped)
        XCTAssertEqual(board.state.framing, .seated)
        XCTAssertEqual(board.state.pieces.count, 32)
    }
}
