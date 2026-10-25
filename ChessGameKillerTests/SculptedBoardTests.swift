import ChessKit
import SceneKit
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

    /// The king's cross is its own finish: ivory on the white king, metal on the dark one.
    func testTheKingsCrossIsIvoryOnWhiteAndMetalOnBlack() {
        let assets = SculptedAssets.shared
        for look in [SculptedLook.gilded, .noir] {
            XCTAssertTrue(assets.parts(for: look)[.king]?.contains { $0.finish == .cross } ?? false, "\(look.name): the king has no cross")
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

    /// Big Board looks from above: every piece, even a king on the far rank, stays inside its
    /// own square, its cross below the square's far edge and its foot clear of the near one.
    func testSeatedPiecesStayInsideTheirSquares() {
        let framing = SculptedCamera.Framing.seated
        let size = CGSize(width: 402, height: 402 / framing.aspect)
        let tallest = SculptedAssets.shared.height(of: .king) * framing.pieceScale
        let foot = 0.34 * framing.pieceScale
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(size.width / size.height), flipped: flipped, framing: framing)
            // Toward the top of the screen is away from the player.
            let away: Float = flipped ? 1 : -1
            for index in 0..<64 {
                let square = Square(file: index % 8, rank: index / 8)
                let center = SculptedCamera.position(of: square)
                let top = camera.screenPoint(center + SIMD3(0, tallest, 0), in: size).y
                let farEdge = camera.screenPoint(center + SIMD3(0, 0, 0.5 * away), in: size).y
                let nearFoot = camera.screenPoint(center + SIMD3(0, 0, -foot * away), in: size).y
                let nearEdge = camera.screenPoint(center + SIMD3(0, 0, -0.5 * away), in: size).y
                XCTAssertGreaterThan(top, farEdge, "\(square) king rises out of its square, flipped \(flipped)")
                XCTAssertLessThan(nearFoot, nearEdge, "\(square) foot spills forward, flipped \(flipped)")
            }
        }
    }

    func testTheSeatedBoardFillsItsViewAndStaysInside() {
        let framing = SculptedCamera.Framing.seated
        for flipped in [false, true] {
            let camera = SculptedCamera.fitted(aspect: Float(framing.aspect), flipped: flipped, framing: framing)
            let points = SculptedCamera.keyPoints(tallest: SculptedCamera.tallest * framing.pieceScale)
                .map { flipped ? SIMD3($0.x * -1, $0.y, $0.z * -1) : $0 }
                .map(camera.normalized)
            XCTAssertTrue(points.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 })
            XCTAssertGreaterThan(points.map { abs($0.x) }.max() ?? 0, 0.95, "edge to edge")
            XCTAssertGreaterThan(points.map { abs($0.y) }.max() ?? 0, 0.9, "top to bottom, nothing wasted")
        }
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
        // With nothing picked up, the king hides the middle of e2.
        scene.apply(SculptedBoardState(pieces: pieces), animated: false)
        XCTAssertEqual(scene.square(at: e2), .e1)
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
