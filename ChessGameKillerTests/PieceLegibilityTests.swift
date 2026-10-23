import ChessKit
import UIKit
import XCTest
@testable import ChessGameKiller

/// The flat piece pictures of every look with sprite pieces, held to the v2 sprite contract, and the
/// rook held apart from the pawn. Seen from high above, a rook's battlements are a ring seen from the
/// top: its outline rounds off like a pawn's ball and it reads as a big pawn.
/// scripts/qa/legibility.py measures the same pieces on the composited boards, with pictures.
final class PieceLegibilityTests: XCTestCase {

    // The v2 contract: 560 x 760 px, 400 px to a board square, the foot (where the base meets the
    // board) at x 280, y 600 from the top left.
    static let width = 560
    static let height = 760
    static let footX = 280
    static let footY = 600
    /// Alpha of the solid body. The soft contact shadow stays below it.
    static let solid: UInt8 = 217
    /// Nothing solid this close to the canvas edge, and the shadow faded out by the edge itself.
    static let margin = 4
    static let edgeAlpha: UInt8 = 8
    /// How far the base may sit off x 280 on the foot's row.
    static let footSlack = 6
    // The piece brief's rook: at least 1.25x the pawn's height, its top clearly wider than the pawn's
    // head, and flat: a little below its top it is already nearly as wide as it gets (a tower with
    // battlements), where a rounded top is still narrow. Over the top third of each piece's height.
    static let rookHeight = 1.25
    static let rookTop = 1.25
    static let flatDepth = 0.08
    static let rookFlat = 0.85

    static let pieces: [Piece] = [Piece.Color.white, .black].flatMap { color in
        Piece.Kind.allCases.map { Piece($0, color: color, square: .a1) }
    }

    /// Each sprite set once, with the first look that uses it.
    static var spriteSets: [(prefix: String, theme: BoardTheme)] {
        var sets: [(prefix: String, theme: BoardTheme)] = []
        for theme in BoardTheme.all where theme.spritePieces && !sets.contains(where: { $0.prefix == theme.pieceSet }) {
            sets.append((prefix: theme.pieceSet, theme: theme))
        }
        return sets
    }

    func testEverySpriteFollowsTheV2Contract() throws {
        XCTAssertFalse(Self.spriteSets.isEmpty)
        for (_, theme) in Self.spriteSets {
            for piece in Self.pieces {
                let name = theme.imageName(for: piece)
                let image = try XCTUnwrap(UIImage(named: name)?.cgImage, "\(theme.name) is missing \(name)")
                XCTAssertEqual(image.width, Self.width, "\(name) is not \(Self.width) px wide")
                XCTAssertEqual(image.height, Self.height, "\(name) is not \(Self.height) px tall")
                guard image.width == Self.width, image.height == Self.height else { continue }
                let s = SpriteSilhouette(image)
                XCTAssertFalse(s.solidNearEdge(Self.margin), "\(name) is cut off or touches the canvas edge")
                XCTAssertLessThanOrEqual(s.edgeAlpha, Self.edgeAlpha, "\(name)'s shadow is not faded out by the edge")
                XCTAssertTrue(s.isSolid(Self.footX, Self.footY), "\(name) does not stand on the foot (\(Self.footX), \(Self.footY))")
                if let run = s.run(Self.footY) {
                    XCTAssertEqual(Double(run.lowerBound + run.upperBound) / 2, Double(Self.footX), accuracy: Double(Self.footSlack),
                                   "\(name)'s base is not centred on x \(Self.footX)")
                }
            }
        }
    }

    func testEveryRookIsATowerNotABigPawn() throws {
        for (_, theme) in Self.spriteSets {
            for color in [Piece.Color.white, .black] {
                let rookName = theme.imageName(for: Piece(.rook, color: color, square: .a1))
                let pawnName = theme.imageName(for: Piece(.pawn, color: color, square: .a1))
                let rookImage = try XCTUnwrap(UIImage(named: rookName)?.cgImage, "\(theme.name) is missing \(rookName)")
                let pawnImage = try XCTUnwrap(UIImage(named: pawnName)?.cgImage, "\(theme.name) is missing \(pawnName)")
                let r = try XCTUnwrap(SpriteSilhouette(rookImage).measure(footY: Self.footRow(of: rookImage)), "\(rookName) is empty")
                let p = try XCTUnwrap(SpriteSilhouette(pawnImage).measure(footY: Self.footRow(of: pawnImage)), "\(pawnName) is empty")
                XCTAssertGreaterThanOrEqual(Double(r.height), Double(p.height) * Self.rookHeight,
                                            "\(rookName) is not \(Self.rookHeight)x the pawn's height")
                XCTAssertGreaterThanOrEqual(Double(r.topWidth), Double(p.topWidth) * Self.rookTop,
                                            "\(rookName)'s top is not clearly wider than the pawn's head")
                XCTAssertGreaterThanOrEqual(r.flatness, Self.rookFlat,
                                            "\(rookName)'s top is rounded like a pawn's ball (\(r.flatness)), not a tower's")
            }
        }
    }

    /// The measure itself, on two drawn rooks of the same size: battlements on a straight tower pass,
    /// a domed top on the same tower does not.
    func testTheRookMeasureTellsATowerFromADome() throws {
        let tower = try XCTUnwrap(Self.drawn { context in
            context.fill(CGRect(x: 180, y: 430, width: 200, height: 170))
            for x in [180, 255, 330] {
                context.fill(CGRect(x: x, y: 400, width: 50, height: 31))
            }
            context.fill(CGRect(x: 150, y: 600, width: 260, height: 30))
        })
        let dome = try XCTUnwrap(Self.drawn { context in
            context.fill(CGRect(x: 180, y: 470, width: 200, height: 130))
            context.fillEllipse(in: CGRect(x: 180, y: 400, width: 200, height: 140))
            context.fill(CGRect(x: 150, y: 600, width: 260, height: 30))
        })
        let towerShape = SpriteSilhouette(tower)
        let t = try XCTUnwrap(towerShape.measure(footY: Self.footY))
        let d = try XCTUnwrap(SpriteSilhouette(dome).measure(footY: Self.footY))
        // Read from the top: the battlements start at y 400, 200 px above the foot.
        XCTAssertEqual(t.height, 200)
        XCTAssertEqual(Double(d.height), 200, accuracy: 3)
        XCTAssertEqual(t.topWidth, 200)
        XCTAssertGreaterThanOrEqual(t.flatness, Self.rookFlat)
        XCTAssertLessThan(d.flatness, Self.rookFlat)
        XCTAssertTrue(towerShape.isSolid(Self.footX, Self.footY))
        XCTAssertEqual(towerShape.run(Self.footY), 150...409)
        XCTAssertFalse(towerShape.solidNearEdge(Self.margin))
        XCTAssertEqual(towerShape.edgeAlpha, 0)
    }

    // MARK: Helpers

    /// Where a sprite's foot is. The first sprites (520 x 568) stood on y 400; until they are all
    /// replaced the rook test still reads them right.
    static func footRow(of image: CGImage) -> Int {
        image.width == 520 && image.height == 568 ? 400 : footY
    }

    /// A sprite-sized picture drawn white on clear, with the top left as the origin.
    static func drawn(_ body: (CGContext) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { renderer in
            renderer.cgContext.setFillColor(UIColor.white.cgColor)
            body(renderer.cgContext)
        }.cgImage
    }

    /// The alpha of every pixel, row by row from the top left.
    static func alpha(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}

/// A sprite's alpha, read from the top left, and the measures the tests use.
struct SpriteSilhouette {
    let width: Int
    let height: Int
    let alpha: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        alpha = PieceLegibilityTests.alpha(image)
    }

    func isSolid(_ x: Int, _ y: Int) -> Bool {
        alpha[y * width + x] >= PieceLegibilityTests.solid
    }

    /// From the leftmost to the rightmost solid pixel of a row.
    func run(_ y: Int) -> ClosedRange<Int>? {
        guard let first = (0..<width).first(where: { isSolid($0, y) }),
              let last = (0..<width).last(where: { isSolid($0, y) }) else { return nil }
        return first...last
    }

    func span(_ y: Int) -> Int {
        run(y).map { $0.count } ?? 0
    }

    func solidNearEdge(_ margin: Int) -> Bool {
        for y in 0..<height {
            let columns = (y < margin || y >= height - margin) ? Array(0..<width) : Array(0..<margin) + Array((width - margin)..<width)
            if columns.contains(where: { isSolid($0, y) }) { return true }
        }
        return false
    }

    /// The strongest alpha on the outermost ring of pixels.
    var edgeAlpha: UInt8 {
        var most: UInt8 = 0
        for x in 0..<width {
            most = max(most, alpha[x], alpha[(height - 1) * width + x])
        }
        for y in 0..<height {
            most = max(most, alpha[y * width], alpha[y * width + width - 1])
        }
        return most
    }

    /// The piece's height above the foot, the widest row of its top third, and how wide it already is
    /// a little below its top compared with that (1 for a flat top, much less for a rounded one).
    func measure(footY: Int) -> (height: Int, topWidth: Int, flatness: Double)? {
        guard let top = (0..<height).first(where: { y in span(y) > 0 }), top < footY else { return nil }
        let h = footY - top
        let topWidth = (top..<(top + max(1, h / 3))).map { span($0) }.max() ?? 0
        let below = top + Int((Double(h) * PieceLegibilityTests.flatDepth).rounded())
        return (h, topWidth, topWidth > 0 ? Double(span(below)) / Double(topWidth) : 0)
    }
}
