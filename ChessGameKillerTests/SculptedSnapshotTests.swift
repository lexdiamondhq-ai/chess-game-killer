import ChessKit
import SceneKit
import XCTest
@testable import ChessGameKiller

/// Pictures of the 3D board at phone size, saved to SNAPSHOT_DIR for checking by eye:
/// a game in progress with every kind of mark, the board from Black's side, the light at
/// three levels, a close crop at full resolution, and a capture caught mid-move.
@MainActor
final class SculptedSnapshotTests: XCTestCase {

    /// The Italian Game, Black's bishop just out to c5, White's knight on f3 picked up.
    private static let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 6 5"

    private static var pieces: [PlacedPiece] {
        (Position(fen: fen)?.pieces ?? []).map { PlacedPiece(id: $0.square.rawValue, piece: $0) }
    }

    private static var midgame: SculptedBoardState {
        SculptedBoardState(
            pieces: pieces,
            selected: .f3,
            targets: [.e5, .g5, .h4, .d4, .g1],
            lastMove: LastMove(from: .f8, to: .c5),
            hints: [SculptedHint(from: .e1, to: .g1, isBest: true), SculptedHint(from: .d2, to: .d3, isBest: false)]
        )
    }

    func testGameInProgress() throws {
        let (scene, window) = try stage(Self.midgame)
        let image = scene.snapshot()
        try save(image, "sculpted-board")
        try save(crop(image, x: 0, y: 0.35, side: 0.5), "sculpted-board-crop")
        window.isHidden = true
    }

    func testFromBlacksSide() throws {
        var state = Self.midgame
        state.flipped = true
        state.selected = nil
        state.targets = []
        state.checkedKing = nil
        let (scene, window) = try stage(state)
        try save(scene.snapshot(), "sculpted-board-black")
        window.isHidden = true
    }

    func testCheckAndCaptureMarks() throws {
        var state = SculptedBoardState(pieces: Self.pieces)
        state.checkedKing = .e8
        state.selected = .c4
        state.targets = [.f7, .d5, .e6, .b5, .a6, .b3, .d3, .e2, .f1]
        let (scene, window) = try stage(state)
        try save(scene.snapshot(), "sculpted-board-marks")
        window.isHidden = true
    }

    /// Each 3D look at the size it has on an iPhone 17 Pro, a game in progress.
    func testEveryLook() throws {
        for look in SculptedLook.all {
            let (scene, window) = try stage(Self.midgame, look: look, side: 402)
            try save(scene.snapshot(), "study-\(look.name.lowercased())")
            window.isHidden = true
        }
    }

    /// Every look has its own stone, studio and cache key.
    func testLooksAreDistinct() {
        let looks = SculptedLook.all
        XCTAssertEqual(Set(looks.map(\.name)).count, looks.count, "two looks share a cache key")
        XCTAssertEqual(Set(looks.map(\.squares)).count, looks.count, "two looks share their stone")
        for look in looks {
            XCTAssertNotNil(UIImage(named: look.squares), "\(look.name) is missing \(look.squares)")
            XCTAssertNotNil(UIImage(named: look.studio), "\(look.name) is missing \(look.studio)")
        }
    }

    func testLightLevels() throws {
        for (name, environment, key) in [("low", 1.5, 900.0), ("high", 2.5, 1350.0)] as [(String, CGFloat, CGFloat)] {
            var look = SculptedLook.classic
            look.environment = environment
            look.key = key
            let (scene, window) = try stage(SculptedBoardState(pieces: Self.pieces), look: look)
            try save(scene.snapshot(), "sculpted-light-\(name)")
            window.isHidden = true
        }
    }

    /// Nf3xe5: the knight lifts and hops, the pawn tips away and is gone before it lands.
    func testCaptureInMotion() throws {
        let (scene, window) = try stage(SculptedBoardState(pieces: Self.pieces, lastMove: LastMove(from: .f8, to: .c5)))
        var after = SculptedBoardState(lastMove: LastMove(from: .f3, to: .e5))
        let pawn = Piece(.pawn, color: .black, square: .e5)
        after.pieces = Self.pieces.compactMap { placed in
            if placed.square == .e5 { return nil }
            if placed.square == .f3 { return PlacedPiece(id: placed.id, piece: Piece(.knight, color: .white, square: .e5)) }
            return placed
        }
        after.lastCapture = CaptureEvent(id: 1, piece: pawn)
        // Ten times slower than in play: taking a picture takes a moment of its own.
        SculptedBoardScene.motionScale = 10
        defer { SculptedBoardScene.motionScale = 1 }
        let start = Date()
        scene.apply(after, animated: true)
        for (index, time) in [0.6, 2.0, 3.2, 4.4, 9.5].enumerated() {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            try save(scene.snapshot(), "sculpted-motion-\(index + 1)")
        }
        window.isHidden = true
    }

    // MARK: Helpers

    private func stage(
        _ state: SculptedBoardState, look: SculptedLook = .noir, side: CGFloat = 390
    ) throws -> (SculptedBoardScene, UIWindow) {
        let scene = SculptedBoardScene(look: look, assets: SculptedAssets())
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: side, height: (side / SculptedBoardView.aspect).rounded())
        let host = UIViewController()
        host.view.backgroundColor = UIColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 1)
        scene.view.frame = host.view.bounds
        scene.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(scene.view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        scene.apply(state, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        return (scene, window)
    }

    /// A square piece of the picture, by fractions of its size, at full resolution.
    private func crop(_ image: UIImage, x: CGFloat, y: CGFloat, side: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width)
        let rect = CGRect(x: x * w, y: y * CGFloat(cg.height), width: side * w, height: side * w)
        guard let part = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: part)
    }

    private func save(_ image: UIImage, _ name: String) throws {
        // The board's background is clear; put it on the app's dark backdrop to judge it.
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let flattened = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            UIColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        XCTAssertGreaterThan(image.size.width, 10)
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = flattened.pngData() else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
