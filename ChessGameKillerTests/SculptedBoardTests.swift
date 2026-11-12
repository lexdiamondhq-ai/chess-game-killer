import ChessKit
import SceneKit
import UIKit
import XCTest
@testable import ChessGameKiller

/// The 3D board's models, camera and taps.
@MainActor
final class SculptedBoardTests: XCTestCase {

    func testAllSixPiecesLoad() {
        let assets = SculptedAssets.shared
        XCTAssertTrue(assets.isLoaded)
        for kind in Piece.Kind.allCases {
            let parts = assets.parts[kind] ?? []
            XCTAssertTrue(parts.contains { $0.finish == .body }, "\(kind) has no body")
            XCTAssertTrue(parts.contains { $0.finish == .metal }, "\(kind) has no platinum ring")
            for part in parts {
                XCTAssertGreaterThan(part.geometry.sources.first?.vectorCount ?? 0, 100)
            }
        }
        XCTAssertTrue(assets.parts[.king]?.contains { $0.finish == .gem } ?? false, "the king lost its sapphires")
        XCTAssertTrue(assets.parts[.queen]?.contains { $0.finish == .pearl } ?? false, "the queen lost her pearls")
    }

    /// The gilded set: six pieces with gold on every one, amber in the king's cross and the
    /// knight's eyes, standing at the same heights as the classic set.
    func testTheGildedSetLoads() {
        let assets = SculptedAssets.shared
        let gilded = assets.parts(for: .gilded)
        XCTAssertEqual(gilded.count, 6)
        for kind in Piece.Kind.allCases {
            let parts = gilded[kind] ?? []
            XCTAssertTrue(parts.contains { $0.finish == .body }, "\(kind) has no body")
            XCTAssertTrue(parts.contains { $0.finish == .metal }, "\(kind) has no gold")
            for part in parts {
                XCTAssertGreaterThan(part.geometry.sources.first?.vectorCount ?? 0, 100)
            }
            let height = parts.map { Float($0.geometry.boundingBox.max.y) }.max() ?? 0
            XCTAssertEqual(height, assets.height(of: kind), accuracy: 0.03, "\(kind) changed height")
        }
        XCTAssertTrue(gilded[.king]?.contains { $0.finish == .gem } ?? false, "the king lost its amber")
        XCTAssertTrue(gilded[.knight]?.contains { $0.finish == .gem } ?? false, "the knight lost its eyes")
        XCTAssertTrue(assets.parts[.knight]?.contains { $0.finish == .gem } ?? false, "the classic knight lost its eyes")
        // Loaded once, then shared.
        XCTAssertTrue(assets.parts(for: .gilded)[.knight]?.first?.geometry === gilded[.knight]?.first?.geometry)
        // Looks with the classic set get the classic meshes; Portoro shares the gilded ones.
        XCTAssertTrue(assets.parts(for: .noir)[.knight]?.first?.geometry === assets.parts[.knight]?.first?.geometry)
        XCTAssertTrue(assets.parts(for: .portoro)[.knight]?.first?.geometry === gilded[.knight]?.first?.geometry)
    }

    /// The ivory pieces once washed out on the light squares: the two were nearly the same tone.
    /// On every 3D look the ivory must stay well brighter than the light squares it stands on, and
    /// where the squares come near its tone, keep a darker outline.
    func testTheIvoryStandsOutOnTheLightSquares() throws {
        for look in SculptedLook.all {
            let squares = try XCTUnwrap(UIImage(named: look.squares)?.cgImage, "\(look.name) is missing \(look.squares)")
            let light = Self.lightSquareLuminance(squares)
            let ivory = Self.luminance(look.ivory)
            XCTAssertGreaterThan(ivory, light * 1.3, "\(look.name): the ivory would wash out on the light squares")
            if ivory < light * 2 {
                XCTAssertGreaterThan(look.ivoryEdge, 0, "\(look.name): the ivory lost its outline")
            }
        }
    }

    /// The same with the 3D pieces off, and on every small board: each look's piece pictures on its
    /// board picture. The white pieces washed out there too, on Midnight from Black's side, a little
    /// darker than the cream squares. White pieces must stand brighter than the light squares, or,
    /// like Fabergé's gold on white enamel, far darker.
    func testTheFlatWhitePiecesStandOutOnTheLightSquares() throws {
        for theme in BoardTheme.all {
            guard let name = theme.boardArt else { continue }
            let art = try XCTUnwrap(UIImage(named: name)?.cgImage, "\(theme.name) is missing \(name)")
            // The picture is nine squares wide: the board, in a frame half a square wide.
            let inset = CGFloat(art.width) / 18
            let board = try XCTUnwrap(art.cropping(to: CGRect(x: inset, y: inset, width: CGFloat(art.width) - inset * 2,
                                                              height: CGFloat(art.height) - inset * 2)))
            let light = Self.lightSquareLuminance(board)
            var total = 0.0
            for kind in Piece.Kind.allCases {
                let sprite = theme.imageName(for: Piece(kind, color: .white, square: .a1))
                let image = try XCTUnwrap(UIImage(named: sprite)?.cgImage, "\(theme.name) is missing \(sprite)")
                total += Self.opaqueLuminance(image)
            }
            let ratio = total / Double(Piece.Kind.allCases.count) / light
            XCTAssertTrue(ratio > 1.05 || ratio < 0.5, "\(theme.name): the white pieces would wash out on the light squares (\(ratio))")
        }
    }

    /// SceneKit draws only the front of each triangle, so a solid wound inside out shows its far
    /// side through itself: the knights once looked hollow, their base ring showing through the neck.
    /// Every solid of every part must enclose a positive volume.
    func testEveryPartFacesOutward() {
        let assets = SculptedAssets.shared
        for (name, set) in [("classic", assets.parts), ("gilded", assets.parts(for: .gilded))] {
            for (kind, parts) in set {
                for part in parts {
                    let volumes = Self.solidVolumes(part.geometry)
                    XCTAssertFalse(volumes.isEmpty, "\(name) \(kind) \(part.finish) has no solids")
                    for volume in volumes {
                        XCTAssertGreaterThan(volume, 0, "\(name) \(kind) \(part.finish) has a solid turned inside out")
                    }
                }
            }
        }
    }

    /// Every piece at its own height, so each is told apart by its height alone. The queen stands
    /// well under the king (Alex once mistook one for the other) and so under the bishop too.
    func testPiecesStandAtTheirOwnHeights() {
        let h = SculptedAssets.shared.heights
        let order: [Piece.Kind] = [.king, .bishop, .queen, .knight, .rook, .pawn]
        for (taller, shorter) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(h[taller] ?? 0, (h[shorter] ?? 0) + 0.05, "\(taller) should stand above \(shorter)")
        }
        XCTAssertLessThanOrEqual(h[.king] ?? 9, SculptedCamera.tallest)
        XCTAssertGreaterThan(h[.king] ?? 0, (h[.queen] ?? 9) + 0.4, "the king must tower over the queen")
    }

    /// The king wears a closed crown in both sets: metal arches strung with pearls over the stone's
    /// own cap, under an orb and cross in the same metal on both sides. An older set's cross (its
    /// own finish) still draws as it did: ivory on the white king, metal on the dark one.
    func testTheKingWearsAClosedCrown() {
        let assets = SculptedAssets.shared
        for look in [SculptedLook.gilded, .noir] {
            let king = assets.parts(for: look)[.king] ?? []
            XCTAssertTrue(king.contains { $0.finish == .pearl }, "\(look.name): the crown's arches lost their pearls")
            XCTAssertTrue(king.contains { $0.finish == .gem }, "\(look.name): the circlet lost its stones")
            XCTAssertFalse(king.contains { $0.finish == .cross }, "\(look.name): the cross is the crown's metal now")
            XCTAssertTrue(assets.material(.cross, for: .white, look: look) === assets.material(.body, for: .white, look: look))
            XCTAssertTrue(assets.material(.cross, for: .black, look: look) === assets.material(.metal, for: .black, look: look))
        }
    }

    func testTheFramedBoardFillsTheViewAndStaysInside() {
        for aspect: Float in [1, 0.8, 1.35, 1.6] {
            for flipped in [false, true] {
                let camera = SculptedCamera.fitted(aspect: aspect, flipped: flipped)
                // From Black's side the far rank, whose kings must fit, is White's first rank.
                let points = SculptedCamera.keyPoints
                    .map { flipped ? SIMD3($0.x * -1, $0.y, $0.z * -1) : $0 }
                    .map(camera.normalized)
                XCTAssertTrue(points.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 }, "\(aspect) \(flipped)")
                // Up to the game's own shape, the board's near corners reach the side margins.
                if aspect <= Float(SculptedBoardView.aspect) {
                    XCTAssertGreaterThan(points.map { abs($0.x) }.max() ?? 0, 0.95)
                }
                let ys = points.map(\.y)
                XCTAssertEqual((ys.max()! + ys.min()!) / 2, 0, accuracy: 0.02, "the picture is centered")
            }
        }
    }

    /// Flat from above: every flat piece's box stays inside its own square on every square, from
    /// both sides.
    func testFlatPiecesStayInsideTheirSquares() {
        let framing = SculptedCamera.Framing.seated
        let size = CGSize(width: 402, height: 402 / framing.aspect)
        let kinds: [Piece.Kind] = [.king, .queen, .rook, .bishop, .knight, .pawn]
        // The widest and the tallest of the set, together: a box round all of it.
        let extents = kinds.map { SculptedFlatSet.extent(of: $0) }
        let half = extents.map { $0.reach }.max() ?? 0
        let height = (extents.map { $0.height }.max() ?? 0) + 0.01
        XCTAssertGreaterThan(half, 0.2, "the flat set loaded")
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(size.width / size.height), flipped: flipped, framing: framing)
            for index in 0..<64 {
                let square = Square(file: index % 8, rank: index / 8)
                let center = SculptedCamera.position(of: square)
                let outline = camera.frame(of: square, in: size).insetBy(dx: -0.5, dy: -0.5)
                for dz in [-half, half] {
                    for dx in [-half, half] {
                        let point = camera.screenPoint(center + SIMD3(dx, height, dz), in: size)
                        XCTAssertTrue(outline.contains(point), "\(square) flipped \(flipped)")
                    }
                }
            }
        }
    }

    /// The flat set has all six pieces in both colors, each a shape over its shadow.
    func testTheFlatSetHasAllSixPieces() {
        for color in [Piece.Color.white, .black] {
            for kind in [Piece.Kind.king, .queen, .rook, .bishop, .knight, .pawn] {
                let node = SculptedFlatSet.makePiece(kind, color: color, look: .gilded)
                XCTAssertEqual(node.childNodes.count, 2, "\(color) \(kind)")
                XCTAssertTrue(node.childNodes.allSatisfy { $0.geometry != nil }, "\(color) \(kind)")
                // The shadow lies under the board's marks, the shape over them.
                XCTAssertLessThan(node.childNodes[0].renderingOrder, node.childNodes[1].renderingOrder)
            }
        }
    }

    /// Every cut-out has its picture and its shadow, and the shape in the picture reaches no
    /// further from the middle than its stated reach, which keeps it inside its own square.
    func testEveryCutOutHasItsPictureAndShadow() throws {
        for color in [Piece.Color.white, .black] {
            for kind in [Piece.Kind.king, .queen, .rook, .bishop, .knight, .pawn] {
                let name = SculptedFlatSet.pictureName(kind, color: color)
                let picture = try XCTUnwrap(UIImage(named: name)?.cgImage, "\(name) is missing")
                XCTAssertNotNil(UIImage(named: SculptedFlatSet.shadowName(kind)), "\(kind)'s shadow is missing")
                XCTAssertEqual(picture.width, picture.height, name)
                let reach = Self.opaqueReach(picture) * Double(SculptedFlatSet.span)
                XCTAssertLessThanOrEqual(reach, Double(SculptedFlatSet.half(of: kind)) + 0.005, name)
                XCTAssertGreaterThan(reach, Double(SculptedFlatSet.half(of: kind)) - 0.03, "\(name) is smaller than stated")
                XCTAssertLessThan(Double(SculptedFlatSet.half(of: kind)), 0.42, "\(name) crowds its square")
            }
        }
    }

    /// How far a picture's visible pixels reach from its middle, as a share of its width.
    private static func opaqueReach(_ image: CGImage) -> Double {
        let side = image.width
        var alpha = [UInt8](repeating: 0, count: side * side)
        let context = CGContext(data: &alpha, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var reach = 0.0
        let middle = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side where alpha[y * side + x] > 20 {
                reach = max(reach, abs(Double(x) + 0.5 - middle), abs(Double(y) + 0.5 - middle))
            }
        }
        return reach / Double(side)
    }

    /// The flat view looks straight down, so the polished board mirrors the top of its studio:
    /// under the soft box overhead the stone and the glass frame went milky. Seen from above, every
    /// look's studio has a dark ceiling; the tilted view keeps its soft box.
    func testTheStudioSeenFromAboveHasADarkCeiling() throws {
        for look in SculptedLook.all {
            let above = try XCTUnwrap(SculptedAssets.shared.environment(look, above: true)?.cgImage,
                                      "\(look.name) is missing \(look.studioAbove)")
            let tilted = try XCTUnwrap(SculptedAssets.shared.environment(look)?.cgImage, look.name)
            XCTAssertLessThan(Self.ceilingBrightness(above), 0.15, "\(look.name): the flat board would mirror a light")
            XCTAssertGreaterThan(Self.ceilingBrightness(tilted), 0.5, look.name)
        }
    }

    /// Flat, the scene takes the studio seen from above; tilted again, its own.
    func testTheFlatViewIsLitFromAbove() {
        let scene = SculptedBoardScene()
        let tilted = SculptedBoardState(pieces: Self.startPieces)
        var flat = tilted
        flat.framing = .seated
        scene.apply(tilted, animated: false)
        XCTAssertFalse(scene.litFromAbove)
        scene.apply(flat, animated: false)
        XCTAssertTrue(scene.litFromAbove)
        scene.apply(tilted, animated: false)
        XCTAssertFalse(scene.litFromAbove)
    }

    /// A floating board (the King's hall) has no frame and throws no shadow behind itself;
    /// every other board keeps both.
    func testAFloatingBoardHasNothingAroundItsSquares() {
        let scene = SculptedBoardScene()
        let framed = SculptedBoardState(pieces: Self.startPieces)
        var floating = framed
        floating.floating = true
        scene.apply(framed, animated: false)
        XCTAssertTrue(scene.showsSurround)
        scene.apply(floating, animated: false)
        XCTAssertFalse(scene.showsSurround)
        scene.apply(framed, animated: false)
        XCTAssertTrue(scene.showsSurround)
    }

    func testTheFlatBoardFillsItsViewAndStaysInside() {
        let framing = SculptedCamera.Framing.seated
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(framing.aspect), flipped: flipped, framing: framing)
            let points = SculptedCamera.keyPoints(tallest: framing.tallest)
                .map { flipped ? SIMD3($0.x * -1, $0.y, $0.z * -1) : $0 }
                .map(camera.normalized)
            XCTAssertTrue(points.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 })
            XCTAssertGreaterThan(points.map { abs($0.x) }.max() ?? 0, 0.95, "edge to edge")
            XCTAssertGreaterThan(points.map { abs($0.y) }.max() ?? 0, 0.9, "top to bottom, nothing wasted")
        }
    }

    /// The files and ranks sit in the corners of the edge squares, so the board can run edge to
    /// edge (Alex, 2026-11-07): each letter on its own file's near square, each number on its own
    /// rank's left square, all in the picture, upright and the right way round from either side,
    /// tilted or flat.
    func testTheFilesAndRanksSitInTheCornersOfTheEdgeSquares() {
        let files = Array("abcdefgh")
        for flipped in [false, true] {
            let labels = SculptedBoardScene.labelPlacements(flipped: flipped)
            let letters = labels.filter { $0.text.first?.isLetter == true }
            let numbers = labels.filter { $0.text.first?.isNumber == true }
            XCTAssertEqual(letters.map(\.text).sorted(), files.map { String($0) })
            XCTAssertEqual(numbers.map(\.text).sorted(), (1...8).map { String($0) })
            for label in labels {
                // On its own square, clear of the square's edges, a hair above the stone.
                XCTAssertEqual(SculptedCamera.square(at: label.position), label.square, label.text)
                let center = SculptedCamera.position(of: label.square)
                XCTAssertLessThan(abs(label.position.x - center.x), 0.5 - 0.12, label.text)
                XCTAssertLessThan(abs(label.position.z - center.z), 0.5 - 0.12, label.text)
                XCTAssertGreaterThan(label.position.y, 0, "on top of the stone")
            }
            for letter in letters {
                XCTAssertEqual(letter.square.rankIndex, flipped ? 7 : 0, "\(letter.text) is on the near rank")
            }
            for number in numbers {
                XCTAssertEqual(number.square.fileIndex, flipped ? 7 : 0, "\(number.text) is on the left file")
            }
            for letter in letters {
                XCTAssertEqual(letter.square.fileIndex, files.firstIndex(of: letter.text.first!)!, letter.text)
            }
            for number in numbers {
                XCTAssertEqual(number.square.rankIndex, Int(number.text)! - 1, number.text)
            }

            // A glyph's own up and right, lying on the squares.
            let turn = SculptedBoardScene.labelOrientation(flipped: flipped)
            let glyphUp = turn.act(SIMD3<Float>(0, 0.1, 0))
            let glyphRight = turn.act(SIMD3<Float>(0.1, 0, 0))
            let views: [(SculptedCamera.Framing, Float)] = [
                (.standing, SculptedCamera.standingAspects.lowerBound),
                (.standing, SculptedCamera.standingAspects.upperBound),
                (.seated, Float(SculptedCamera.Framing.seated.aspect)),
            ]
            for (framing, aspect) in views {
                let size = CGSize(width: 390, height: CGFloat(390 / aspect))
                let camera = SculptedCamera.fitted(aspect: aspect, flipped: flipped, framing: framing)
                let view = "\(framing) \(aspect) flipped \(flipped)"
                func screen(_ point: SIMD3<Float>) -> CGPoint { camera.screenPoint(point, in: size) }
                for label in labels {
                    // The whole glyph is in the picture, not cut off at the view's edge.
                    for dx: Float in [-0.12, 0.12] {
                        for dz: Float in [-0.12, 0.12] {
                            let n = camera.normalized(label.position + SIMD3(dx, 0, dz))
                            XCTAssertTrue(abs(n.x) <= 1 && abs(n.y) <= 1, "\(label.text) \(view)")
                        }
                    }
                    // Its top points up the screen and its right to the right: upright, not mirrored.
                    let here = screen(label.position)
                    XCTAssertLessThan(screen(label.position + glyphUp).y, here.y, "\(label.text) \(view)")
                    XCTAssertGreaterThan(screen(label.position + glyphRight).x, here.x, "\(label.text) \(view)")
                }
                // Read along the bottom, a to h for White and h to a for Black; up the left side,
                // 1 to 8 for White and 8 to 1 for Black.
                let across = letters.sorted { screen($0.position).x < screen($1.position).x }.map(\.text).joined()
                XCTAssertEqual(across, flipped ? "hgfedcba" : "abcdefgh", view)
                let up = numbers.sorted { screen($0.position).y > screen($1.position).y }.map(\.text).joined()
                XCTAssertEqual(up, flipped ? "87654321" : "12345678", view)
                // In the corners: each letter at its square's bottom right, each number at its top left.
                for letter in letters {
                    let middle = screen(SculptedCamera.position(of: letter.square))
                    XCTAssertGreaterThan(screen(letter.position).x, middle.x, "\(letter.text) \(view)")
                    XCTAssertGreaterThan(screen(letter.position).y, middle.y, "\(letter.text) \(view)")
                }
                for number in numbers {
                    let middle = screen(SculptedCamera.position(of: number.square))
                    XCTAssertLessThan(screen(number.position).x, middle.x, "\(number.text) \(view)")
                    XCTAssertLessThan(screen(number.position).y, middle.y, "\(number.text) \(view)")
                }
            }
        }
    }

    /// The files and ranks never take the color of the square they're on (Alex, 2026-11-07):
    /// on every look, the ink on a light square is well darker than it, and on a dark square well lighter.
    func testTheFilesAndRanksStandOutFromTheirSquares() throws {
        for look in SculptedLook.all {
            let image = try XCTUnwrap(UIImage(named: look.squares)?.cgImage, look.squares)
            let squares = try XCTUnwrap(SculptedBoardScene.squareAverages(image), look.squares)
            let inks = SculptedBoardScene.labelInks(squares: look.squares)
            func lum(_ color: UIColor) -> Float {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                return SculptedBoardScene.luminance(SIMD3(Float(r), Float(g), Float(b)))
            }
            XCTAssertGreaterThan(SculptedBoardScene.luminance(squares.light) - lum(inks.onLight), 0.25, "\(look.name) light squares")
            XCTAssertGreaterThan(lum(inks.onDark) - SculptedBoardScene.luminance(squares.dark), 0.25, "\(look.name) dark squares")
        }
    }

    func testBoardViewSetting() {
        XCTAssertEqual(BoardTilt.tilted.framing, .standing)
        XCTAssertEqual(BoardTilt.flat.framing, .seated)
        // "auto", saved before Big Board went, reads as Tilted.
        XCTAssertEqual(BoardTilt(rawValue: "auto"), .tilted)
        XCTAssertEqual(BoardTilt.allCases, [.tilted, .flat])
    }

    /// The switch under the board shows the view in play, and none while the board is 2D.
    func testTheBoardViewSwitchShowsTheViewInPlay() {
        XCTAssertEqual(BoardViewSwitch.showing(.gilded, threeD: true, framing: .standing), .tilted)
        XCTAssertEqual(BoardViewSwitch.showing(.noir, threeD: true, framing: .seated), .flat)
        XCTAssertNil(BoardViewSwitch.showing(.gilded, threeD: false, framing: .standing))
        XCTAssertNil(BoardViewSwitch.showing(.classic, threeD: true, framing: .seated))
    }

    /// Picking Tilted or Flat always ends on a 3D board: a look without one moves to Gilded,
    /// and a rival's board gives way to the player's own look.
    func testPickingAViewAlwaysLandsOnA3DBoard() {
        XCTAssertEqual(BoardViewSwitch.change(inPlay: .noir, chosen: .noir), .init())
        XCTAssertEqual(BoardViewSwitch.change(inPlay: .classic, chosen: .classic), .init(look: .gilded))
        XCTAssertEqual(BoardViewSwitch.change(inPlay: .spark, chosen: .midnight), .init(leavesRivalBoard: true))
        XCTAssertEqual(BoardViewSwitch.change(inPlay: .spark, chosen: .neon), .init(leavesRivalBoard: true, look: .gilded))
        XCTAssertEqual(BoardViewSwitch.change(inPlay: .pulse, chosen: .pulse), .init(look: .gilded))
        XCTAssertNotNil(BoardTheme.gilded.sculptedLook)
    }

    func testEverySquareIsFoundUnderItsOwnCenter() {
        let size = CGSize(width: 390, height: 390 / SculptedBoardView.aspect)
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(size.width / size.height), flipped: flipped)
            for index in 0..<64 {
                let square = Square(file: index % 8, rank: index / 8)
                let point = camera.screenPoint(SculptedCamera.position(of: square), in: size)
                XCTAssertEqual(camera.square(at: point, in: size), square)
            }
        }
    }

    func testWhiteSeesItsOwnSideNearest() {
        let size = CGSize(width: 390, height: 390)
        let white = SculptedCamera.fitted(aspect: 1, flipped: false)
        let black = SculptedCamera.fitted(aspect: 1, flipped: true)
        let e1 = SculptedCamera.position(of: .e1)
        let e8 = SculptedCamera.position(of: .e8)
        XCTAssertGreaterThan(white.screenPoint(e1, in: size).y, white.screenPoint(e8, in: size).y)
        XCTAssertLessThan(black.screenPoint(e1, in: size).y, black.screenPoint(e8, in: size).y)
        // a-file on White's left, on Black's right.
        XCTAssertLessThan(white.screenPoint(SculptedCamera.position(of: .a4), in: size).x, size.width / 2)
        XCTAssertGreaterThan(black.screenPoint(SculptedCamera.position(of: .a4), in: size).x, size.width / 2)
    }

    /// The camera math the taps use agrees with what SceneKit draws.
    func testSceneKitDrawsWhereTheCameraMathSays() throws {
        let scene = SculptedBoardScene()
        let window = try hostWindow(for: scene.view, side: 390)
        scene.apply(SculptedBoardState(pieces: Self.startPieces), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let size = scene.view.bounds.size
        for point in [SIMD3<Float>(-4.55, 0, 4.55), SIMD3(4.55, 0, -4.55), SIMD3(0, 1.2, -3.5), SIMD3(1.5, 0, 0.5)] {
            let ours = scene.camera.screenPoint(point, in: size)
            let theirs = scene.view.projectPoint(SCNVector3(point.x, point.y, point.z))
            XCTAssertEqual(ours.x, CGFloat(theirs.x), accuracy: 1.5)
            XCTAssertEqual(ours.y, CGFloat(theirs.y), accuracy: 1.5)
        }
        // Tapping a pawn's head finds its square; tapping open stone finds the stone.
        let e2Head = scene.camera.screenPoint(SculptedCamera.position(of: .e2) + SIMD3(0, 0.55, 0), in: size)
        XCTAssertEqual(scene.square(at: e2Head), .e2)
        let e4 = scene.camera.screenPoint(SculptedCamera.position(of: .e4), in: size)
        XCTAssertEqual(scene.square(at: e4), .e4)
        window.isHidden = true
    }

    /// With a piece picked up, a tap on a move mark plays there, even where the mark shows
    /// through a piece standing in front of it. Elsewhere that piece is still the piece.
    func testATapOnAMoveMarkFindsItThroughAPiece() throws {
        let scene = SculptedBoardScene()
        let window = try hostWindow(for: scene.view, side: 390)
        // 1.e4 e5 2.Nf3 Nc6 and the queen picked up: e2 is right behind the king.
        let pieces = (Position(fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")?.pieces ?? [])
            .map { PlacedPiece(id: $0.square.rawValue, piece: $0) }
        scene.apply(SculptedBoardState(pieces: pieces, selected: .d1, targets: [.e2]), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let size = scene.view.bounds.size
        let e2 = scene.camera.screenPoint(SculptedCamera.position(of: .e2), in: size)
        XCTAssertEqual(scene.square(at: e2), .e2)
        let kingsChest = scene.camera.screenPoint(SculptedCamera.position(of: .e1) + SIMD3(0, 0.6, 0), in: size)
        XCTAssertEqual(scene.square(at: kingsChest), .e1)
        // With nothing picked up, the king hides the near part of e2 (seen from above the board's
        // near half, as the camera tips higher, it no longer hides e2's middle).
        let nearE2 = scene.camera.screenPoint(SculptedCamera.position(of: .e2) + SIMD3(0, 0, 0.4), in: size)
        scene.apply(SculptedBoardState(pieces: pieces), animated: false)
        XCTAssertEqual(scene.square(at: nearE2), .e1)
        window.isHidden = true
    }

    /// Looking back through a game: each piece keeps its id, so it walks back rather than fading.
    func testPiecesKeepTheirIdentityWhenLookingBack() {
        var next = 1000
        let live = Self.startPieces
        // 1. e4 e5 2. Nf3, then a step back to before Nf3, then the start again.
        let afterNf3 = Position(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2")!.pieces
        let shown = SculptedBoardScene.carryIdentity(afterNf3, from: live, nextID: &next)
        let id = { (pieces: [PlacedPiece], square: Square) in pieces.first { $0.square == square }?.id }
        XCTAssertEqual(id(shown, .f3), id(live, .g1), "the knight is the one from g1")
        XCTAssertEqual(id(shown, .e4), id(live, .e2))
        XCTAssertEqual(id(shown, .e5), id(live, .e7))
        XCTAssertEqual(id(shown, .a1), id(live, .a1))
        XCTAssertEqual(Set(shown.map(\.id)).count, 32, "no id is used twice")
        XCTAssertEqual(next, 1000, "nobody new came on")
        // After a capture the taken piece is gone; stepping back brings a new one.
        let taken = Position(fen: "rnbqkbnr/pppp1ppp/8/4N3/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 0 3")!.pieces
        let afterCapture = SculptedBoardScene.carryIdentity(taken, from: shown, nextID: &next)
        XCTAssertEqual(id(afterCapture, .e5), id(shown, .f3), "the knight took on e5")
        let back = SculptedBoardScene.carryIdentity(afterNf3, from: afterCapture, nextID: &next)
        XCTAssertEqual(id(back, .f3), id(shown, .f3))
        XCTAssertEqual(id(back, .e5), 1000, "the pawn comes back as a new piece")
    }

    func testTheNewLookIsSwitchedOnOnce() {
        let defaults = UserDefaults(suiteName: "SculptedBoardTests")!
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
        defaults.set("faberge", forKey: "boardTheme")
        defaults.set(true, forKey: "matchRival")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "gilded")
        XCTAssertEqual(defaults.bool(forKey: "matchRival"), false)
        // A look picked afterwards stays.
        defaults.set("neon", forKey: "boardTheme")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "neon")
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
    }

    /// Someone who already met Sculpted and turned "Match rival" back on keeps it on.
    func testGildedKeepsAMatchRivalChoiceMadeAfterSculpted() {
        let defaults = UserDefaults(suiteName: "SculptedBoardTests")!
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
        defaults.set(true, forKey: LookIntroduction.sculptedKey)
        defaults.set("sculpted", forKey: "boardTheme")
        defaults.set(true, forKey: "matchRival")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "gilded")
        XCTAssertEqual(defaults.bool(forKey: "matchRival"), true)
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
    }

    /// Someone on Noir, the last default, moves to Gilded once and can go back to Noir.
    func testANoirPlayerMovesToGildedOnce() {
        let defaults = UserDefaults(suiteName: "SculptedBoardTests")!
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
        defaults.set(true, forKey: "noirIntroduced")
        defaults.set(true, forKey: LookIntroduction.sculptedKey)
        defaults.set("noir", forKey: "boardTheme")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "gilded")
        defaults.set("noir", forKey: "boardTheme")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "noir")
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
    }

    // MARK: Helpers

    /// Relative luminance of an sRGB color, 0 for black to 1 for white.
    static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return luminance(Double(r), Double(g), Double(b))
    }

    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The average luminance of the light squares in a stone texture: the middle of each square,
    /// away from the grooves, in whichever checker color is brighter.
    static func lightSquareLuminance(_ image: CGImage) -> Double {
        let side = 128, cell = side / 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                    bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .high
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        var sums = [0.0, 0.0], counts = [0, 0]
        for y in 0..<side {
            for x in 0..<side {
                guard (3..<(cell - 3)).contains(x % cell), (3..<(cell - 3)).contains(y % cell) else { continue }
                let parity = (x / cell + y / cell) % 2
                let i = (y * side + x) * 4
                sums[parity] += luminance(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
                counts[parity] += 1
            }
        }
        return max(sums[0] / Double(max(counts[0], 1)), sums[1] / Double(max(counts[1], 1)))
    }

    /// How bright an equirectangular studio is at its top, straight overhead, from 0 to 1.
    static func ceilingBrightness(_ image: CGImage) -> Double {
        let width = 64, height = 32, rows = 3
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .high
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // The buffer starts with the picture's top row.
        let top = (0..<(width * rows)).map { Double(pixels[$0 * 4]) / 255 }
        return top.reduce(0, +) / Double(top.count)
    }

    /// The average luminance of a piece picture where it is solid, leaving out its soft shadow.
    static func opaqueLuminance(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var sum = 0.0, count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 230 {
            let alpha = Double(pixels[i + 3])
            sum += luminance(Double(pixels[i]) / alpha, Double(pixels[i + 1]) / alpha, Double(pixels[i + 2]) / alpha)
            count += 1
        }
        return sum / Double(max(count, 1))
    }

    /// The signed volume of each solid in a mesh (positive when its triangles face outward),
    /// for solids of 30 triangles or more. Split vertices are welded by position first.
    static func solidVolumes(_ geometry: SCNGeometry) -> [Double] {
        guard let source = geometry.sources(for: .vertex).first, let element = geometry.elements.first else { return [] }
        var welded: [SIMD3<Int32>: Int] = [:]
        var points: [SIMD3<Double>] = []
        var vertex = [Int](repeating: 0, count: source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0..<source.vectorCount {
                let base = source.dataOffset + i * source.dataStride
                let p = SIMD3<Float>(raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                                     raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                                     raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self))
                let key = SIMD3<Int32>(p * 100_000, rounding: .toNearestOrAwayFromZero)
                if let id = welded[key] {
                    vertex[i] = id
                } else {
                    vertex[i] = points.count
                    welded[key] = points.count
                    points.append(SIMD3<Double>(p))
                }
            }
        }
        var triangles: [(Int, Int, Int)] = []
        element.data.withUnsafeBytes { raw in
            for t in 0..<element.primitiveCount {
                let read = { (k: Int) in vertex[Int(raw.loadUnaligned(fromByteOffset: (t * 3 + k) * 4, as: UInt32.self))] }
                triangles.append((read(0), read(1), read(2)))
            }
        }
        var parent = Array(0..<points.count)
        func root(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for (a, b, c) in triangles {
            let ra = root(a), rb = root(b)
            parent[rb] = ra
            let rc = root(c)
            parent[rc] = ra
        }
        var volume: [Int: Double] = [:]
        var count: [Int: Int] = [:]
        for (a, b, c) in triangles {
            let (p, q, r) = (points[a], points[b], points[c])
            let cross = SIMD3(q.y * r.z - q.z * r.y, q.z * r.x - q.x * r.z, q.x * r.y - q.y * r.x)
            let solid = root(a)
            volume[solid, default: 0] += (p * cross).sum() / 6
            count[solid, default: 0] += 1
        }
        return volume.filter { count[$0.key, default: 0] >= 30 }.map(\.value)
    }

    static var startPieces: [PlacedPiece] {
        (Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")?.pieces ?? [])
            .map { PlacedPiece(id: $0.square.rawValue, piece: $0) }
    }

    func hostWindow(for view: UIView, side: CGFloat) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: side, height: side + 100)
        let host = UIViewController()
        host.view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.11, alpha: 1)
        view.frame = CGRect(x: 0, y: 50, width: side, height: side)
        host.view.addSubview(view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }
}
