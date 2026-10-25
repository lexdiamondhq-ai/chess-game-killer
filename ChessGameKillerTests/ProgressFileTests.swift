import XCTest
@testable import ChessGameKiller

/// The small files that hold what the player has built up: the army, training, the thinking
/// drills, endgames, the repertoire and friend games. Each one reads whatever version of the
/// app wrote it, and a file that can't be read is set aside, never written over.
@MainActor
final class ProgressFileTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ json: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    /// Prints the app's own encoding of a value as a FIXTURE line in the CI log, so the
    /// hand-written files below can be checked against what the app writes.
    private func logFixture<Value: Encodable>(_ name: String, _ value: Value) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            NSLog("FIXTURE %@ %@", name, text)
        }
    }

    // MARK: Reading a file

    func testNoFileReadsAsNothing() {
        XCTAssertNil(ProgressFile.read(ThinkProgress.self, at: folder.appendingPathComponent("none.json")))
        XCTAssertNil(ProgressFile.read(ThinkProgress.self, at: nil))
    }

    func testAnUnreadableFileIsSetAsideAndNeverWrittenOver() throws {
        let url = try file("think-progress.json", "this is not json")
        let store = ThinkStore(progress: ThinkStore.load(from: url) ?? ThinkProgress(), fileURL: url)
        XCTAssertEqual(store.progress, ThinkProgress(), "The store starts fresh")

        let aside = ProgressFile.asideURL(for: url)
        XCTAssertEqual(aside.lastPathComponent, "think-progress.unreadable.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "this is not json", "The old file is kept to recover from")

        store.recordLevel(1500)
        XCTAssertEqual(ThinkStore.load(from: url)?.level, 1500, "The store saves to its own place")
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "this is not json", "and the old file stays")
    }

    func testTheNextUnreadableFileReplacesTheOneSetAside() throws {
        let url = try file("army.json", "first")
        XCTAssertNil(ProgressFile.read(ArmyStore.Army.self, at: url))
        _ = try file("army.json", "second")
        XCTAssertNil(ProgressFile.read(ArmyStore.Army.self, at: url))
        XCTAssertEqual(try String(contentsOf: ProgressFile.asideURL(for: url), encoding: .utf8), "second")
    }

    func testEndgameProgressStartsFreshFromAnUnreadableFileAndKeepsIt() throws {
        let url = try file("endgame-progress.json", "{not json")
        let progress = EndgameProgress.load(from: url, studies: [])
        XCTAssertTrue(progress.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProgressFile.asideURL(for: url).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Files from other versions

    /// An army file as the app writes it, by hand: every field as it looks on disk, and a pawn
    /// saved before experience was stored. Pieces are keyed by their slot, which Swift writes
    /// as a list of slot, record, slot, record (and rivals by level, as an object of strings).
    /// The FIXTURE line in the log is the app's own encoding of the same army, to compare.
    func testAnArmyFileReadsBack() throws {
        let json = """
        {"records":[
           "queen",{"name":"Vesper","games":12,"wins":7,"survivedWins":5,"captures":9,"captureValue":21,"mates":2,
                    "promotions":0,"falls":3,"xp":88,"honors":1,"takenBy":{"2":3,"3":1},"revenge":[2],"trophies":[1],"escapes":1},
           "ePawn",{"games":12,"wins":7,"survivedWins":3,"captures":1,"captureValue":1,"mates":0,"promotions":1,"falls":6}],
         "lastGameID":"0E4B9A4C-6E6B-4F3A-9C8C-5B1E2D3F4A5B",
         "captives":["kingsKnight",4]}
        """
        let url = try file("army.json", json)
        let army = try XCTUnwrap(ProgressFile.read(ArmyStore.Army.self, at: url))

        var queen = PieceRecord()
        queen.name = "Vesper"
        queen.games = 12
        queen.wins = 7
        queen.survivedWins = 5
        queen.captures = 9
        queen.captureValue = 21
        queen.mates = 2
        queen.falls = 3
        queen.xp = 88
        queen.honors = 1
        queen.takenBy = [2: 3, 3: 1]
        queen.revenge = [2]
        queen.trophies = [1]
        queen.escapes = 1
        var pawn = PieceRecord()
        pawn.games = 12
        pawn.wins = 7
        pawn.survivedWins = 3
        pawn.captures = 1
        pawn.captureValue = 1
        pawn.promotions = 1
        pawn.falls = 6
        // Saved before experience was stored: what it had earned by then.
        pawn.xp = 12 + 7 * 3 + 3 * 2 + 1 * 2 + 10
        let expected = ArmyStore.Army(records: [.queen: queen, .ePawn: pawn],
                                      lastGameID: UUID(uuidString: "0E4B9A4C-6E6B-4F3A-9C8C-5B1E2D3F4A5B"),
                                      captives: [.kingsKnight: 4])
        logFixture("army", expected)
        XCTAssertEqual(army, expected)
        XCTAssertEqual(army.records[.queen]?.nemesis?.level, .club, "Taken three times by Pulse")
        XCTAssertEqual(army.records[.queen]?.nemesis?.times, 3)

        let written = try XCTUnwrap(String(data: JSONEncoder().encode(expected), encoding: .utf8))
        XCTAssertTrue(written.contains("\"queen\",{"), "Slot, then record, in a list: \(written)")
        XCTAssertEqual(try JSONDecoder().decode(ArmyStore.Army.self, from: Data(written.utf8)), expected)
        XCTAssertEqual(try JSONDecoder().decode(ArmyStore.Army.self, from: Data("{}".utf8)), ArmyStore.Army())
    }

    /// A training file from an older version: records with few fields, a mistake that can't be
    /// read, a key from a newer version. Everything readable is kept, the rest keeps its default.
    func testATrainingFileFromAnotherVersionReadsBack() throws {
        let json = """
        {"skills":{"forks":{"rating":812.5,"attempts":9,"solved":6}},
         "items":{"fork-1":{"box":2,"due":790000000,"lastSeen":789000000}},
         "lessonsDone":{"welcome":788000000},
         "mistakes":[{"id":"m1","fen":"6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1","best":"a1a8","played":"h2h3",
                      "skill":"back-rank","title":"You had mate","created":789500000,"due":789500000},
                     {"id":"broken"}],
         "xp":310,"streak":{"current":3,"best":5,"lastDay":"2026-01-14"},"sessionsDone":4,"newInAnUpdate":true}
        """
        let url = try file("training-progress.json", json)
        let progress = try XCTUnwrap(ProgressFile.read(TrainingProgress.self, at: url))

        var expected = TrainingProgress()
        expected.skills["forks"] = SkillRecord(rating: 812.5, attempts: 9, solved: 6)
        expected.items["fork-1"] = ItemRecord(box: 2, due: Date(timeIntervalSinceReferenceDate: 790_000_000),
                                              lastSeen: Date(timeIntervalSinceReferenceDate: 789_000_000))
        expected.lessonsDone["welcome"] = Date(timeIntervalSinceReferenceDate: 788_000_000)
        let when = Date(timeIntervalSinceReferenceDate: 789_500_000)
        expected.mistakes = [GameMistake(id: "m1", fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8", played: "h2h3",
                                         skill: "back-rank", title: "You had mate", created: when, due: when)]
        expected.xp = 310
        expected.streak = Streak(current: 3, best: 5, lastDay: "2026-01-14")
        expected.sessionsDone = 4
        logFixture("training", expected)
        XCTAssertEqual(progress, expected, "A mistake with no position is dropped; everything else keeps its default")
        XCTAssertEqual(progress.skills["forks"]?.gameHits, 0)
        XCTAssertNil(progress.skills["forks"]?.lastPracticed)
        XCTAssertEqual(progress.items["fork-1"]?.attempts, 0)
        XCTAssertEqual(progress.mistakes.first?.fixed, false)
        XCTAssertNil(progress.streak.restDay)
        XCTAssertNil(progress.lastAccuracy)

        XCTAssertEqual(try JSONDecoder().decode(TrainingProgress.self, from: Data("{}".utf8)), TrainingProgress())
        XCTAssertEqual(try JSONDecoder().decode(TrainingProgress.self, from: JSONEncoder().encode(expected)), expected)
    }

    /// A record missing its dates still reads: it was seen just now and is due now.
    func testARecordWithoutDatesIsDueNow() throws {
        let record = try JSONDecoder().decode(ItemRecord.self, from: Data(#"{"box":1}"#.utf8))
        XCTAssertEqual(record.box, 1)
        XCTAssertLessThan(abs(record.lastSeen.timeIntervalSinceNow), 5)
        XCTAssertEqual(record.due, record.lastSeen)
        let streak = try JSONDecoder().decode(Streak.self, from: Data(#"{"current":3}"#.utf8))
        XCTAssertEqual(streak, Streak(current: 3), "Keys a file doesn't have keep their defaults")
    }

    func testAThinkingFileWithoutNewerKeysReadsBack() throws {
        let url = try file("think-progress.json", #"{"positions":30,"points":41,"found":22,"level":1500}"#)
        let progress = try XCTUnwrap(ThinkStore.load(from: url))
        XCTAssertEqual(progress.positions, 30)
        XCTAssertEqual(progress.points, 41)
        XCTAssertEqual(progress.found, 22)
        XCTAssertEqual(progress.foundFirst, 0)
        XCTAssertEqual(progress.rounds, 0)
        XCTAssertEqual(progress.recent, [])
        XCTAssertEqual(progress.level, 1500)
        XCTAssertNil(progress.levelDate)
        logFixture("think", progress)
    }

    func testARepertoireFileKeepsEveryLineItCanRead() throws {
        let json = """
        [{"lineID":"italian","name":"Italian Game","moves":["e2e4","e7e5","g1f3","b8c6","f1c4"],"side":"w","box":2,"due":790000000},
         {"lineID":"sicilian","moves":["e2e4","c7c5"]},
         {"name":"no line"}]
        """
        let url = try file("repertoire.json", json)
        let entries = try XCTUnwrap(ProgressFile.read([Lossy<RepertoireEntry>].self, at: url)).compactMap(\.value)
        XCTAssertEqual(entries.map(\.lineID), ["italian", "sicilian"], "A line with no id is dropped")
        XCTAssertEqual(entries[0], RepertoireEntry(lineID: "italian", name: "Italian Game", moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"],
                                                   side: "w", box: 2, due: Date(timeIntervalSinceReferenceDate: 790_000_000)))
        XCTAssertEqual(entries[1].name, "")
        XCTAssertEqual(entries[1].color, .white)
        XCTAssertEqual(entries[1].box, 0)
        XCTAssertLessThan(abs(entries[1].due.timeIntervalSinceNow), 5, "Due now, so it comes up for review")
        logFixture("repertoire", [entries[0]])
    }

    func testFriendGamesThatCantBeReadAreSkipped() throws {
        let game = FriendGame.sample(FriendGameState.sample(), seat: .white)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(game), encoding: .utf8))
        let url = try file("friend-games.json", "[\(encoded), {\"id\":\"not a game\"}]")
        let games = ChallengeStore.load(from: url)
        XCTAssertEqual(games.map(\.id), [game.id])
        XCTAssertEqual(games.first?.code, game.code)
        XCTAssertEqual(games.first?.seat, .white)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "A file that reads is left where it is")
    }
}
