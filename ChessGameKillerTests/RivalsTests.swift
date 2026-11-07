import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// A crowd with scripted answers, and nothing at all for positions it wasn't given.
final class FakeCrowdBook: CrowdBookSource, @unchecked Sendable {
    private let positions: [String: CrowdPosition]
    private(set) var asked: [String] = []

    init(_ positions: [String: CrowdPosition] = [:]) {
        self.positions = positions
    }

    func position(fen: String, source: CrowdSource) async -> CrowdPosition? {
        asked.append(fen)
        return positions[fen]
    }
}

/// The Crowd's moves.
@MainActor
final class RivalsTests: XCTestCase {

    private func waitUntil(_ what: String, timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Timed out waiting until \(what)")
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private let opening = CrowdPosition(moves: [
        .init(uci: "e2e4", san: "e4", games: 620),
        .init(uci: "d2d4", san: "d4", games: 210),
        .init(uci: "c2c4", san: "c4", games: 90),
        .init(uci: "b2b3", san: "b3", games: 20),
    ])

    // MARK: The Crowd

    func testTheExplorersReplyIsRead() throws {
        let json = """
        {"white":10,"draws":5,"black":5,"moves":[
          {"uci":"e2e4","san":"e4","averageRating":1612,"white":6,"draws":2,"black":2,"game":null},
          {"uci":"d2d4","san":"d4","averageRating":1600,"white":4,"draws":3,"black":3,"game":null}
        ],"topGames":[],"opening":null}
        """
        let position = try XCTUnwrap(CrowdBook.parse(Data(json.utf8)))
        XCTAssertEqual(position.moves.map(\.san), ["e4", "d4"])
        XCTAssertEqual(position.moves.map(\.games), [10, 10])
        XCTAssertEqual(position.games, 20)
        XCTAssertNil(CrowdBook.parse(Data("not json".utf8)))
    }

    func testTheCrowdPlaysInProportionToItsVotes() throws {
        let source = CrowdSource.lichess(ratings: [1600])
        let first = try XCTUnwrap(CrowdBook.vote(from: opening, source: source, pick: 0))
        XCTAssertEqual(first.san, "e4")
        XCTAssertEqual(first.percent, "66%")
        XCTAssertEqual(first.top.map(\.san), ["e4", "d4", "c4"])
        let late = try XCTUnwrap(CrowdBook.vote(from: opening, source: source, pick: 0.95))
        XCTAssertEqual(late.san, "c4", "a move a few players chose still comes now and then")
        // b3, at 2%, is never the crowd's move.
        for pick in stride(from: 0.0, to: 1.0, by: 0.01) {
            XCTAssertNotEqual(CrowdBook.vote(from: opening, source: source, pick: pick)?.san, "b3")
        }
    }

    func testARarePositionIsLeftToStockfish() {
        let rare = CrowdPosition(moves: [.init(uci: "e2e4", san: "e4", games: 12)])
        XCTAssertNil(CrowdBook.vote(from: rare, source: .lichess(ratings: [1000]), pick: 0))
        XCTAssertNotNil(CrowdBook.vote(from: rare, source: .masters, pick: 0), "masters' games are rarer, and enough")
    }

    func testAWeightLeansTheDraw() throws {
        let lean: (String) -> Double = { $0 == "c4" ? 20 : 1 }
        let vote = try XCTUnwrap(CrowdBook.vote(from: opening, source: .masters, pick: 0.5, weight: lean))
        XCTAssertEqual(vote.san, "c4")
    }

    func testTheExplorerIsAskedForTheRightCrowd() throws {
        let fen = Position.standard.fen
        let lichess = try XCTUnwrap(CrowdBook.url(fen: fen, source: .lichess(ratings: [2000])))
        XCTAssertEqual(lichess.host(), "explorer.lichess.ovh")
        XCTAssertEqual(lichess.path(), "/lichess")
        XCTAssertTrue(lichess.absoluteString.contains("ratings=2000"))
        let masters = try XCTUnwrap(CrowdBook.url(fen: fen, source: .masters))
        XCTAssertEqual(masters.path(), "/masters")
        XCTAssertEqual(MatchController.Level.grandmaster.crowdSource, .masters)
    }

    func testTheCrowdMovesAndShowsItsVote() async {
        let book = FakeCrowdBook([Position.standard.fen: opening])
        let engine = FakeEngine()
        let match = MatchController(engine: engine, sounds: nil)
        match.crowdBook = book
        match.chance = { 0 }
        match.start(.init(opponent: .computer, playerColor: .black, level: .club))
        await waitUntil("the crowd opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.moves, ["e4"])
        XCTAssertEqual(match.crowdVote?.san, "e4")
        let requests = await engine.moveRequests
        XCTAssertEqual(requests, 0, "the crowd's own move, not Stockfish's")
    }

    func testWithNoCrowdStockfishPlaysAndTheCrowdIsNotAskedAgain() async {
        let book = FakeCrowdBook()
        let engine = FakeEngine()
        let match = MatchController(engine: engine, sounds: nil)
        match.crowdBook = book
        match.start(.init(opponent: .computer, playerColor: .black, level: .club))
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        XCTAssertNil(match.crowdVote)
        let requests = await engine.moveRequests
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(book.asked.count, 1)
    }

    func testSavedGamesKnowTheirCrowd() {
        XCTAssertEqual(Rival.named("1000s")?.level, .beginner)
        XCTAssertEqual(Rival.named("The Masters")?.level, .grandmaster)
        XCTAssertNil(Rival.named("grudge"), "the Grudge is retired")
        for rival in Rival.all {
            XCTAssertNotNil(UIImage(named: rival.portraitName), "\(rival.portraitName) is missing")
            XCTAssertNotNil(UIImage(named: rival.glowName), "\(rival.glowName) is missing")
        }
    }

    // MARK: Pictures

    /// The New Game sheet with The Crowd.
    func testPictures() throws {
        try snapshot("crowd-new-game", view: Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) {
            NewGameSheet(theme: .named(.gilded), start: { _ in })
        }, wait: 3)
    }

    private func snapshot(_ name: String, view: some View, wait: TimeInterval) throws {
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
