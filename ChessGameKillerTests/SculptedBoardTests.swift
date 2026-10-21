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

    /// Tournament heights, so every piece is told apart by its height alone.
    func testPiecesStandAtTournamentHeights() {
        let h = SculptedAssets.shared.heights
        let order: [Piece.Kind] = [.king, .queen, .bishop, .knight, .rook, .pawn]
        for (taller, shorter) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(h[taller] ?? 0, (h[shorter] ?? 0) + 0.05, "\(taller) should stand above \(shorter)")
        }
        XCTAssertLessThanOrEqual(h[.king] ?? 9, SculptedCamera.tallest)
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
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "noir")
        XCTAssertEqual(defaults.bool(forKey: "matchRival"), false)
        // A look picked afterwards stays.
        defaults.set("neon", forKey: "boardTheme")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "neon")
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
    }

    /// Someone who already met Sculpted and turned "Match rival" back on keeps it on.
    func testNoirKeepsAMatchRivalChoiceMadeAfterSculpted() {
        let defaults = UserDefaults(suiteName: "SculptedBoardTests")!
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
        defaults.set(true, forKey: LookIntroduction.sculptedKey)
        defaults.set("sculpted", forKey: "boardTheme")
        defaults.set(true, forKey: "matchRival")
        LookIntroduction.applyOnce(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "boardTheme"), "noir")
        XCTAssertEqual(defaults.bool(forKey: "matchRival"), true)
        defaults.removePersistentDomain(forName: "SculptedBoardTests")
    }

    // MARK: Helpers

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
