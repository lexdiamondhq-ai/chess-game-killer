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

/// The Crowd's moves and the Grudge's memory.
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

    func testTheGrudgeLeansTowardLinesYouLost() throws {
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

    func testTheGrudgeSearchesAtItsOwnStrength() async {
        let engine = FakeEngine()
        let match = MatchController(engine: engine, sounds: nil)
        var setup = MatchController.Setup(opponent: .computer, playerColor: .black, level: .club)
        setup.grudge = true
        setup.grudgeSkill = 12
        match.start(setup)
        await waitUntil("the Grudge opens") { match.game.plyCount == 1 }
        let searches = await engine.moveSearches
        XCTAssertEqual(searches.first, FakeEngine.MoveSearch(skill: 12, depth: 5, thinkTimeMs: 350))
        XCTAssertEqual(match.opponentName, "Your Grudge")
    }

    // MARK: The Grudge

    private func store() -> GrudgeStore {
        let defaults = UserDefaults(suiteName: "RivalsTests")!
        defaults.removePersistentDomain(forName: "RivalsTests")
        return GrudgeStore(defaults: defaults)
    }

    func testTheFirstLossToACrowdWakesTheGrudgeOnce() {
        let grudges = store()
        XCTAssertFalse(grudges.isBorn)
        XCTAssertTrue(grudges.crowdWon(level: .club, moves: [], playerColor: .white, positions: []))
        XCTAssertTrue(grudges.unseen)
        XCTAssertEqual(grudges.record?.itsWins, 1)
        XCTAssertEqual(grudges.record?.skill, MatchController.Level.club.skill + 1)
        XCTAssertEqual(grudges.record?.mood, .smug)
        XCTAssertFalse(grudges.crowdWon(level: .expert, moves: [], playerColor: .white, positions: []), "only ever one")
        grudges.markSeen()
        XCTAssertFalse(grudges.unseen)
        // It is still there next launch.
        let again = GrudgeStore(defaults: UserDefaults(suiteName: "RivalsTests")!)
        XCTAssertEqual(again.record?.itsWins, 1)
        XCTAssertEqual(again.record?.skill, grudges.record?.skill)
    }

    func testYourWinsScarItAndTheTenthRebuildsIt() {
        let grudges = store()
        grudges.crowdWon(level: .casual, moves: [], playerColor: .white, positions: [])
        grudges.recordGame(.youWon, moves: [], playerColor: .white, positions: [])
        XCTAssertEqual(grudges.record?.scars, 1)
        XCTAssertEqual(grudges.record?.mood, .even)
        grudges.recordGame(.youWon, moves: [], playerColor: .white, positions: [])
        XCTAssertEqual(grudges.record?.mood, .rattled)
        for _ in 0..<8 { grudges.recordGame(.youWon, moves: [], playerColor: .white, positions: []) }
        XCTAssertEqual(grudges.record?.scars, 0, "ten scars: rebuilt")
        XCTAssertEqual(grudges.record?.form, 1)
        XCTAssertEqual(grudges.record?.mood, .respect)
        XCTAssertEqual(grudges.record?.score, "10 – 1")
    }

    func testEndingItsStreakMakesItFurious() {
        let grudges = store()
        grudges.crowdWon(level: .club, moves: [], playerColor: .white, positions: [])
        grudges.recordGame(.itWon, moves: [], playerColor: .white, positions: [])
        grudges.recordGame(.itWon, moves: [], playerColor: .white, positions: [])
        XCTAssertEqual(grudges.record?.itsRun, 3)
        grudges.recordGame(.youWon, moves: [], playerColor: .white, positions: [])
        XCTAssertEqual(grudges.record?.mood, .furious)
    }

    func testItRemembersTheWorstPieceItTookAndWhere() throws {
        let game = GameModel()
        // 1.e4 e5 2.Qh5 Nc6 3.Qxf7+?? Kxf7: the queen is lost on f7, on Black's third move.
        for move in ["e2e4", "e7e5", "d1h5", "b8c6", "h5f7", "e8f7"] { _ = game.playEngineMove(move) }
        let moment = try XCTUnwrap(GrudgeStore.worstLoss(moves: game.moves, positions: game.positionFENs,
                                                         playerColor: .white, date: .now))
        XCTAssertEqual(moment.piece, "queen")
        XCTAssertEqual(moment.square, "f7")
        XCTAssertEqual(moment.move, 3)
        XCTAssertEqual(GrudgeStore.destination(of: "exd8=Q+"), "d8")
        XCTAssertEqual(GrudgeStore.pieceAt("e1", in: Position.standard.fen), "K")
    }

    func testItSteersBackIntoOpeningsYouLost() {
        var record = GrudgeRecord(bornAt: .now, skill: 10)
        record.openings["e4 c5 Nf3 d6"] = GrudgeRecord.Tally(wins: 0, draws: 0, losses: 3)
        XCTAssertGreaterThan(record.lean(after: ["e4"], toward: "c5"), 2.5)
        XCTAssertEqual(record.lean(after: ["e4"], toward: "e5"), 1)
        XCTAssertEqual(record.lean(after: ["e4", "c5", "Nf3", "d6"], toward: "d4"), 1, "past the opening it plays its own game")
    }

    func testItsRatingFollowsItsSkill() {
        XCTAssertEqual(GrudgeRecord.rating(forSkill: 10), 1500)
        XCTAssertEqual(GrudgeRecord.rating(forSkill: 20), 3000)
        XCTAssertEqual(GrudgeRecord.level(forSkill: 11), .club)
        XCTAssertEqual(GrudgeRecord.level(forSkill: 19), .grandmaster)
    }

    func testTheGrudgeOnlySaysShortTrueThings() {
        let moments: [RivalMoment] = [
            .greeting, .tookPiece(.knight), .lostPiece(.queen), .givesCheck, .playerBlunder,
            .playerGreatMove, .rivalResigns, .playerResigned, .rivalWins, .playerWins, .draw, .drawDeclined,
        ]
        var records: [GrudgeRecord?] = [nil]
        for (you, it, run) in [(0, 4, 0), (3, 3, 2), (9, 2, 1)] {
            var record = GrudgeRecord(bornAt: .now, skill: 10)
            record.yourWins = you
            record.itsWins = it
            record.yourRun = run
            records.append(record)
        }
        for record in records {
            for moment in moments {
                for line in GrudgeVoice.lines(for: moment, record: record) {
                    XCTAssertLessThanOrEqual(line.count, 48, "too long for the bubble: \(line)")
                }
            }
        }
        let now = Date()
        let tuesday = now.addingTimeInterval(-2 * 86_400)
        let memory = GrudgeRecord.Moment(date: tuesday, move: 12, square: "e5", piece: "knight")
        XCTAssertEqual(GrudgeVoice.recall(memory, now: now)?.hasSuffix(". Move 12. Remember?"), true)
        let old = GrudgeRecord.Moment(date: now.addingTimeInterval(-30 * 86_400), move: 12, square: "e5", piece: "knight")
        XCTAssertEqual(GrudgeVoice.recall(old, now: now), "Your knight on e5. Remember?")
    }

    func testSavedGamesKnowTheGrudgeFromTheCrowd() {
        XCTAssertTrue(Rival.isGrudge(opponent: "Your Grudge"))
        XCTAssertFalse(Rival.isGrudge(opponent: "The 1600s"))
        XCTAssertEqual(Rival.named("grudge")?.isGrudge, true)
        XCTAssertEqual(Rival.named("1000s")?.level, .beginner)
        XCTAssertEqual(Rival.named("The Masters")?.level, .grandmaster)
        for rival in Rival.all + [Rival.grudge(.club)] {
            XCTAssertNotNil(UIImage(named: rival.portraitName), "\(rival.portraitName) is missing")
            XCTAssertNotNil(UIImage(named: rival.glowName), "\(rival.glowName) is missing")
        }
    }

    /// The five rivals climb from the Cub to the Ashen King, each on its own coin; games saved
    /// under their former names ("The 1600s") still find them and show the new name.
    func testRivalsHaveFacesAndKeepTheirFormerNames() {
        XCTAssertEqual(Rival.all.map(\.name), ["The Cub", "The Hunter", "The Berserker", "The Lionheart", "The Ashen King"])
        for rival in Rival.all {
            XCTAssertNotNil(rival.coinName.flatMap { UIImage(named: $0) }, "\(rival.slug)'s coin is missing")
            XCTAssertEqual(Rival.named(rival.formerName ?? "")?.level, rival.level)
        }
        XCTAssertNil(Rival.grudge(.club).coinName)

        let old = SavedGame(id: UUID(), date: .now, opponent: "The 1600s", level: MatchController.Level.club.rawValue,
                            playerIsWhite: true, result: .win, accuracy: nil, positions: [], moves: [], moments: [])
        XCTAssertEqual(old.opponentShown, "The Berserker")
        let friend = SavedGame(id: UUID(), date: .now, opponent: "Dana", level: nil,
                               playerIsWhite: true, result: .win, accuracy: nil, positions: [], moves: [], moments: [])
        XCTAssertEqual(friend.opponentShown, "Dana")

        // One rival is one player: "The Berserker wins", where the old crowds were many.
        XCTAssertEqual("The Berserker".agreeing("wins", "win"), "wins")
        XCTAssertEqual("The Ashen King".midSentence.possessive, "the Ashen King's")
        // The Ashen King was the Dragonlord: games and wins saved under that name still find him.
        let dragonlord = SavedGame(id: UUID(), date: .now, opponent: "The Dragonlord",
                                   level: MatchController.Level.grandmaster.rawValue, playerIsWhite: true, result: .win,
                                   accuracy: nil, positions: [], moves: [], moments: [])
        XCTAssertEqual(dragonlord.opponentShown, "The Ashen King")
        XCTAssertEqual(Rival.named("The Dragonlord")?.level, .grandmaster)
        XCTAssertEqual("The 1600s".agreeing("wins", "win"), "win")
    }

    // MARK: Pictures

    /// The summons, caught a few seconds in, your Grudge's card on Home, and the New Game sheet
    /// (rivals only: the Grudge lives on Home now).
    func testPictures() throws {
        let defaults = UserDefaults.standard
        let keys = ["setup.grudge", "grudge.lastSeen", GrudgeStore.key, GrudgeStore.unseenKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        var record = GrudgeRecord(bornAt: .now, skill: 11)
        record.yourWins = 7
        record.itsWins = 11
        record.scars = 7
        record.lastLoss = GrudgeRecord.Moment(date: .now.addingTimeInterval(-86_400), move: 12, square: "e5", piece: "knight")
        try snapshot("grudge-stage", view: GrudgeStage(record: record, lastSeen: (6, 11))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black), wait: 6)

        // Its card on Home, resting and opened into the summons.
        try snapshot("grudge-home-card", view: VStack(spacing: 16) {
            HomeAuroraGrudge(record: record, isOpen: false, palette: HomeAuroraPalette(dark: false),
                             select: {}, settle: {})
            HomeAuroraGrudge(record: record, isOpen: true, palette: HomeAuroraPalette(dark: false),
                             lastSeen: (6, 11), select: {}, settle: {})
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF6F1E7)), wait: 6)

        try snapshot("crowd-new-game", view: Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) {
            NewGameSheet(theme: .named(.gilded), start: { _ in }).environment(GrudgeStore(defaults: UserDefaults(suiteName: "RivalsTestsEmpty")!))
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
