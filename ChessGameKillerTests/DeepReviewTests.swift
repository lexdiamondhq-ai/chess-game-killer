import ChessKit
import SwiftUI
import XCTest
@testable import ChessGameKiller

// The coach's deep review without a network or a speaker: the server's lines from
// coach/PROTOCOL.md (POST /review), a scripted transport and a voice that writes down what it read.

// MARK: - Test pieces

/// A review of `RewindSample.game()` and the server's lines for it.
enum DeepReviewSample {
    /// The start of an MP3 ("ID3"), as a voice line carries it in base64.
    static let mp3 = Data([0x49, 0x44, 0x33, 0x04, 0x00])

    static let review = DeepReview(coach: "leo", parts: [
        DeepReviewPart(label: "The opening", kind: .intro,
                       text: "Let's look at this one together, because one idea runs right through it."),
        DeepReviewPart(label: "The opening", kind: .praise, ply: 7,
                       text: "On move 4, knight to g5 went straight for the weak point on f7. That's exactly the spirit."),
        DeepReviewPart(label: "The knight on g5", kind: .mistake, ply: 11,
                       text: "On move 6 you castled. The knight was ready to take on f7, and the king had to take back."),
        DeepReviewPart(label: "The end", kind: .moment, ply: 20,
                       text: "And on move 10 the queen took your bishop back."),
        DeepReviewPart(label: "One habit", kind: .habit,
                       text: "When you've aimed a piece at a target, look for the capture before any quiet move."),
    ])

    static let reviewLine = #"{"type":"review","coach":"leo","parts":[{"label":"The opening","kind":"intro","ply":null,"text":"Let's look at this one together, because one idea runs right through it."},{"label":"The opening","kind":"praise","ply":7,"text":"On move 4, knight to g5 went straight for the weak point on f7. That's exactly the spirit."},{"label":"The knight on g5","kind":"mistake","ply":11,"text":"On move 6 you castled. The knight was ready to take on f7, and the king had to take back."},{"label":"The end","kind":"moment","ply":20,"text":"And on move 10 the queen took your bishop back."},{"label":"One habit","kind":"habit","ply":null,"text":"When you've aimed a piece at a target, look for the capture before any quiet move."}]}"#
    static let doneLine = #"{"type":"done"}"#

    static func voiceLine(_ part: Int) -> String {
        #"{"type":"voice","part":\#(part),"format":"mp3","audio":"SUQzBAA="}"#
    }

    /// A review and its voices as the server sends them: out of order, one part without a voice.
    static var fullStream: [DeepReviewTestTransport.Step] {
        [.event(.review(review)), .event(.voice(part: 1, mp3: mp3)), .event(.voice(part: 0, mp3: mp3)),
         .event(.voice(part: 2, mp3: nil)), .event(.voice(part: 4, mp3: mp3)), .event(.voice(part: 3, mp3: mp3)),
         .event(.done)]
    }

    /// A folder of its own for one test's kept reviews.
    static func store() -> DeepReviewStore {
        DeepReviewStore(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepReviewTests-\(UUID().uuidString)", isDirectory: true))
    }
}

/// The coach's server, played by the test: every request gets the same scripted lines.
final class DeepReviewTestTransport: DeepReviewTransport, @unchecked Sendable {
    enum Step: Sendable {
        case event(DeepReviewEvent)
        case fail(Error)
        /// Nothing more comes until the request is stopped.
        case hang
    }

    private let lock = NSLock()
    private let steps: [Step]
    private var sent: [DeepReviewRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    var requests: [DeepReviewRequest] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func review(_ request: DeepReviewRequest) -> AsyncThrowingStream<DeepReviewEvent, Error> {
        lock.lock()
        sent.append(request)
        lock.unlock()
        let steps = self.steps
        return AsyncThrowingStream { continuation in
            let task = Task {
                for step in steps {
                    switch step {
                    case .event(let event):
                        continuation.yield(event)
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    case .hang:
                        try? await Task.sleep(for: .seconds(30))
                        if Task.isCancelled { return }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The coach's voice, played by the test: it writes down what it was given, in order.
@MainActor
final class DeepReviewTestSpeaker: TalkSpeaker {
    enum Line: Equatable {
        case recording(Data)
        case words(String)
    }

    private(set) var lines: [Line] = []
    private(set) var stops = 0
    /// Keeps every line going until `stop()`, like a voice still talking.
    var holds: Bool
    private var waiting: CheckedContinuation<Void, Never>?

    init(holds: Bool = false) {
        self.holds = holds
    }

    func play(mp3: Data) async {
        lines.append(.recording(mp3))
        await hold()
    }

    func say(_ text: String) async {
        lines.append(.words(text))
        await hold()
    }

    func stop() {
        stops += 1
        let continuation = waiting
        waiting = nil
        continuation?.resume()
    }

    private func hold() async {
        guard holds else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.waiting = continuation
        }
    }
}

// MARK: - The request and the stream

final class DeepReviewTests: XCTestCase {

    func testTheRequestCarriesTheGameAndItsGrades() throws {
        let game = RewindSample.game()
        let request = try XCTUnwrap(DeepReviewRequest(game: game, coach: .leo, voice: true))
        XCTAssertEqual(request.v, 1)
        XCTAssertEqual(request.player, "white")
        XCTAssertEqual(request.result, "loss")
        XCTAssertEqual(request.rival, game.opponentShown)
        XCTAssertEqual(request.rivalRating, 1600)
        XCTAssertNil(request.start, "a game from the usual first position sends none")
        XCTAssertEqual(request.moves, game.moves)
        XCTAssertEqual(request.graded.map(\.ply), [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21])
        XCTAssertNil(request.coach, "Leo is the server's own")

        let castled = try XCTUnwrap(request.graded.first { $0.ply == 11 })
        XCTAssertEqual(castled.grade, "mistake")
        XCTAssertEqual(castled.best, "Nxf7")
        XCTAssertEqual(castled.line?.first, "Nxf7")
        XCTAssertEqual(castled.line?.count, 4)
        XCTAssertEqual(castled.before, 0.55)
        XCTAssertEqual(castled.after, 0.12)
        // A move with nothing better to name sends neither a best move nor a line.
        let first = try XCTUnwrap(request.graded.first)
        XCTAssertNil(first.best)
        XCTAssertNil(first.line)

        XCTAssertEqual(DeepReviewRequest(game: game, coach: .vera, voice: false)?.coach, "vera")
    }

    func testNilsAreLeftOutOfTheBody() throws {
        let request = try XCTUnwrap(DeepReviewRequest(game: RewindSample.game(), coach: .leo, voice: true))
        let body = try XCTUnwrap(DeepReviewAPI(baseURL: URL(string: "https://review.stub")!).makeRequest(request).httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["coach"])
        XCTAssertNil(object["start"])
        XCTAssertEqual(object["voice"] as? Bool, true)
        XCTAssertEqual((object["moves"] as? [String])?.count, 22)
        let graded = try XCTUnwrap(object["graded"] as? [[String: Any]])
        XCTAssertNil(graded[0]["best"])
        XCTAssertEqual(graded[5]["best"] as? String, "Nxf7")
    }

    func testTheRequestGoesToReview() throws {
        let request = try XCTUnwrap(DeepReviewRequest(game: RewindSample.game(), coach: .leo, voice: true))
        let sent = try DeepReviewAPI(baseURL: URL(string: "https://review.stub")!).makeRequest(request)
        XCTAssertEqual(sent.url?.absoluteString, "https://review.stub/review")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testOnlyAFinishedGameOfThePlayersOwnIsOffered() {
        let game = RewindSample.game()
        XCTAssertTrue(DeepReviewRequest.offered(for: game))

        var unfinished = game
        unfinished.result = .unfinished
        XCTAssertFalse(DeepReviewRequest.offered(for: unfinished))
        XCTAssertNil(DeepReviewRequest(game: unfinished))

        var short = game
        short.moves = Array(game.moves.prefix(10))
        short.positions = Array(game.positions.prefix(11))
        short.moments = game.moments.filter { $0.ply <= 10 }
        XCTAssertFalse(DeepReviewRequest.offered(for: short))

        var ungraded = game
        ungraded.moments = Array(game.moments.prefix(2))
        XCTAssertFalse(DeepReviewRequest.offered(for: ungraded))

        // A game with a friend on this phone is both sides': there's no one player to coach.
        let friend = SavedGame(id: UUID(), date: .now, opponent: "Friend", level: nil, playerIsWhite: true,
                               result: .win, accuracy: nil, positions: game.positions, moves: game.moves,
                               moments: game.moments)
        XCTAssertFalse(DeepReviewRequest.offered(for: friend))
    }

    func testTheServersLinesAreRead() throws {
        XCTAssertEqual(try DeepReviewEvent.decode(line: DeepReviewSample.reviewLine), .review(DeepReviewSample.review))
        XCTAssertEqual(try DeepReviewEvent.decode(line: DeepReviewSample.voiceLine(3)),
                       .voice(part: 3, mp3: DeepReviewSample.mp3))
        XCTAssertEqual(try DeepReviewEvent.decode(line: #"{"type":"voice","part":2,"unavailable":"upstream"}"#),
                       .voice(part: 2, mp3: nil))
        XCTAssertEqual(try DeepReviewEvent.decode(line: DeepReviewSample.doneLine), .done)
        XCTAssertEqual(try DeepReviewEvent.decode(line: #"{"type":"error","error":"timeout"}"#), .failed("timeout"))
        XCTAssertNil(try DeepReviewEvent.decode(line: #"{"type":"progress","step":2}"#))
        XCTAssertNil(try DeepReviewEvent.decode(line: "   "))
        XCTAssertNil(try DeepReviewEvent.decode(line: #"{"type":"voice","format":"mp3","audio":"SUQzBAA="}"#),
                     "a voice line that names no part can't be placed")
        XCTAssertEqual(try DeepReviewEvent.decode(line: #"{"type":"review","coach":"leo","parts":[]}"#), .failed("internal"))
        XCTAssertThrowsError(try DeepReviewEvent.decode(line: "not json"))
    }

    func testAKindThisAppDoesntKnowIsAPlainMoment() throws {
        let line = #"{"type":"review","coach":"vera","parts":[{"label":"Later","kind":"aside","ply":4,"text":"A quiet move."}]}"#
        guard case .review(let review)? = try DeepReviewEvent.decode(line: line) else { return XCTFail("not a review") }
        XCTAssertEqual(review.speaker, .vera)
        XCTAssertEqual(review.parts, [DeepReviewPart(label: "Later", kind: .moment, ply: 4, text: "A quiet move.")])
    }

    func testTheStreamIsReadLineByLine() async throws {
        let text = [DeepReviewSample.reviewLine, "not json at all", "", DeepReviewSample.voiceLine(1),
                    DeepReviewSample.doneLine, DeepReviewSample.voiceLine(0)].joined(separator: "\r\n")
        let events = try await relayed(text)
        XCTAssertEqual(events, [.review(DeepReviewSample.review), .voice(part: 1, mp3: DeepReviewSample.mp3), .done])

        // An error line ends the stream there.
        let failed = try await relayed(#"{"type":"error","error":"upstream"}"# + "\n" + DeepReviewSample.doneLine)
        XCTAssertEqual(failed, [.failed("upstream")])
    }

    private func relayed(_ text: String) async throws -> [DeepReviewEvent] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in text.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        let (stream, continuation) = AsyncThrowingStream<DeepReviewEvent, Error>.makeStream()
        try await DeepReviewAPI.relay(bytes, to: continuation)
        continuation.finish()
        var events: [DeepReviewEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: The review itself

    func testChaptersAndLength() {
        let review = DeepReviewSample.review
        XCTAssertEqual(review.chapters, ["The opening", "The knight on g5", "The end", "One habit"])
        XCTAssertEqual(review.speaker, .leo)
        XCTAssertGreaterThan(review.seconds, 15)
        XCTAssertGreaterThanOrEqual(review.parts[4].readingTime, .seconds(3))
    }

    func testTheBoardStandsBeforeAMistakeAndAfterAnyOtherMove() {
        let game = RewindSample.game()
        let parts = DeepReviewSample.review.parts
        XCTAssertNil(parts[0].boardPly(in: game), "a part about no one move leaves the board alone")
        XCTAssertEqual(parts[1].boardPly(in: game), 7)
        XCTAssertEqual(parts[2].boardPly(in: game), 10, "before the mistake, so the better move can be shown")
        XCTAssertEqual(parts[3].boardPly(in: game), 20)
        XCTAssertNil(DeepReviewPart(label: "", kind: .moment, ply: 99, text: "x").boardPly(in: game))
        XCTAssertNil(DeepReviewPart(label: "", kind: .mistake, ply: 0, text: "x").boardPly(in: game))
    }

    // MARK: Kept with the game

    func testAReviewIsKeptWithItsRecordings() throws {
        let store = DeepReviewSample.store()
        let game = UUID()
        XCTAssertFalse(store.has(game))
        XCTAssertNil(store.review(for: game))

        store.saveVoice(DeepReviewSample.mp3, part: 0, for: game)
        XCTAssertNil(store.voice(part: 0, for: game), "no recording is kept without its review")

        store.save(DeepReviewSample.review, for: game)
        store.saveVoice(DeepReviewSample.mp3, part: 2, for: game)
        XCTAssertTrue(store.has(game))
        XCTAssertEqual(store.review(for: game), DeepReviewSample.review)
        XCTAssertEqual(store.voice(part: 2, for: game), DeepReviewSample.mp3)
        XCTAssertNil(store.voice(part: 1, for: game))

        // A new review of the same game replaces the old one and its recordings.
        var again = DeepReviewSample.review
        again.coach = "vera"
        store.save(again, for: game)
        XCTAssertEqual(store.review(for: game)?.speaker, .vera)
        XCTAssertNil(store.voice(part: 2, for: game))

        store.delete(game)
        XCTAssertFalse(store.has(game))
        XCTAssertFalse(DeepReviewStore(folder: nil).has(game))
    }

    func testOnlyTheNewestReviewsAreKept() throws {
        let store = DeepReviewSample.store()
        let games = (0..<(DeepReviewStore.limit + 3)).map { _ in UUID() }
        for (index, game) in games.enumerated() {
            store.save(DeepReviewSample.review, for: game)
            // Age each one, so the order they were kept in is the order on disk.
            let folder = try XCTUnwrap(store.folder).appendingPathComponent(game.uuidString)
            let date = Date(timeIntervalSinceNow: Double(index - 1000))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.path)
        }
        store.save(DeepReviewSample.review, for: games[games.count - 1])
        XCTAssertFalse(store.has(games[0]))
        XCTAssertTrue(store.has(games[games.count - 1]))
        XCTAssertLessThanOrEqual(games.filter(store.has).count, DeepReviewStore.limit)
    }
}

// MARK: - Playing it

@MainActor
final class DeepReviewPlayerTests: XCTestCase {

    private func make(_ steps: [DeepReviewTestTransport.Step], store: DeepReviewStore = DeepReviewSample.store(),
                        game: SavedGame = RewindSample.game(), counted: @escaping () -> Void = {})
        -> (DeepReviewPlayer, DeepReviewTestTransport, DeepReviewTestSpeaker) {
        let transport = DeepReviewTestTransport(steps)
        let speaker = DeepReviewTestSpeaker()
        let player = DeepReviewPlayer(game: game, transport: transport, store: store, speaker: speaker, onNewReview: counted)
        player.gap = .zero
        player.holdsSilentParts = false
        return (player, transport, speaker)
    }

    private func wait(_ what: String, timeout: Duration = .seconds(5), until done: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !done(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(done(), what)
    }

    func testANewReviewIsReadPartByPartAndKept() async {
        let store = DeepReviewSample.store()
        let game = RewindSample.game()
        var counted = 0
        let (player, transport, speaker) = make(DeepReviewSample.fullStream, store: store, game: game) { counted += 1 }
        XCTAssertEqual(player.phase, .loading)

        player.start()
        await wait("the review is read to its end") { player.phase == .finished }

        let parts = DeepReviewSample.review.parts
        XCTAssertEqual(speaker.lines, [
            .recording(DeepReviewSample.mp3), .recording(DeepReviewSample.mp3),
            // The part the server had no voice for is read by the device's.
            .words(parts[2].text),
            .recording(DeepReviewSample.mp3), .recording(DeepReviewSample.mp3),
        ])
        XCTAssertEqual(player.review, DeepReviewSample.review)
        XCTAssertEqual(player.index, parts.count - 1)
        XCTAssertEqual(counted, 1, "a use is counted once, when the review arrives")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.moves, game.moves)
        XCTAssertEqual(store.review(for: game.id), DeepReviewSample.review)
        XCTAssertEqual(store.voice(part: 3, for: game.id), DeepReviewSample.mp3)
        XCTAssertNil(store.voice(part: 2, for: game.id))
    }

    func testAReviewKeptWithTheGameIsFreeToHearAgain() async {
        let store = DeepReviewSample.store()
        let game = RewindSample.game()
        store.save(DeepReviewSample.review, for: game.id)
        store.saveVoice(DeepReviewSample.mp3, part: 0, for: game.id)
        var counted = 0
        let (player, transport, speaker) = make([.fail(TalkFailure.offline)], store: store, game: game) { counted += 1 }

        player.start()
        await wait("the kept review is read") { player.phase == .finished }

        XCTAssertTrue(transport.requests.isEmpty, "nothing is asked of the server")
        XCTAssertEqual(counted, 0)
        XCTAssertEqual(speaker.lines.first, .recording(DeepReviewSample.mp3))
        XCTAssertEqual(speaker.lines.count, DeepReviewSample.review.parts.count)
        XCTAssertEqual(speaker.lines.last, .words(DeepReviewSample.review.parts[4].text))
    }

    func testNoReviewIsAFailureAndCountsNothing() async {
        var counted = 0
        let cases: [([DeepReviewTestTransport.Step], String)] = [
            ([.fail(TalkFailure.offline)], "needs the internet"),
            ([.event(.failed("timeout"))], "took too long"),
            ([.fail(TalkFailure.server("daily_limit"))], "back tomorrow"),
            ([.fail(TalkFailure.server("rate_limited"))], "in a minute"),
            ([.event(.done)], "couldn't review"),
        ]
        for (steps, words) in cases {
            let store = DeepReviewSample.store()
            let (player, _, speaker) = make(steps, store: store) { counted += 1 }
            player.start()
            await wait("it fails: \(words)") {
                if case .failed = player.phase { return true }
                return false
            }
            guard case .failed(let why) = player.phase else { continue }
            XCTAssertTrue(why.contains(words), why)
            XCTAssertTrue(speaker.lines.isEmpty)
            XCTAssertFalse(store.has(player.game.id))
        }
        XCTAssertEqual(counted, 0)
    }

    func testAStreamThatBreaksAfterTheWordsIsStillRead() async {
        let (player, _, speaker) = make([.event(.review(DeepReviewSample.review)),
                                         .event(.voice(part: 0, mp3: DeepReviewSample.mp3)),
                                         .fail(TalkFailure.offline)])
        player.start()
        await wait("the review is read to its end") { player.phase == .finished }
        XCTAssertEqual(speaker.lines.first, .recording(DeepReviewSample.mp3))
        XCTAssertEqual(speaker.lines.dropFirst().count, 4)
        XCTAssertEqual(speaker.lines.last, .words(DeepReviewSample.review.parts[4].text))
    }

    func testPauseResumeAndMovingBetweenParts() async {
        let (player, _, speaker) = make(DeepReviewSample.fullStream)
        speaker.holds = true
        player.start()
        await wait("the first part is being read") { speaker.lines.count == 1 }
        XCTAssertEqual(player.phase, .playing)
        XCTAssertEqual(player.index, 0)

        player.pause()
        XCTAssertEqual(player.phase, .paused)
        XCTAssertEqual(player.index, 0)

        // Paused, moving on only turns the page.
        player.go(to: 2)
        XCTAssertEqual(player.index, 2)
        XCTAssertEqual(player.phase, .paused)
        player.go(to: 99)
        XCTAssertEqual(player.index, 2)

        player.resume()
        XCTAssertEqual(player.phase, .playing)
        await wait("the third part is read") { speaker.lines.last == .words(DeepReviewSample.review.parts[2].text) }

        // Playing, moving on reads that part.
        player.go(to: 4)
        await wait("the last part is read") { speaker.lines.last == .recording(DeepReviewSample.mp3) && player.index == 4 }

        speaker.holds = false
        speaker.stop()
        await wait("the review ends") { player.phase == .finished }

        // Hearing it again starts from the top.
        speaker.holds = true
        player.resume()
        XCTAssertEqual(player.index, 0)
        XCTAssertEqual(player.phase, .playing)

        player.close()
        XCTAssertGreaterThan(speaker.stops, 0)
    }

    func testAGameTooShortSaysSo() {
        var game = RewindSample.game()
        game.moments = []
        let (player, transport, _) = make(DeepReviewSample.fullStream, game: game)
        player.start()
        guard case .failed(let why) = player.phase else { return XCTFail("\(player.phase)") }
        XCTAssertTrue(why.contains("too short"))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: Premium

    func testANewReviewIsPremiumsAndCountedThere() {
        let name = "DeepReviewTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertTrue(PremiumFeature.deepReview.isLocked)
        XCTAssertEqual(PremiumFeature.deepReview.premium, .perDay(20))

        let free = Premium(defaults: defaults, isPremium: false)
        XCTAssertFalse(free.canUse(.deepReview, key: "a"))
        XCTAssertFalse(free.use(.deepReview, key: "a"))
        XCTAssertEqual(free.remaining(.deepReview), 0)
        XCTAssertEqual(free.limitLine(.deepReview), PremiumFeature.deepReview.limitLine)

        let paid = Premium(defaults: defaults, isPremium: true)
        XCTAssertEqual(paid.remaining(.deepReview), 20)
        for game in 0..<20 {
            XCTAssertTrue(paid.canUse(.deepReview, key: "game-\(game)"))
            XCTAssertTrue(paid.use(.deepReview, key: "game-\(game)"))
        }
        XCTAssertEqual(paid.remaining(.deepReview), 0)
        XCTAssertFalse(paid.canUse(.deepReview, key: "one-more"))
        XCTAssertFalse(paid.use(.deepReview, key: "one-more"))
        XCTAssertTrue(paid.use(.deepReview, key: "game-3"), "a game already reviewed today is free again")
        XCTAssertEqual(paid.limitLine(.deepReview), PremiumFeature.deepReview.premiumLimitLine)
        // The other locked features stay open and uncounted with Premium.
        XCTAssertNil(paid.remaining(.lessons))
        XCTAssertTrue(paid.use(.puzzleCycles))
    }
}
