import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Your army on the Aurora home: the champion and the army's quest (Alex, 2026-11-12: "A and C
/// together"). The card's pictures are saved to SNAPSHOT_DIR as army-home-*.png.
@MainActor
final class ArmyQuestTests: XCTestCase {

    private static func record(xp: Int, name: String? = nil, games: Int = 12) -> PieceRecord {
        var record = PieceRecord()
        record.games = games
        record.xp = xp
        record.name = name
        return record
    }

    /// A few weeks in: a named knight leads, a few more are named, the rest still recruits.
    private static func army(holding held: ArmySlot? = nil, by captor: MatchController.Level = .casual) -> ArmyStore {
        var army = ArmyStore.Army()
        for slot in ArmySlot.allCases { army.records[slot] = record(xp: 14) }
        var kestrel = record(xp: 212, name: "Kestrel")
        kestrel.captures = 41
        kestrel.survivedWins = 12
        kestrel.mates = 2
        kestrel.escapes = 1
        army.records[.kingsKnight] = kestrel
        army.records[.queen] = record(xp: 160, name: "Vesper")
        army.records[.queensBishop] = record(xp: 64, name: "Sable")
        army.records[.ePawn] = record(xp: 21)
        if let held { army.captives[held] = captor.rawValue }
        return ArmyStore(army: army)
    }

    // MARK: The champion

    func testTheChampionIsTheMostExperiencedFreePiece() {
        XCTAssertNil(ArmyStore().champion, "No champion before any game")
        XCTAssertEqual(Self.army().champion, .kingsKnight)
        // Held by a rival, it can't stand on the card: the next one does.
        XCTAssertEqual(Self.army(holding: .kingsKnight).champion, .queen)
    }

    func testTheChampionsDeedsAreItsProudestFirst() {
        let army = Self.army()
        XCTAssertEqual(army.deeds(of: .kingsKnight), ["2 checkmates", "Took 41 pieces"])
        XCTAssertEqual(army.deeds(of: .queen), ["12 games played"])
        XCTAssertEqual(army.rankProgress(of: .kingsKnight), Double(212 - 100) / Double(300 - 100), accuracy: 0.001)
        var legend = ArmyStore.Army()
        legend.records[.queen] = Self.record(xp: 400, name: "Iris")
        XCTAssertEqual(ArmyStore(army: legend).rankProgress(of: .queen), 1)
    }

    // MARK: The quest

    func testNoQuestBeforeTheFirstGame() {
        XCTAssertNil(ArmyQuest.of(ArmyStore(), next: .club))
    }

    func testAHeldPieceComesFirst() throws {
        let army = Self.army(holding: .queensBishop, by: .casual)
        let quest = try XCTUnwrap(ArmyQuest.of(army, next: .club))
        XCTAssertEqual(quest.slot, .queensBishop)
        XCTAssertEqual(quest.rival, .casual, "The rescue is against the rival holding it, not the one up next")
        XCTAssertEqual(quest.line(army), "\(MatchController.Level.casual.rival.name) holds Sable, your queenside bishop.")
        XCTAssertEqual(quest.button(army), "Win to free Sable")
    }

    func testOtherwiseThePieceNearestItsNextRank() throws {
        let army = Self.army()
        let quest = try XCTUnwrap(ArmyQuest.of(army, next: .club))
        // The e-pawn is 4 XP from Veteran, closer than anyone else is to their next rank.
        XCTAssertEqual(quest.slot, .ePawn)
        XCTAssertEqual(quest.kind, .rankUp(next: .veteran, xpLeft: 4, rival: .club))
        XCTAssertEqual(quest.line(army), "Your e-pawn is 4 XP from Veteran. Win with it standing.")
        XCTAssertEqual(quest.button(army), "Play \(MatchController.Level.club.rival.shortName)")
    }

    func testANamedPieceIsCalledByItsName() throws {
        var army = ArmyStore.Army()
        army.records[.queen] = Self.record(xp: 290, name: "Vesper")
        army.records[.kingsRook] = Self.record(xp: 60, name: "Flint")
        let store = ArmyStore(army: army)
        let quest = try XCTUnwrap(ArmyQuest.of(store, next: .expert))
        XCTAssertEqual(quest.line(store), "Vesper is 10 XP from Legend. Win with Vesper standing.")
    }

    // MARK: Pictures

    func testTheArmyCardOnHome() throws {
        let shots: [(String, ArmyStore)] = [
            ("army-home-1-quest", Self.army()),
            ("army-home-2-rescue", Self.army(holding: .queensBishop)),
            ("army-home-3-fresh", ArmyStore()),
        ]
        for dark in [false, true] {
            let palette = HomeAuroraPalette(dark: dark)
            for (name, army) in shots {
                let card = HomeAuroraArmy(army: army, color: .white, pieceTheme: .named(.gilded), nextRival: .club,
                                          palette: palette, open: {}, play: { _ in })
                let page = VStack(spacing: 0) {
                    HomeAuroraSection(title: "Your army", palette: palette, note: "37 games together")
                    card.padding(.horizontal, 16)
                    HomeAuroraSignOff(palette: palette)
                        .padding(.top, 22)
                    Spacer()
                }
                .padding(.top, 80)
                .background(palette.sheet.ignoresSafeArea())
                .background(palette.bg.ignoresSafeArea())
                try snapshot("\(name)-\(dark ? "dark" : "light")", view: page)
            }
        }
    }

    private func snapshot(_ name: String, view: some View, wait: TimeInterval = 1) throws {
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
        window.isHidden = true
    }
}
