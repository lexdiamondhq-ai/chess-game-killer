import ChessKit
import SceneKit
import SwiftUI
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

    /// Hints on and the king picked up: brackets on the pieces the coach would move (the
    /// runner-up fainter), dots where the king can go, and a halo on its best square.
    func testHintMarks() throws {
        var state = SculptedBoardState(pieces: Self.pieces)
        state.selected = .e1
        state.targets = [.e2, .f1, .g1]
        state.hints = [SculptedHint(from: .e1, to: .g1, isBest: true), SculptedHint(from: .d2, to: .d3, isBest: false)]
        let (scene, window) = try stage(state)
        let image = scene.snapshot()
        try save(image, "hints-3d")
        try save(crop(image, x: 0.25, y: 0.5, side: 0.5), "hints-3d-crop")
        window.isHidden = true
    }

    /// A knight taken on the flat board, caught as it tips over away from the bishop
    /// that took it, lands and fades.
    func testFlatCaptureFallInMotion() throws {
        let theme = BoardTheme.named(.midnight)
        let size: CGFloat = 110
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: size * 4, height: size * 3)
        let board = ZStack {
            Color(red: 0.11, green: 0.115, blue: 0.125)
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { column in
                    Rectangle().fill(theme.squareFill(isLight: column % 2 == 0)).frame(width: size, height: size)
                }
            }
            PieceImage(piece: Piece(.bishop, color: .white, square: .b2), theme: theme, size: size, onBoard: true)
                .offset(x: -size / 2)
            CaptureFall(piece: Piece(.knight, color: .black, square: .b2), theme: theme, size: size, seed: 1, away: 1)
                .offset(x: -size / 2)
        }
        let start = Date()
        window.rootViewController = UIHostingController(rootView: board)
        window.makeKeyAndVisible()
        for (index, time) in [0.02, 0.12, 0.2, 0.3, 0.45, 0.9].enumerated() {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try save(image, "capture-fall-\(index + 1)")
        }
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

    /// The gilded set up close at full resolution: White's knight and bishop, then Black's knights.
    func testGildedCloseUps() throws {
        let (scene, window) = try stage(Self.midgame, look: .gilded, side: 402)
        let image = scene.snapshot()
        try save(crop(image, x: 0.1, y: 0.45, side: 0.5), "study-gilded-close-white")
        try save(crop(image, x: 0.15, y: 0.0, side: 0.5), "study-gilded-close-black")
        window.isHidden = true
    }

    /// The start from Black's side, where the ivory is farthest away and smallest, on every 3D look.
    func testTheIvoryFromBlacksSide() throws {
        var start = SculptedBoardState(pieces: SculptedBoardTests.startPieces)
        start.flipped = true
        for look in SculptedLook.all {
            let (scene, window) = try stage(start, look: look, side: 402)
            try save(scene.snapshot(), "study-\(look.name.lowercased())-black")
            window.isHidden = true
        }
    }

    /// The flat board after 1.d4 from Black's side, as the game shows it with 3D pieces off,
    /// for every theme, at phone size.
    func testFlatBoardsFromBlacksSide() throws {
        let draft = try XCTUnwrap(PositionDraft(fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"))
        for theme in BoardTheme.all {
            let board = PositionBoard(draft: draft, theme: theme, flipped: true, tints: [.d2: theme.lastMove, .d4: theme.lastMove])
                .frame(width: 370, height: 370)
                .padding(16)
                .background(Color(red: 0.11, green: 0.115, blue: 0.125))
            let renderer = ImageRenderer(content: board)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, "\(theme.name) did not draw")
            try save(image, "study-flat-\(theme.id.rawValue)-black")
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

    /// Checkmate: the losing king tips over, the light drops and the camera leans in.
    func testCheckmateFinale() throws {
        // Fool's mate: Black's queen on h4, White's king mated on e1.
        let fen = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
        let pieces = (Position(fen: fen)?.pieces ?? []).map { PlacedPiece(id: $0.square.rawValue, piece: $0) }
        let before = SculptedBoardState(pieces: pieces, lastMove: LastMove(from: .d8, to: .h4), checkedKing: .e1)
        let (scene, window) = try stage(before)
        var after = before
        after.finale = SculptedFinale(kingID: Square.e1.rawValue, square: .e1)
        SculptedBoardScene.motionScale = 4
        defer { SculptedBoardScene.motionScale = 1 }
        let start = Date()
        scene.apply(after, animated: true)
        for (index, time) in [3.4, 4.6, 9.0].enumerated() {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            try save(scene.snapshot(), "sculpted-finale-\(index + 1)")
        }
        window.isHidden = true
    }

    /// Bxd8: a queen taken slows the move, lands with a puff of dust and shakes the board.
    func testBigCaptureInMotion() throws {
        let fen = "r2qk2r/ppp2ppp/2n2n2/3pp1B1/1b2P3/2NP1N2/PPP2PPP/R2QKB1R w KQkq - 0 7"
        let pieces = (Position(fen: fen)?.pieces ?? []).map { PlacedPiece(id: $0.square.rawValue, piece: $0) }
        let (scene, window) = try stage(SculptedBoardState(pieces: pieces))
        var after = SculptedBoardState(lastMove: LastMove(from: .g5, to: .d8))
        after.pieces = pieces.compactMap { placed in
            if placed.square == .d8 { return nil }
            if placed.square == .g5 { return PlacedPiece(id: placed.id, piece: Piece(.bishop, color: .white, square: .d8)) }
            return placed
        }
        after.lastCapture = CaptureEvent(id: 1, piece: Piece(.queen, color: .black, square: .d8))
        SculptedBoardScene.motionScale = 10
        defer { SculptedBoardScene.motionScale = 1 }
        let start = Date()
        scene.apply(after, animated: true)
        for (index, time) in [2.5, 5.2, 6.4].enumerated() {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            try save(scene.snapshot(), "sculpted-big-capture-\(index + 1)")
        }
        window.isHidden = true
    }

    // MARK: Helpers

    private func stage(
        _ state: SculptedBoardState, look: SculptedLook = .gilded, side: CGFloat = 390
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
