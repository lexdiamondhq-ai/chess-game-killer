import ChessKit
import SceneKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Pictures of the screens that follow the home's Light, Middle or Dark and have no pictures of
/// their own elsewhere: the four welcome pages, How it works and the highlight reel. Saved to
/// SNAPSHOT_DIR as light-*.png. The home is set to its default, Light.
@MainActor
final class LightScreensSnapshotTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var saved: [String: Any?] = [:]
    private static let keys = ["boardTheme", "sculpted3D", HomeToneMode.key, HomeLayout.key]

    override func setUp() async throws {
        for key in Self.keys {
            saved[key] = defaults.object(forKey: key)
        }
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(true, forKey: "sculpted3D")
        defaults.set(HomeToneMode.light.rawValue, forKey: HomeToneMode.key)
        defaults.set(true, forKey: HomeLayout.key)
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    func testWelcomePages() throws {
        // Long enough for each page's scene to play to its end.
        for page in 0..<WelcomeFlow.pages {
            try snapshot("welcome-\(page + 1)", view: WelcomeFlow(page: page) { _, _ in }, wait: 6)
        }
    }

    func testHowItWorks() throws {
        let theme = BoardTheme.named(.gilded)
        try snapshot("light-guide", view: NavigationStack { GuideView(theme: theme) {} }.screenScheme(theme))
    }

    func testHighlightReelFrames() throws {
        let theme = BoardTheme.named(.gilded)
        let reel = Self.reel
        try snapshot("light-reel-intro", view: ReelFrame(reel: reel, theme: theme, time: 1.5, wordmarkTop: 96))
        try snapshot("light-reel-highlight",
                     view: ReelFrame(reel: reel, theme: theme, time: GameReel.introLength + 1.5, wordmarkTop: 96))
    }

    /// The wiring that once called itself forever: on the older home a screen keeps the board's own room.
    func testScreensOpenOnTheOlderHome() throws {
        defaults.set(false, forKey: HomeLayout.key)
        let theme = BoardTheme.named(.gilded)
        XCTAssertNil(theme.screenTone)
        try snapshot("light-older-home-guide", view: NavigationStack { GuideView(theme: theme) {} }.screenScheme(theme))
    }

    /// A won game with two highlights, in a Ruy Lopez's first moves.
    private static var reel: GameReel {
        let fens = [
            Position.standard.fen,
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
            "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
        ]
        func moment(_ ply: Int, _ grade: MoveReview.Grade, _ san: String, _ uci: String,
                    before: Double, after: Double) -> ReelMoment {
            ReelMoment(ply: ply, grade: grade, san: san, uci: uci, color: ply % 2 == 1 ? .white : .black,
                       fenBefore: fens[min(ply - 1, fens.count - 1)], fenAfter: fens[min(ply, fens.count - 1)],
                       best: "Nf3", before: before, after: after)
        }
        let log = [
            3: moment(3, .blunder, "Nf3", "g1f3", before: 0.05, after: -0.6),
            5: moment(5, .best, "Bb5", "f1b5", before: 0.5, after: 0.5),
        ]
        return GameReel.make(log: log, player: "Alex", opponent: "Pulse", playerColor: .white, winner: .white,
                             isOver: true, accuracy: 84, moveCount: 32, finalFEN: fens.last ?? Position.standard.fen)
    }

    private func snapshot(_ name: String, view: some View, wait: TimeInterval = 1.5) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        window.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            for view in Self.sceneViews(in: window) {
                view.snapshot().draw(in: view.convert(view.bounds, to: window))
            }
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.isHidden = true
    }

    private static func sceneViews(in view: UIView) -> [SCNView] {
        ((view as? SCNView).map { [$0] } ?? []) + view.subviews.flatMap { sceneViews(in: $0) }
    }
}
