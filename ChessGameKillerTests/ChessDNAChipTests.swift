import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The weapon and the leak sit side by side on both Chess DNA cards, the one on Home and the one
/// on Learn, and must be one size (Alex, 2026-11-27: "The weapon and leak shapes are not the
/// same"). Each chip was only as tall as its own words, so a weapon on two lines stood taller
/// than a leak on one. This lays the real cards out at three phone widths, by day and by night,
/// and measures the two chips as drawn.
///
/// The cards read as one button to VoiceOver, so a tap test can't see the chips inside them:
/// they report their own sizes as they are laid out instead.
@MainActor
final class ChessDNAChipTests: XCTestCase {
    /// What the chips reported, filled in as the card is laid out.
    private final class Sizes: @unchecked Sendable {
        var all: [CGSize] = []
    }

    /// A weapon long enough to wrap onto two lines at every width, beside the sample's leak.
    private func dnaWithALongWeapon() throws -> ChessDNA {
        let sample = TrainSample(settled: true)
        let read = ChessDNA.make(games: sample.vault.games, puzzleStats: sample.puzzles.themeStats,
                                 puzzlesPlayed: sample.puzzles.progress.played)
        let leak = try XCTUnwrap(read.leak, "The sample player needs a leak to stand beside the weapon")
        XCTAssertLessThan(leak.headline.count, "Middlegame decisions in sharp positions".count)
        return ChessDNA(
            gamesRead: read.gamesRead,
            gamesCounted: read.gamesCounted,
            gamesImported: read.gamesImported,
            puzzlesRead: read.puzzlesRead,
            style: read.style,
            traits: read.traits,
            report: read.report,
            strengths: read.strengths,
            weapon: ChessDNA.Weapon(title: "Middlegame decisions in sharp positions", detail: "",
                                    symbol: "brain.head.profile", theme: ""),
            openings: read.openings,
            picks: read.picks,
            trends: read.trends,
            accuracyTrend: read.accuracyTrend
        )
    }

    func testWeaponAndLeakAreOneSizeOnHome() throws {
        let dna = try dnaWithALongWeapon()
        for width in [320.0, 390.0, 440.0] {
            for dark in [false, true] {
                let sizes = Sizes()
                let card = HomeAuroraDNA(dna: dna, palette: HomeAuroraPalette(dark: dark), action: {})
                    .padding(.horizontal, 16)
                try measure(card, width: width, into: sizes)
                expectOneSize(sizes.all, "Home's Chess DNA card, \(Int(width)) points wide, \(dark ? "night" : "day")")
            }
        }
    }

    func testWeaponAndLeakAreOneSizeOnLearn() throws {
        let dna = try dnaWithALongWeapon()
        for width in [320.0, 390.0, 440.0] {
            let sizes = Sizes()
            let card = ChessDNACard(dna: dna, theme: .named(.gilded))
                .padding(.horizontal, 16)
            try measure(card, width: width, into: sizes)
            expectOneSize(sizes.all, "Learn's Chess DNA card, \(Int(width)) points wide")
        }
    }

    /// Lays the view out in a real window of this width and keeps what the chips report.
    private func measure(_ view: some View, width: CGFloat, into sizes: Sizes) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        window.rootViewController = UIHostingController(rootView: ScrollView {
            view.onPreferenceChange(DNAChipSizes.self) { sizes.all = $0 }
        })
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        window.layoutIfNeeded()
        window.isHidden = true
    }

    private func expectOneSize(_ sizes: [CGSize], _ place: String, file: StaticString = #filePath, line: UInt = #line) {
        guard sizes.count == 2 else {
            XCTFail("\(place): expected a weapon and a leak, found \(sizes.count) chips", file: file, line: line)
            return
        }
        let (weapon, leak) = (sizes[0], sizes[1])
        XCTAssertEqual(weapon.height, leak.height, accuracy: 0.5,
                       "\(place): the weapon is \(weapon.height) points tall and the leak \(leak.height)",
                       file: file, line: line)
        XCTAssertEqual(weapon.width, leak.width, accuracy: 0.5,
                       "\(place): the weapon is \(weapon.width) points wide and the leak \(leak.width)",
                       file: file, line: line)
        // Two lines of words, not one squeezed line: the pair grew to the taller chip.
        XCTAssertGreaterThan(weapon.height, 50, "\(place): the weapon's two lines did not fit", file: file, line: line)
    }
}
