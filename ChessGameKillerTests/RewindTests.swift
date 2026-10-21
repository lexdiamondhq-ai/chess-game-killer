import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// A real game for Rewind: a Two Knights where White castles instead of
/// playing the Nxf7 fork, then throws a knight away on h7.
enum RewindSample {
    static let moves = [
        "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5", "d7d5", "e4d5", "f6d5",
        "e1g1", "f8e7", "f1e1", "e8g8", "g5h7", "g8h7", "d1h5", "h7g8", "c4d5", "d8d5", "b1c3", "d5d4",
    ]

    static func game(id: UUID = UUID(), date: Date = .now) -> SavedGame {
        var positions = [Position.standard.fen]
        var sans: [String] = []
        for uci in moves {
            let fen = positions.last!
            sans.append(Notation.san(of: uci, fen: fen)!)
            positions.append(TrainingChess.fen(after: [uci], from: fen)!)
        }
        func moment(_ ply: Int, _ grade: MoveReview.Grade, before: Double, after: Double,
                    best: String? = nil, line: [String] = []) -> SavedMoment {
            let fen = positions[ply - 1]
            return SavedMoment(
                ply: ply, grade: grade.rawValue, san: sans[ply - 1], uci: moves[ply - 1], byWhite: ply % 2 == 1,
                fenBefore: fen, fenAfter: positions[ply], best: best.flatMap { Notation.san(of: $0, fen: fen) },
                bestUCI: best, bestLine: line, reply: nil, before: before, after: after
            )
        }
        let moments = [
            moment(1, .best, before: 0.05, after: 0.05),
            moment(3, .best, before: 0.05, after: 0.06),
            moment(5, .good, before: 0.06, after: 0.05),
            moment(7, .best, before: 0.05, after: 0.22),
            moment(9, .best, before: 0.2, after: 0.2),
            moment(11, .mistake, before: 0.55, after: 0.12, best: "g5f7", line: ["g5f7", "e8f7", "d1f3", "f7e6"]),
            moment(13, .good, before: 0.12, after: 0.1),
            moment(15, .blunder, before: 0.1, after: -0.55, best: "d2d3", line: ["d2d3", "c8g4"]),
            moment(17, .good, before: -0.5, after: -0.5),
            moment(19, .inaccuracy, before: -0.45, after: -0.6, best: "h5h3", line: ["h5h3"]),
            moment(21, .good, before: -0.6, after: -0.62),
        ]
        return SavedGame(id: id, date: date, opponent: "Pulse", level: MatchController.Level.club.rawValue,
                         playerIsWhite: true, result: .loss, accuracy: 71, positions: positions, moves: sans,
                         moments: moments)
    }
}

final class RewindTests: XCTestCase {

    func testMomentsToRewriteAreTheCostlyOnesInOrder() {
        let game = RewindSample.game()
        XCTAssertEqual(game.toRewrite.map(\.ply), [11, 15, 19])
        XCTAssertEqual(game.leftToRewrite, 3)
        // Ng5 gained the most of the strong moves, so it is the one to be proud of.
        XCTAssertTrue(game.highlights.map(\.ply).contains(7))
        XCTAssertEqual(game.keyMoments.map(\.ply), game.keyMoments.map(\.ply).sorted())
    }

    func testTheLineIsFromThePlayersSide() {
        var game = RewindSample.game()
        XCTAssertEqual(game.lifeline.first?.value, 0)
        XCTAssertEqual(game.value(at: 15), -0.55, accuracy: 0.0001)
        // Between two graded moves the line runs straight.
        XCTAssertEqual(game.value(at: 14), (0.1 - 0.55) / 2, accuracy: 0.0001)
        // The last move was the opponent's, and the game was lost: the line ends at the bottom.
        XCTAssertEqual(game.lifeline.last?.ply, RewindSample.moves.count)
        XCTAssertEqual(game.lifeline.last?.value, -1)

        // The same game from Black's chair turns over.
        game = SavedGame(id: game.id, date: game.date, opponent: "Pulse", level: 2, playerIsWhite: false,
                         result: .win, accuracy: nil, positions: game.positions, moves: game.moves,
                         moments: game.moments.map { $0 })
        XCTAssertEqual(game.value(at: 15), 0.55, accuracy: 0.0001)
    }

    func testTheGhostLinePlaysTheEnginesMoves() {
        let moment = RewindSample.game().moments.first { $0.ply == 11 }!
        let ghost = SavedGame.ghostLine(for: moment)
        XCTAssertEqual(ghost.moves, ["Nxf7", "Kxf7", "Qf3+", "Ke6"])
        XCTAssertEqual(ghost.positions.count, 4)
        XCTAssertEqual(ghost.uci, ["g5f7", "e8f7", "d1f3", "f7e6"])
    }

    func testAGhostLineStopsAtAMoveThatDoesNotFit() {
        var moment = RewindSample.game().moments.first { $0.ply == 11 }!
        moment.bestLine = ["g5f7", "a1a8", "d1f3"]
        XCTAssertEqual(SavedGame.ghostLine(for: moment).moves, ["Nxf7"])
    }

    func testLeoNamesTheMissedFork() {
        let moment = RewindSample.game().moments.first { $0.ply == 11 }!
        let note = RewindNote.make(for: moment, library: nil)
        XCTAssertTrue(note.isLesson)
        XCTAssertEqual(note.tag, "Missed fork")
        XCTAssertEqual(note.skill, "forks")
        XCTAssertTrue(note.detail.contains("Nxf7"), note.detail)
        XCTAssertFalse(note.title.contains("{") || note.detail.contains("{"))
    }

    func testEveryMomentGetsWords() {
        for moment in RewindSample.game().moments {
            let note = RewindNote.make(for: moment, library: nil)
            XCTAssertFalse(note.title.isEmpty)
            XCTAssertFalse(note.detail.contains("{"), note.detail)
        }
    }

    func testGamesSurviveSaving() throws {
        let game = RewindSample.game()
        let data = try JSONEncoder().encode([game])
        XCTAssertEqual(try JSONDecoder().decode([SavedGame].self, from: data), [game])
    }

    @MainActor
    func testTheVaultUpdatesAGameAndKeepsWhatWasRewritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let vault = GameVault(fileURL: url)
        let id = UUID()
        var game = RewindSample.game(id: id)
        game.moments = Array(game.moments.prefix(6))
        vault.record(game)
        vault.markRewritten(11, in: id)
        XCTAssertEqual(vault.game(id)?.leftToRewrite, 0)

        // The last grades arrive: the same game, more moments, nothing lost.
        vault.record(RewindSample.game(id: id))
        XCTAssertEqual(vault.games.count, 1)
        XCTAssertEqual(vault.game(id)?.rewritten, [11])
        XCTAssertEqual(vault.game(id)?.leftToRewrite, 2)
        XCTAssertEqual(vault.rewrittenThisWeek(), 1)
        XCTAssertEqual(vault.leftThisWeek(), 2)

        let reloaded = try JSONDecoder().decode([SavedGame].self, from: Data(contentsOf: url))
        XCTAssertEqual(reloaded.first?.rewritten, [11])
    }

    @MainActor
    func testAMatchHandsOverItsGame() {
        let match = MatchController(engine: nil, sounds: nil)
        var setup = MatchController.Setup()
        setup.opponent = .friend
        match.start(setup, playSound: false)
        XCTAssertNil(match.savedGame())
        for uci in ["e2e4", "e7e5", "g1f3"] {
            let squares = Notation.squares(of: uci)!
            match.tap(squares.from)
            match.tap(squares.to)
        }
        let saved = match.savedGame()
        XCTAssertEqual(saved?.moves, ["e4", "e5", "Nf3"])
        XCTAssertEqual(saved?.positions.count, 4)
        XCTAssertEqual(saved?.result, .unfinished)
        XCTAssertEqual(saved?.opponent, "Friend")
    }
}

@MainActor
final class LineExplorerTests: XCTestCase {

    private func explorer(level: ReviewLevel = .club, engine: ChessEngine? = nil) -> LineExplorer {
        let moment = RewindSample.game().moments.first { $0.ply == 11 }!
        return LineExplorer(root: moment.fenBefore, line: moment.bestLine, player: .white, level: level, engine: engine)
    }

    func testTheLineStepsMoveByMove() {
        let line = explorer()
        XCTAssertEqual(line.steps.map(\.san), ["Nxf7", "Kxf7", "Qf3+", "Ke6"])
        XCTAssertEqual(line.cursor, 0)
        line.go(to: 1)
        XCTAssertEqual(line.current?.numbered, "6. Nxf7")
        XCTAssertEqual(line.ghostSquares, [Square("f7")])
        line.go(to: 2)
        // The king took the knight: the king is now the ghost on f7.
        XCTAssertEqual(line.ghostSquares, [Square("f7")])
        line.go(to: 3)
        XCTAssertEqual(line.ghostSquares, [Square("f7"), Square("f3")])
        line.go(to: 99)
        XCTAssertTrue(line.atEnd)
        line.stepBack()
        XCTAssertEqual(line.cursor, 3)
    }

    func testLeoSaysWhatEachMoveDoes() {
        let line = explorer()
        line.go(to: 1)
        XCTAssertTrue(line.sentence.contains("takes their pawn"), line.sentence)
        XCTAssertTrue(line.sentence.contains("queen and rook"), line.sentence)
        line.go(to: 2)
        XCTAssertTrue(line.sentence.hasPrefix("Kxf7: Their king takes your knight"), line.sentence)
        line.go(to: 3)
        XCTAssertTrue(line.sentence.contains("with check"), line.sentence)
    }

    func testCoachIsShorterThanGrandmaster() {
        let line = explorer(level: .grandmaster)
        XCTAssertEqual(line.steps.count, 4)
        line.go(to: 4)
        line.setLevel(.coach)
        XCTAssertEqual(line.steps.count, 4)
        XCTAssertEqual(ReviewLevel.coach.depth, 4)
        XCTAssertLessThan(ReviewLevel.club.depth, ReviewLevel.grandmaster.depth)
        XCTAssertFalse(ReviewLevel.club.showsBranches(playerToMove: true))
        XCTAssertTrue(ReviewLevel.club.showsBranches(playerToMove: false))
        XCTAssertFalse(ReviewLevel.coach.showsBranches(playerToMove: false))
    }

    func testYourOwnMoveStartsYourOwnLine() {
        let line = explorer()
        line.tap(Square("d2"))
        XCTAssertEqual(line.selected, Square("d2"))
        line.tap(Square("d4"))
        XCTAssertNil(line.selected)
        XCTAssertEqual(line.ownMoveAt, 0)
        XCTAssertEqual(line.steps.map(\.san), ["d4"])
        XCTAssertEqual(line.cursor, 1)
        // A move that isn't legal changes nothing.
        line.play("a1a8")
        XCTAssertEqual(line.steps.count, 1)
    }

    func testTheEngineRunsTheLineOnAndOffersBranches() async throws {
        let line = explorer(level: .club, engine: FakeEngine())
        line.go(to: 1)
        // Black to move after Nxf7: on Club the opponent's tries show.
        for _ in 0..<40 where line.isThinking || line.branches.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(line.evaluation)
        XCTAssertFalse(line.branches.isEmpty)
        XCTAssertLessThanOrEqual(line.branches.count, ReviewLevel.club.branches)
        XCTAssertFalse(line.branches.contains { $0.moves.first == "e8f7" }, "The line's own move isn't a branch")

        let branch = line.branches[0]
        line.follow(branch)
        XCTAssertEqual(line.cursor, 2)
        XCTAssertEqual(line.current?.uci, branch.moves.first)

        // At the end of a short line the engine carries it on to the level's depth.
        line.go(to: line.steps.count)
        for _ in 0..<40 where line.steps.count < ReviewLevel.club.depth {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(line.steps.count, ReviewLevel.club.depth)
    }
}

/// Pictures of Rewind at iPhone size, saved for CI like the game screen's.
@MainActor
final class RewindSnapshotTests: XCTestCase {

    func testRewindScreen() throws {
        let vault = GameVault()
        let game = RewindSample.game()
        vault.record(game)
        try snapshot("rewind-moment", RewindView(game: game, theme: .named(.pulse)).environment(vault))
    }

    func testRewindScreenOnALightBoard() throws {
        let vault = GameVault()
        let game = RewindSample.game()
        vault.record(game)
        try snapshot("rewind-blueprint", RewindView(game: game, theme: .named(.blueprint), startAt: 14).environment(vault))
    }

    func testDeepLine() throws {
        let vault = GameVault()
        let game = RewindSample.game()
        vault.record(game)
        UserDefaults.standard.set(ReviewLevel.grandmaster.rawValue, forKey: ReviewLevel.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: ReviewLevel.storageKey) }
        try snapshot("rewind-line", RewindView(game: game, theme: .named(.pulse), startAt: 10, opensLine: true,
                                               engine: FakeEngine()).environment(vault), wait: 3)
    }

    func testYourGames() throws {
        let vault = GameVault()
        vault.record(RewindSample.game(date: .now.addingTimeInterval(-86_400)))
        var won = RewindSample.game()
        won.result = .win
        won.rewritten = [11, 15, 19]
        vault.record(won)
        try snapshot("rewind-games", RewindGamesView(theme: .named(.neon)).environment(vault))
    }

    private func snapshot(_ name: String, _ view: some View, wait: TimeInterval = 1.5) throws {
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
