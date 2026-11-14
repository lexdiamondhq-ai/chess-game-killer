import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The screens that differ for a free player and a Premium one, each drawn both ways, so the two
/// sides of the app can be walked side by side without a purchase (inspection, 2026-11-14).
/// The tests otherwise see everything open (`Premium.unlimited`); here `Premium.pose` stands as
/// one player or the other. Saved to SNAPSHOT_DIR as sides-*-free.png and sides-*-premium.png.
@MainActor
final class FreeAndPremiumSnapshotTests: XCTestCase {
    private let theme = BoardTheme.named(.gilded)
    private static let keys = ["coachVoiceMuted", "boardTheme", Premium.activeKey]
    private var saved: [Any?] = []

    override func setUp() async throws {
        try await super.setUp()
        let defaults = UserDefaults.standard
        saved = Self.keys.map { defaults.object(forKey: $0) }
        defaults.set(true, forKey: "coachVoiceMuted")
        defaults.set(BoardTheme.ID.gilded.rawValue, forKey: "boardTheme")
    }

    override func tearDown() async throws {
        Premium.shared.pose(premium: nil)
        let defaults = UserDefaults.standard
        for (key, value) in zip(Self.keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try await super.tearDown()
    }

    /// Stands as one player. The rivals' ladder reads Premium from what the app remembered at
    /// launch, so that is set with it.
    private func stand(premium: Bool) -> String {
        Premium.shared.pose(premium: premium)
        UserDefaults.standard.set(premium, forKey: Premium.activeKey)
        return premium ? "premium" : "free"
    }

    func testThePremiumPage() throws {
        for premium in [false, true] {
            let side = stand(premium: premium)
            let window = try show(PremiumOfferView(feature: nil), wait: 2)
            try save(window, "sides-1-premium-page-\(side)")
            window.isHidden = true
        }
    }

    /// Where an allowance ends: the free player's offer, and the Premium player's "more tomorrow".
    func testWhereScansStop() throws {
        for premium in [false, true] {
            let side = stand(premium: premium)
            let window = try show(PremiumOfferView(feature: .scan), wait: 2)
            try save(window, "sides-2-scan-limit-\(side)")
            window.isHidden = true
        }
    }

    func testSettings() throws {
        for premium in [false, true] {
            let side = stand(premium: premium)
            let window = try show(SettingsSheet(), wait: 3)
            try save(window, "sides-3-settings-\(side)")
            scroll(window, to: 700)
            try save(window, "sides-4-settings-boards-\(side)")
            window.isHidden = true
        }
    }

    func testTheLearnDoors() throws {
        let sample = TrainSample(settled: true)
        for premium in [false, true] {
            let side = stand(premium: premium)
            let lessons = try show(sample.door(.lessons, theme: theme), wait: 3)
            try save(lessons, "sides-5-lessons-\(side)")
            lessons.isHidden = true
            let puzzles = try show(sample.door(.puzzles, theme: theme), wait: 3)
            try save(puzzles, "sides-6-puzzles-\(side)")
            puzzles.isHidden = true
            let calculation = try show(sample.door(.calculation, theme: theme), wait: 3)
            try save(calculation, "sides-7-calculation-\(side)")
            calculation.isHidden = true
            let dna = try show(sample.door(.games, theme: theme), wait: 4)
            try save(dna, "sides-8-chess-dna-\(side)")
            dna.isHidden = true
        }
    }

    /// A rival two steps up the ladder: locked for a free player who hasn't climbed there,
    /// open for Premium.
    func testARivalUpTheLadder() throws {
        for premium in [false, true] {
            let side = stand(premium: premium)
            let window = try show(RivalsHall(ended: .expert, begin: { _ in }, close: {}), wait: 3)
            try save(window, "sides-9-rival-\(side)")
            window.isHidden = true
        }
    }

    // MARK: Drawing

    private func show(_ view: some View, wait: TimeInterval) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    private func scroll(_ window: UIWindow, to offset: CGFloat) {
        guard let scroll = Self.scrollViews(in: window).max(by: { $0.contentSize.height < $1.contentSize.height }) else { return }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: min(top + offset, bottom)), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
