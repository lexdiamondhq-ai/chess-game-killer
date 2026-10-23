import SceneKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Pictures of On the line at iPhone size: New Game with a piece picked, New Game when Pulse
/// is holding a piece (the rescue), and the army with that prisoner. Saved to SNAPSHOT_DIR as
/// on-the-line-*.png.
@MainActor
final class OnTheLineSnapshotTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var saved: [String: Any?] = [:]
    private static let keys = ["setup.level", "setup.side", "showBestMoves", "coachVerdicts"]

    override func setUp() async throws {
        for key in Self.keys { saved[key] = defaults.object(forKey: key) }
        defaults.set(MatchController.Level.club.rawValue, forKey: "setup.level")
        defaults.set(SideChoice.white.rawValue, forKey: "setup.side")
        defaults.set(false, forKey: "showBestMoves")
        defaults.set(true, forKey: "coachVerdicts")
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    /// An army with three named veterans, the knight the most experienced.
    private func veterans() -> ArmyStore {
        let store = ArmyStore()
        for _ in 0..<6 {
            let game = GameModel()
            for move in ["e2e4", "d7d5", "e4d5", "g8f6", "g1f3", "f6d5", "f3e5"] { _ = game.playEngineMove(move) }
            store.record(game.ledger!, playerColor: .white, won: true, stakes: GameStakes(level: .expert, assisted: false))
        }
        return store
    }

    func testPickingAPieceToPutOnTheLine() throws {
        let army = veterans()
        let pick = try XCTUnwrap(army.stakeable.first)
        try snapshot("on-the-line-pick", view: sheet(army, stakesOpen: true, stake: pick))
    }

    func testARivalHoldingAPiece() throws {
        let army = veterans()
        let held = try XCTUnwrap(army.stakeable.first)
        let loss = GameModel()
        _ = loss.playEngineMove("e2e4")
        army.record(loss.ledger!, playerColor: .white, won: false,
                    stakes: GameStakes(level: .club, assisted: false, staked: held))
        XCTAssertEqual(army.captor(of: held), .club)
        try snapshot("on-the-line-rescue", view: sheet(army, stakesOpen: true, stake: nil))
        try snapshot("on-the-line-army", view: ArmyView(theme: .named(.gilded), color: .white).environment(army))
    }

    private func sheet(_ army: ArmyStore, stakesOpen: Bool, stake: ArmySlot?) -> some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                NewGameSheet(theme: .named(.gilded), stakesOpen: stakesOpen, stake: stake, start: { _ in })
                    .environment(army)
            }
    }

    private func snapshot(_ name: String, view: some View, wait: TimeInterval = 2) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.rootViewController?.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
    }
}
