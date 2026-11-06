import ChessKit
import XCTest
@testable import ChessGameKiller

/// A stand-in for Maia that plays a scripted move and remembers what it was asked.
final class FakeHumanMoves: HumanMovePicking, @unchecked Sendable {
    private let answer: String?
    private(set) var asked: [(fens: [String], legal: [String], rating: Int)] = []

    init(answer: String?) { self.answer = answer }

    func move(fens: [String], legal: [String], rating: Int, pick: Double) async -> String? {
        asked.append((fens, legal, rating))
        return answer
    }
}

/// Maia, the human-move networks the crowd plays from past its book.
@MainActor
final class MaiaTests: XCTestCase {

    private struct Reference: Decodable {
        let name: String
        let fens: [String]
        let top: [[Entry]]

        enum Entry: Decodable {
            case move(String), chance(Double)
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let move = try? value.decode(String.self) { self = .move(move) } else { self = .chance(try value.decode(Double.self)) }
            }
        }

        var moves: [(move: String, chance: Double)] {
            top.compactMap { pair in
                guard pair.count == 2, case .move(let move) = pair[0], case .chance(let chance) = pair[1] else { return nil }
                return (move, chance)
            }
        }
    }

    /// The numbers `scripts/maia/reference.py` worked out with numpy and python-chess.
    private func references() throws -> [String: [Reference]] {
        let url = try XCTUnwrap(Bundle(for: MaiaTests.self).url(forResource: "maia-reference", withExtension: "json"))
        return try JSONDecoder().decode([String: [Reference]].self, from: Data(contentsOf: url))
    }

    func testEveryNetworkIsBundled() {
        for rating in Maia.ratings {
            XCTAssertNotNil(MaiaNetwork(rating: rating), "maia-\(rating).bin is missing or unreadable")
        }
    }

    func testAFileThatIsNotANetworkIsTurnedDown() {
        XCTAssertNil(MaiaNetwork(data: Data("not a network".utf8)))
        XCTAssertNil(MaiaNetwork(data: Data()))
    }

    /// The Swift network gives the same chances as the reference, move by move, for every rating.
    func testMatchesTheReference() throws {
        let all = try references()
        XCTAssertEqual(Set(all.keys), Set(Maia.ratings.map(String.init)))
        for (rating, cases) in all {
            let network = try XCTUnwrap(MaiaNetwork(rating: Int(rating)!))
            for reference in cases {
                let fen = try XCTUnwrap(reference.fens.last)
                let game = GameModel(position: try XCTUnwrap(Position(fen: fen)))
                let ours = MaiaMoves.probabilities(fens: reference.fens, legal: game.legalEngineMoves(), network: network)
                let label = "\(rating), \(reference.name)"
                XCTAssertFalse(ours.isEmpty, label)
                XCTAssertEqual(ours.reduce(0) { $0 + $1.chance }, 1, accuracy: 1e-6, label)
                let expected = reference.moves
                XCTAssertEqual(expected.count, 5, label)
                for (move, chance) in expected {
                    let found = ours.first { $0.move == move }
                    XCTAssertEqual(found?.chance ?? -1, chance, accuracy: 0.002, "\(label): \(move)")
                }
                if expected.count > 1, expected[0].chance - expected[1].chance > 0.01 {
                    XCTAssertEqual(ours.first?.move, expected[0].move, "\(label): the favourite")
                }
            }
        }
    }

    /// From the start, players of every rating mostly open with e4 or d4.
    func testOpensLikeAPerson() throws {
        let start = Position.standard.fen
        for rating in Maia.ratings {
            let network = try XCTUnwrap(MaiaNetwork(rating: rating))
            let moves = MaiaMoves.probabilities(fens: [start], legal: GameModel().legalEngineMoves(), network: network)
            XCTAssertEqual(moves.count, 20)
            let central = moves.filter { ["e2e4", "d2d4"].contains($0.move) }.reduce(0) { $0 + $1.chance }
            XCTAssertGreaterThan(central, 0.7, "\(rating)")
        }
    }

    /// Castling is scored as the king taking its own rook, as lc0 has it; Black's moves are seen
    /// from Black's side of the board.
    func testMovesAreScoredWhereLc0ScoresThem() throws {
        let white = try XCTUnwrap(MaiaBoard(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let black = try XCTUnwrap(MaiaBoard(fen: "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1"))
        // e1h1 is "east, 3 squares" from e1: plane 2 * 7 + 2, square 4.
        XCTAssertEqual(MaiaMoves.policyIndex(of: "e1g1", on: white), (2 * 7 + 2) * 64 + 4)
        XCTAssertEqual(MaiaMoves.policyIndex(of: "e1c1", on: white), (6 * 7 + 3) * 64 + 4)
        XCTAssertEqual(MaiaMoves.policyIndex(of: "e8g8", on: black), MaiaMoves.policyIndex(of: "e1g1", on: white))
        XCTAssertEqual(MaiaMoves.policyIndex(of: "a8a1", on: black), MaiaMoves.policyIndex(of: "a1a8", on: white))
        let promotion = try XCTUnwrap(MaiaBoard(fen: "8/1P4k1/8/8/8/8/6K1/8 w - - 0 1"))
        // A knight promotion is the plain move north; the other three have planes of their own.
        XCTAssertEqual(MaiaMoves.policyIndex(of: "b7b8n", on: promotion), MaiaMoves.policyIndex(of: "b7b8", on: promotion))
        XCTAssertEqual(MaiaMoves.policyIndex(of: "b7b8q", on: promotion), (64 + 1 * 3 + 2) * 64 + 6 * 8 + 1)
        XCTAssertNil(MaiaMoves.policyIndex(of: "b7d4", on: promotion), "not a move any piece makes")
    }

    func testAPawnOnTheLastRankIsOfferedAsEveryPromotion() throws {
        let network = try XCTUnwrap(MaiaNetwork(rating: 1600))
        let fen = "8/1P4k1/8/8/8/8/6K1/8 w - - 0 1"
        let legal = GameModel(position: try XCTUnwrap(Position(fen: fen))).legalEngineMoves()
        let moves = MaiaMoves.probabilities(fens: [fen], legal: legal, network: network)
        XCTAssertTrue(Set(["b7b8q", "b7b8r", "b7b8b", "b7b8n"]).isSubset(of: Set(moves.map(\.move))))
        XCTAssertEqual(moves.first?.move, "b7b8q")
    }

    /// The pick draws among the moves people really play, and never one they almost never would.
    func testChoosesAmongTheLikelyMoves() {
        let moves: [(move: String, chance: Double)] = [("e2e4", 0.6), ("d2d4", 0.3), ("c2c4", 0.07), ("g2g4", 0.03)]
        XCTAssertEqual(MaiaMoves.choose(from: moves, pick: 0), "e2e4")
        XCTAssertEqual(MaiaMoves.choose(from: moves, pick: 0.7), "d2d4")
        XCTAssertEqual(MaiaMoves.choose(from: moves, pick: 0.99), "c2c4")
        XCTAssertEqual(MaiaMoves.choose(from: moves, pick: 1), "c2c4", "g2g4, at 3%, is never played")
        XCTAssertNil(MaiaMoves.choose(from: [], pick: 0.5))
    }

    /// Repeated positions are marked, so the network can tell a shuffle from a fresh position.
    func testRepetitionsAreMarked() throws {
        let game = GameModel()
        for move in ["g1f3", "g8f6", "f3g1", "f6g8"] { XCTAssertTrue(game.playEngineMove(move)) }
        let planes = try XCTUnwrap(MaiaInput.planes(fens: game.fenHistory))
        XCTAssertEqual(game.fenHistory.count, 5)
        XCTAssertEqual(planes[12 * 64], 1, "the position now is the start again")
        XCTAssertEqual(planes[(13 + 12) * 64], 0, "one move ago it was new")
        XCTAssertEqual(planes[(4 * 13 + 12) * 64], 0, "the start itself was new")
        XCTAssertEqual(planes[5 * 13 * 64 ..< 8 * 13 * 64].reduce(0, +), 0, "nothing before the game began")
        XCTAssertEqual(planes[111 * 64], 1)
    }

    // MARK: In a game

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

    func testPastTheBookTheCrowdPlaysMaiasMove() async {
        let engine = FakeEngine()
        let human = FakeHumanMoves(answer: "d2d4")
        let match = MatchController(engine: engine, sounds: nil)
        match.humanMoves = human
        match.start(.init(opponent: .computer, playerColor: .black, level: .casual))
        await waitUntil("the crowd opens") { match.game.plyCount == 1 }
        XCTAssertEqual(match.game.moves, ["d4"])
        XCTAssertEqual(human.asked.first?.rating, 1200)
        XCTAssertEqual(human.asked.first?.fens, [Position.standard.fen])
        XCTAssertEqual(human.asked.first?.legal.count, 20)
        let requests = await engine.moveRequests
        XCTAssertEqual(requests, 0, "Maia's move, not Stockfish's")
    }

    func testWithNoMoveFromMaiaStockfishPlays() async {
        let engine = FakeEngine()
        let match = MatchController(engine: engine, sounds: nil)
        match.humanMoves = FakeHumanMoves(answer: nil)
        match.start(.init(opponent: .computer, playerColor: .black, level: .club))
        await waitUntil("the computer opens") { match.game.plyCount == 1 }
        let requests = await engine.moveRequests
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(match.engineFailed)
    }

    /// The Masters play full Stockfish past their book, and the Grudge searches at its own strength.
    func testTheMastersAndTheGrudgeKeepStockfish() async {
        var grudge = MatchController.Setup(opponent: .computer, playerColor: .black, level: .club)
        grudge.grudge = true
        grudge.grudgeSkill = 12
        let masters = MatchController.Setup(opponent: .computer, playerColor: .black, level: .grandmaster)
        for setup in [grudge, masters] {
            XCTAssertNil(setup.humanRating)
            let engine = FakeEngine()
            let human = FakeHumanMoves(answer: "d2d4")
            let match = MatchController(engine: engine, sounds: nil)
            match.humanMoves = human
            match.start(setup)
            await waitUntil("the computer opens") { match.game.plyCount == 1 }
            XCTAssertTrue(human.asked.isEmpty)
            let requests = await engine.moveRequests
            XCTAssertEqual(requests, 1)
        }
    }

    func testEachCrowdHasTheNetworkForItsRating() {
        let ratings = MatchController.Level.allCases.map { MatchController.Setup(level: $0).humanRating }
        XCTAssertEqual(ratings, [1100, 1200, 1600, 1900, nil])
        for case let rating? in ratings { XCTAssertTrue(Maia.ratings.contains(rating)) }
        XCTAssertEqual(Maia.rating(nearest: 1000), 1100)
        XCTAssertEqual(Maia.rating(nearest: 2000), 1900)
    }

    /// Played for real: Maia at 1600 answers 1. e4 with a sensible reply, quickly.
    func testTheRealPlayerAnswersQuickly() async throws {
        let game = GameModel()
        XCTAssertTrue(game.playEngineMove("e2e4"))
        let clock = ContinuousClock()
        let started = clock.now
        let move = await MaiaPlayer.shared.move(fens: game.fenHistory, legal: game.legalEngineMoves(), rating: 1600, pick: 0)
        XCTAssertLessThan(clock.now - started, .seconds(2))
        XCTAssertTrue(["e7e5", "c7c5", "e7e6", "c7c6", "d7d5"].contains(try XCTUnwrap(move)), "\(move ?? "nil")")
    }
}
