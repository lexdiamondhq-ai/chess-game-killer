import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Perfect Endgames: the offline referee, the judge falling back from the tablebase to
/// Stockfish, whole studies played against a scripted tablebase or engine, saved progress,
/// and the bundled library.
@MainActor
final class EndgameTests: XCTestCase {

    /// White: Ke6 and a pawn on e5. Black: Ke8. White to play and win: Kf6 wins, Kd5 doesn't.
    static let kingAndPawn = "4k3/8/4K3/4P3/8/8/8/8 w - - 0 1"
    /// White: Kg6, Qa1. Black: Kh8. Qa8 mates; Qa2 is stalemate.
    static let mateInOne = "7k/8/6K1/8/8/8/8/Q7 w - - 0 1"

    // MARK: The offline referee

    func testRefereeCatchesSlipsButNotNoise() {
        // A win thrown away, and one that holds.
        XCTAssertTrue(EngineReferee.isSlip(goal: .win, played: .centipawns(40), reference: .centipawns(500)))
        XCTAssertFalse(EngineReferee.isSlip(goal: .win, played: .centipawns(300), reference: .centipawns(500)))
        // A win Stockfish has scored low all along: a steady score is no slip.
        XCTAssertFalse(EngineReferee.isSlip(goal: .win, played: .centipawns(60), reference: .centipawns(70)))
        // With no score from before the move, the study's goal stands in for it.
        XCTAssertTrue(EngineReferee.isSlip(goal: .win, played: .centipawns(20), reference: nil))
        XCTAssertFalse(EngineReferee.isSlip(goal: .draw, played: .centipawns(-120), reference: nil))
        // A draw given away, and one Stockfish has been gloomy about all along.
        XCTAssertTrue(EngineReferee.isSlip(goal: .draw, played: .centipawns(-300), reference: .centipawns(0)))
        XCTAssertFalse(EngineReferee.isSlip(goal: .draw, played: .centipawns(-200), reference: .centipawns(-150)))
        // Mates leave no doubt.
        XCTAssertTrue(EngineReferee.isSlip(goal: .draw, played: .mate(-4), reference: .centipawns(0)))
        XCTAssertTrue(EngineReferee.isSlip(goal: .win, played: .mate(-1), reference: .mate(6)))
        XCTAssertFalse(EngineReferee.isSlip(goal: .win, played: .mate(5), reference: .mate(6)))
        XCTAssertTrue(EngineReferee.looksLost(.centipawns(-400)))
        XCTAssertFalse(EngineReferee.looksLost(.centipawns(-60)))
        XCTAssertTrue(EngineReferee.looksLost(.mate(-2)))
    }

    // MARK: The judge

    func testTheTablebaseJudgesWhenItCan() async {
        let tablebase = FakeTablebase(answers: [Self.kingAndPawn: .scripted("win", best: "e6f6", dtm: 29)])
        let judge = EndgameJudge(tablebase: tablebase, engine: FakeEngine())
        let assessment = await judge.assess(Self.kingAndPawn)
        XCTAssertEqual(assessment?.judge, .tablebase)
        XCTAssertEqual(assessment?.judge.label, "Judged by the tablebase")
        XCTAssertEqual(assessment?.outcome, 1)
        XCTAssertEqual(assessment?.best, "e6f6")
        XCTAssertEqual(assessment?.mate, 15)
        XCTAssertFalse(judge.isOffline)
    }

    func testStockfishStepsInWhenTheTablebaseIsOffline() async {
        let tablebase = FakeTablebase(fails: true)
        let judge = EndgameJudge(tablebase: tablebase, engine: FakeEngine(score: 350))
        let assessment = await judge.assess(Self.kingAndPawn)
        XCTAssertEqual(assessment?.judge, .engine(offline: true))
        XCTAssertEqual(assessment?.judge.label, "Judged by Stockfish, offline")
        XCTAssertEqual(assessment?.evaluation, .centipawns(350))
        XCTAssertNotNil(assessment?.best)
        XCTAssertTrue(judge.isOffline)
        // Once it has failed, the tablebase isn't kept waiting on until a fresh attempt.
        _ = await judge.assess(Self.kingAndPawn)
        let probes = await tablebase.probes
        XCTAssertEqual(probes, 1)
        judge.retryTablebase()
        XCTAssertFalse(judge.isOffline)
    }

    func testStockfishJudgesBeyondSevenPieces() async {
        let crowded = "6k1/ppp5/8/PPP5/8/8/8/6K1 w - - 0 1"
        let tablebase = FakeTablebase()
        let judge = EndgameJudge(tablebase: tablebase, engine: FakeEngine(score: 900))
        let assessment = await judge.assess(crowded)
        XCTAssertEqual(assessment?.judge, .engine(offline: false))
        XCTAssertEqual(assessment?.judge.label, "Judged by Stockfish")
        let probes = await tablebase.probes
        XCTAssertEqual(probes, 0)
        XCTAssertFalse(Tablebase.covers(crowded))
        XCTAssertTrue(Tablebase.covers(Self.kingAndPawn))
        XCTAssertFalse(Tablebase.covers("r3k3/8/8/8/8/8/8/4K3 b q - 0 1"), "No castling rights")
    }

    func testWithNeitherJudgeThereIsNoAnswer() async {
        let judge = EndgameJudge(tablebase: FakeTablebase(fails: true), engine: nil)
        let assessment = await judge.assess(Self.kingAndPawn)
        XCTAssertNil(assessment)
    }

    // MARK: Playing a study

    func testAGoodMoveIsAnsweredAndASlipIsTakenBack() async {
        let study = Self.study("kp", fen: Self.kingAndPawn, goal: .win)
        let tablebase = FakeTablebase(answers: [
            Self.kingAndPawn: .scripted("win", best: "e6f6"),
            "4k3/8/8/3KP3/8/8/8/8 b": .scripted("draw", best: "e8d7"),
            "4k3/8/5K2/4P3/8/8/8/8 b": .scripted("loss", best: "e8f8"),
        ])
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: tablebase, engine: nil), playsSounds: false)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        XCTAssertEqual(runner.judgeKind, .tablebase)
        XCTAssertEqual(runner.message, study.idea)

        play(runner, "e6d5")
        await waitUntil("Kd5 is judged") { runner.slips == 1 }
        XCTAssertEqual(runner.tone, .wrong)
        XCTAssertEqual(runner.message, "Kd5 lets the win slip to a draw. \(study.tip)")
        await waitUntil("Kd5 is taken back") { runner.phase == .playing }
        XCTAssertTrue(runner.board.fen.hasPrefix("4k3/8/4K3/4P3/8/8/8/8 w"), runner.board.fen)

        play(runner, "e6f6")
        await waitUntil("Kf6 is answered") { runner.phase == .playing && runner.movesMade == 1 }
        XCTAssertEqual(runner.board.piece(at: Square("f8"))?.kind, .king)
        XCTAssertEqual(runner.tone, .success)
        XCTAssertEqual(runner.slips, 1)
        XCTAssertFalse(runner.isClean)
    }

    func testMateWinsTheStudyAndIsRecorded() async {
        let study = Self.study("mate", fen: Self.mateInOne, goal: .win)
        let tablebase = FakeTablebase(answers: [Self.mateInOne: .scripted("win", best: "a1a8", dtm: 1)])
        let progress = EndgameProgress(studies: [study])
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: tablebase, engine: nil),
                                   progress: progress, playsSounds: false)
        XCTAssertTrue(runner.endsInMate)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        XCTAssertEqual(runner.mateLeft, 1)

        play(runner, "a1a2")
        await waitUntil("the stalemate is taken back") { runner.slips == 1 && runner.phase == .playing }

        play(runner, "a1a8")
        XCTAssertEqual(runner.phase, .won)
        XCTAssertEqual(runner.message, "Checkmate in 1 move: perfect play!")
        XCTAssertTrue(progress.isDone(study.id))
        XCTAssertEqual(progress.doneCount, 1)
        XCTAssertFalse(progress.isClean(study.id), "The stalemate was a slip")
    }

    func testAStalemateThrowsTheWinAway() async {
        let study = Self.study("mate", fen: Self.mateInOne, goal: .win)
        let tablebase = FakeTablebase(answers: [Self.mateInOne: .scripted("win", best: "a1a8", dtm: 1)])
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: tablebase, engine: nil), playsSounds: false)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        play(runner, "a1a2")
        await waitUntil("the stalemate is called") { runner.slips == 1 }
        XCTAssertEqual(runner.message, "Qa2 is stalemate, and the win is gone. \(study.tip)")
        XCTAssertEqual(runner.tone, .wrong)
        XCTAssertEqual(runner.phase, .thinking, "The board waits a moment before taking the move back")
        await waitUntil("the stalemate is taken back") { runner.phase == .playing }
        XCTAssertEqual(runner.board.piece(at: Square("a1"))?.kind, .queen)
    }

    func testADrawIsHeldForTheStudysMoves() async throws {
        let fen = "8/8/8/4k3/8/8/4P3/4K3 b - - 0 1"
        let study = Self.study("hold", fen: fen, goal: .draw, hold: 2)
        let progress = EndgameProgress(studies: [study])
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: FakeTablebase(otherwise: "draw"), engine: nil),
                                   progress: progress, playsSounds: false)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        XCTAssertEqual(runner.player, .black)
        play(runner, "e5e4")
        await waitUntil("the first move is answered") { runner.phase == .playing && runner.movesMade == 1 }
        play(runner, try XCTUnwrap(FakeEngine.legalMoves(fen: runner.board.fen).first))
        await waitUntil("the draw is held") { runner.phase == .held }
        XCTAssertEqual(runner.message, "Held! 2 moves against perfect play.")
        XCTAssertTrue(runner.isClean)
        XCTAssertTrue(progress.isClean(study.id))
    }

    func testOfflineStockfishJudgesAndDefends() async {
        let study = Self.study("kp", fen: Self.kingAndPawn, goal: .win)
        let engine = FakeEngine(scripted: [
            Self.fen(after: [], from: Self.kingAndPawn): [EngineLine(moves: ["e6f6"], evaluation: .mate(15))],
            Self.fen(after: ["e6d5"], from: Self.kingAndPawn): [EngineLine(moves: ["e8d7"], evaluation: .centipawns(0))],
            Self.fen(after: ["e6f6"], from: Self.kingAndPawn): [EngineLine(moves: ["e8f8"], evaluation: .centipawns(-650))],
        ])
        let judge = EndgameJudge(tablebase: FakeTablebase(fails: true), engine: engine)
        let runner = EndgameRunner(study: study, judge: judge, playsSounds: false)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        XCTAssertEqual(runner.judgeKind, .engine(offline: true))

        play(runner, "e6d5")
        await waitUntil("Kd5 is judged") { runner.slips == 1 }
        XCTAssertEqual(runner.message, "Kd5 lets the win slip to a draw. \(study.tip)")
        await waitUntil("Kd5 is taken back") { runner.phase == .playing }

        play(runner, "e6f6")
        await waitUntil("Kf6 is answered") { runner.phase == .playing && runner.movesMade == 1 }
        XCTAssertEqual(runner.board.piece(at: Square("f8"))?.kind, .king, "Stockfish plays the defence")
    }

    func testHintsShowThePieceThenTheMove() async {
        let study = Self.study("kp", fen: Self.kingAndPawn, goal: .win)
        let tablebase = FakeTablebase(answers: [Self.kingAndPawn: .scripted("win", best: "e6f6")])
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: tablebase, engine: nil), playsSounds: false)
        runner.start()
        await waitUntil("the study starts") { runner.phase == .playing }
        runner.hint()
        XCTAssertEqual(runner.marks.map(\.square), ["e6"])
        XCTAssertEqual(runner.message, "Look at your king.")
        runner.hint()
        XCTAssertEqual(runner.marks.map(\.square), ["e6", "f6"])
        XCTAssertEqual(runner.message, "Kf6 keeps the win.")
        XCTAssertEqual(runner.hintsUsed, 1)
        XCTAssertFalse(runner.isClean)
    }

    func testWithNoJudgeTheStudySaysSo() async {
        let study = Self.study("kp", fen: Self.kingAndPawn, goal: .win)
        let runner = EndgameRunner(study: study, judge: EndgameJudge(tablebase: FakeTablebase(fails: true), engine: nil),
                                   playsSounds: false)
        runner.start()
        await waitUntil("the study gives up") { runner.phase == .unavailable }
        XCTAssertTrue(runner.message.hasPrefix("Couldn't reach the tablebase"))
    }

    // MARK: Progress

    func testProgressCountsAndSuggestsTheNextStudy() {
        let studies = ["a", "b", "c"].map { Self.study($0, fen: Self.kingAndPawn, goal: .win) }
        let progress = EndgameProgress(studies: studies)
        XCTAssertEqual(progress.total, 3)
        XCTAssertEqual(progress.doneCount, 0)
        XCTAssertEqual(progress.nextUp?.id, "a")

        progress.record(studies[1], moves: 12, clean: true)
        XCTAssertTrue(progress.isDone("b"))
        XCTAssertTrue(progress.isClean("b"))
        XCTAssertEqual(progress.doneCount, 1)
        XCTAssertEqual(progress.doneCount(in: .mustKnow), 1)
        XCTAssertEqual(progress.next(after: studies[0])?.id, "c", "Done studies are skipped")
        XCTAssertEqual(progress.next(after: studies[2])?.id, "a", "and the list goes round")

        progress.record(studies[1], moves: 9, clean: false)
        XCTAssertEqual(progress.records["b"]?.completions, 2)
        XCTAssertEqual(progress.records["b"]?.bestMoves, 9)
        XCTAssertTrue(progress.isClean("b"), "A clean finish stays counted")

        progress.record(studies[0], moves: 5, clean: false)
        progress.record(studies[2], moves: 5, clean: false)
        XCTAssertTrue(progress.allDone)
        XCTAssertNil(progress.nextUp)
        XCTAssertEqual(progress.next(after: studies[2])?.id, "a", "Once all are done, simply the next")
    }

    func testDoneStudiesComeBackForReview() {
        let studies = ["a", "b"].map { Self.study($0, fen: Self.kingAndPawn, goal: .win) }
        let progress = EndgameProgress(studies: studies)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func day(_ days: Double) -> Date { start.addingTimeInterval(days * 86_400) }

        progress.record(studies[0], moves: 10, clean: true, now: start)
        XCTAssertTrue(progress.dueForReview(now: day(2)).isEmpty)
        XCTAssertEqual(progress.dueForReview(now: day(3.2)).map(\.id), ["a"])
        progress.record(studies[0], moves: 10, clean: true, now: day(3.2))
        XCTAssertTrue(progress.dueForReview(now: day(9)).isEmpty, "The second gap is a week")
        XCTAssertEqual(progress.dueForReview(now: day(10.4)).map(\.id), ["a"])
    }

    func testProgressSurvivesARelaunchAndOlderFiles() throws {
        let studies = ["a", "b"].map { Self.study($0, fen: Self.kingAndPawn, goal: .win) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("endgames-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        EndgameProgress.load(from: url, studies: studies).record(studies[0], moves: 7, clean: true)
        let reopened = EndgameProgress.load(from: url, studies: studies)
        XCTAssertTrue(reopened.isDone("a"))
        XCTAssertEqual(reopened.records["a"]?.bestMoves, 7)
        XCTAssertTrue(reopened.isClean("a"))

        // A file from another version: a record with few fields, one that can't be read, an extra key.
        let other = #"{"records": {"a": {"firstDone": 0}, "b": {"completions": "lots"}}, "version": 9}"#
        try Data(other.utf8).write(to: url)
        let older = EndgameProgress.load(from: url, studies: studies)
        XCTAssertTrue(older.isDone("a"))
        XCTAssertEqual(older.records["a"]?.completions, 1)
        XCTAssertFalse(older.isClean("a"))
        XCTAssertFalse(older.isDone("b"), "An unreadable record is skipped, and the rest kept")
    }

    // MARK: The library

    func testTheBundledLibrary() throws {
        let studies = bundledStudies
        XCTAssertGreaterThanOrEqual(studies.count, 20)
        XCTAssertEqual(Set(studies.map(\.id)).count, studies.count, "Ids are unique")
        for id in ["kq-k", "kr-k", "kp-k-6th", "kbb-k", "kp-k-opposition", "lucena", "philidor", "kq-kr", "kbn-k", "kr-kb"] {
            XCTAssertTrue(studies.contains { $0.id == id }, "\(id) is kept, so saved progress still counts")
        }
        for group in EndgameStudy.Group.allCases {
            XCTAssertGreaterThanOrEqual(studies.filter { $0.group == group }.count, 5, group.rawValue)
        }
        for study in studies {
            let position = try XCTUnwrap(Position(fen: study.fen), study.id)
            XCTAssertEqual(position.sideToMove, study.player, study.id)
            XCTAssertFalse(GameModel(position: position).isGameOver, study.id)
            XCTAssertTrue((1...3).contains(study.level), study.id)
            XCTAssertFalse(study.idea.isEmpty || study.tip.isEmpty, study.id)
        }
        XCTAssertTrue(studies.contains { $0.goal == .draw })
        XCTAssertEqual(studies.first { $0.id == "philidor" }?.goalText, "Black to play and draw")
        XCTAssertEqual(studies.first { $0.id == "lucena" }?.goalText, "White to play and win")
        XCTAssertEqual(studies.first { $0.id == "kbn-k" }?.levelName, "Hard")
    }

    // MARK: Helpers

    private var bundledStudies: [EndgameStudy] { GrandmasterContent.shared.endgames }

    static func study(_ id: String, fen: String, goal: EndgameStudy.Goal, hold: Int? = nil) -> EndgameStudy {
        let side: EndgameStudy.Side = fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
        return EndgameStudy(id: id, title: "Study \(id)", group: .mustKnow, level: 1, fen: fen, side: side, goal: goal,
                            idea: "The plan for \(id).", tip: "The tip for \(id).", hold: hold)
    }

    /// The position after `moves`, exactly as the study's board writes it.
    static func fen(after moves: [String], from start: String) -> String {
        let model = GameModel(position: Position(fen: start)!)
        for move in moves { model.playEngineMove(move) }
        return model.fen
    }

    private func play(_ runner: EndgameRunner, _ uci: String) {
        runner.tap(Square(String(uci.prefix(2))))
        runner.tap(Square(String(uci.dropFirst(2).prefix(2))))
    }

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
}

/// A tablebase that answers from a script, or fails like a phone with no signal.
actor FakeTablebase: TablebaseProbing {
    struct Offline: Error {}

    private let answers: [String: TablebaseResult]
    /// The result ("win", "draw" or "loss") for positions not in the script; nil fails them.
    private let otherwise: String?
    private let fails: Bool
    private(set) var probes = 0

    init(answers: [String: TablebaseResult] = [:], otherwise: String? = nil, fails: Bool = false) {
        self.answers = Dictionary(answers.map { (Self.key($0.key), $0.value) }) { first, _ in first }
        self.otherwise = otherwise
        self.fails = fails
    }

    func probe(_ fen: String) async throws -> TablebaseResult {
        probes += 1
        if fails { throw Offline() }
        if let answer = answers[Self.key(fen)] { return answer }
        guard let otherwise else { throw Offline() }
        return .scripted(otherwise, best: FakeEngine.legalMoves(fen: fen).first)
    }

    /// The pieces and the side to move: the move counters don't change the answer.
    private static func key(_ fen: String) -> String {
        fen.split(separator: " ").prefix(2).joined(separator: " ")
    }
}

extension TablebaseResult {
    /// An answer for tests: the result for the side to move, its best move and plies to mate.
    static func scripted(_ category: String, best: String?, dtm: Int? = nil) -> TablebaseResult {
        let after = ["win": "loss", "loss": "win"][category] ?? category
        let moves = best.map { [Move(uci: $0, san: $0, category: after, dtm: nil)] } ?? []
        return TablebaseResult(category: category, dtm: dtm, checkmate: false, stalemate: false, moves: moves)
    }
}

// MARK: - Screens

/// The endgame screen at iPhone size: playing with the tablebase judging, offline with
/// Stockfish judging, and won; and the playing screen on a small phone. When SNAPSHOT_DIR is
/// set the pictures are saved there.
@MainActor
final class EndgameSnapshotTests: XCTestCase {

    func testEndgameScreens() async throws {
        let library = GrandmasterContent.shared.endgames
        let lucena = try XCTUnwrap(library.first { $0.id == "lucena" })
        let philidor = try XCTUnwrap(library.first { $0.id == "philidor" })
        let queen = try XCTUnwrap(library.first { $0.id == "kq-k" })

        // Playing: the tablebase judges, and it's the player's move.
        let playing = EndgameRunner(study: lucena, judge: EndgameJudge(
            tablebase: FakeTablebase(answers: [lucena.fen: .scripted("win", best: "c1c4")]), engine: nil), playsSounds: false)
        try await snapshot(playing, "train-endgames-playing")

        // Offline: Stockfish judges and defends, one move into holding the draw.
        let afterRook = EndgameTests.fen(after: ["a6b6"], from: philidor.fen)
        let stockfish = FakeEngine(scripted: [afterRook: [EngineLine(moves: ["h1h7"], evaluation: .centipawns(0))]])
        let offline = EndgameRunner(study: philidor, judge: EndgameJudge(tablebase: FakeTablebase(fails: true), engine: stockfish),
                                    playsSounds: false)
        try await snapshot(offline, "train-endgames-offline", moves: ["a6b6"])

        // Won: the queen study from a mate in one, played perfectly.
        let mate = EndgameStudy(id: queen.id, title: queen.title, group: queen.group, level: queen.level,
                                fen: EndgameTests.mateInOne, side: .white, goal: .win, idea: queen.idea, tip: queen.tip, hold: nil)
        let won = EndgameRunner(study: mate, judge: EndgameJudge(
            tablebase: FakeTablebase(answers: [mate.fen: .scripted("win", best: "a1a8", dtm: 1)]), engine: nil), playsSounds: false)
        try await snapshot(won, "train-endgames-won", moves: ["a1a8"], until: .won)

        // The longest plan in the library, on a 375 by 667 screen.
        let longest = try XCTUnwrap(library.max { $0.idea.count < $1.idea.count })
        let small = EndgameRunner(study: longest, judge: EndgameJudge(
            tablebase: FakeTablebase(answers: [longest.fen: .scripted(longest.goal == .win ? "win" : "draw", best: nil)]),
            engine: nil), playsSounds: false)
        try await snapshot(small, "train-endgames-playing-small", size: CGSize(width: 375, height: 667))
    }

    // MARK: Drawing

    /// Starts the study, plays `moves`, waits for `phase` and saves the screen.
    private func snapshot(_ runner: EndgameRunner, _ name: String, moves: [String] = [],
                          until phase: EndgameRunner.Phase = .playing, size: CGSize? = nil) async throws {
        runner.start()
        try await waitUntil { runner.phase == .playing }
        for move in moves {
            runner.tap(Square(String(move.prefix(2))))
            runner.tap(Square(String(move.dropFirst(2).prefix(2))))
        }
        try await waitUntil { runner.phase == phase && runner.movesMade == moves.count }
        let window = try show(EndgameView(runner: runner, theme: .named(.gilded)), size: size)
        try save(window, name)
        window.isHidden = true
    }

    private struct NeverGotThere: Error {}

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw NeverGotThere() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func show(_ view: some View, size: CGSize? = nil, wait: TimeInterval = 3) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
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
}
