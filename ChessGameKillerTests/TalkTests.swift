import ChessKit
import XCTest
@testable import ChessGameKiller

// Talk It Through without a network, an engine, a microphone or a speaker: the server's lines from
// coach/PROTOCOL.md, Stockfish's numbers from a scripted engine, and the session's whole flow with
// stand-ins for the transport, the listener and Leo's voice.

// MARK: - Test pieces

/// Messages from coach/PROTOCOL.md.
private enum TalkTestData {
    /// The protocol's position: white to move, black's bishop on c5 eyeing f2.
    static let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"
    /// The start of an MP3 ("ID3"), as the voice line carries it in base64.
    static let mp3 = Data([0x49, 0x44, 0x33, 0x04, 0x00])

    static let checkedLine = #"{"type":"checked","understood":true,"player":"white","move":{"said":"I'll castle","san":"O-O","uci":"e1g1","grade":"best","note":"O-O is the best move.","reply":{"san":"d6","uci":"d7d6"},"squares":["e1","g1"],"arrows":[{"from":"e1","to":"g1","tone":"good"}]},"claims":[{"id":"c1","said":"his bishop eyes f2","kind":"attacks","verdict":"right","note":"The bishop on c5 hits f2.","squares":["c5","f2"],"arrows":[{"from":"c5","to":"f2","tone":"info"}]},{"id":"c2","said":"my knight on f3 is safe","kind":"safe","verdict":"right","note":"Nothing can take the knight on f3 and win it.","squares":["f3"],"arrows":[]}],"missed":[],"habits":{"threats":"good","forcing":"none","safety":"good"},"eval":{"cp":31},"best":null,"nudge":null}"#
    static let answerText = "Right about the bishop eyeing f2, and castling is the best move here."
    static let answerLine = #"{"type":"answer","text":"Right about the bishop eyeing f2, and castling is the best move here.","source":"leo"}"#
    static let voiceLine = #"{"type":"voice","format":"mp3","audio":"SUQzBAA="}"#
    static let doneLine = #"{"type":"done"}"#

    /// The whole reply, with a kind of line this app doesn't know and a blank line thrown in.
    static var stream: String {
        [checkedLine, #"{"type":"progress","step":2}"#, "", answerLine, voiceLine, doneLine].joined(separator: "\n") + "\n"
    }

    /// The checked line, as the app should read it.
    static let check = TalkCheck(
        understood: true,
        player: "white",
        move: TalkMoveCheck(said: "I'll castle", san: "O-O", uci: "e1g1", grade: .best, note: "O-O is the best move.",
                            reply: TalkMove(san: "d6", uci: "d7d6"), squares: ["e1", "g1"],
                            arrows: [TalkArrow(from: "e1", to: "g1", tone: .good)]),
        claims: [
            TalkClaim(id: "c1", said: "his bishop eyes f2", kind: .attacks, verdict: .right,
                      note: "The bishop on c5 hits f2.", squares: ["c5", "f2"],
                      arrows: [TalkArrow(from: "c5", to: "f2", tone: .info)]),
            TalkClaim(id: "c2", said: "my knight on f3 is safe", kind: .safe, verdict: .right,
                      note: "Nothing can take the knight on f3 and win it.", squares: ["f3"], arrows: []),
        ],
        missed: [],
        habits: TalkHabits(threats: .good, forcing: .none, safety: .good),
        eval: TalkEval(cp: 31),
        best: nil,
        nudge: nil
    )

    /// The protocol's request.
    static let request = TalkRequest(
        fen: fen, said: "his bishop eyes f2 so I'll castle, and my knight on f3 is safe", typed: false,
        reveal: false, context: .game, lastMove: "f8c5", voice: true,
        facts: TalkFacts(depth: 12,
                         moves: [TalkFactLine(uci: "e1g1", eval: TalkEval(cp: 31), pv: ["e1g1", "d7d6", "c2c3"])],
                         threats: [TalkFactLine(uci: "c5f2", eval: TalkEval(cp: -120), pv: ["c5f2", "e1f2", "f6g4"])])
    )

    /// Leo's whole answer: verdicts, words, voice, done.
    static var fullAnswer: [TalkTestTransport.Step] {
        [.event(.checked(check)), .event(.answer(TalkAnswer(text: answerText))), .event(.voice(TalkVoice(audio: mp3))),
         .event(.done)]
    }
}

/// Leo's server, played by the test: every talk gets the same scripted lines, and every request
/// is written down.
private final class TalkTestTransport: TalkTransport, @unchecked Sendable {
    enum Step: Sendable {
        case event(TalkEvent)
        case fail(Error)
        /// Nothing more comes until the request is stopped.
        case hang
    }

    private let lock = NSLock()
    private let steps: [Step]
    private var sent: [TalkRequest] = []
    private var cancelled = 0

    init(_ steps: [Step]) {
        self.steps = steps
    }

    var requests: [TalkRequest] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    /// How many requests were stopped by the app before they ended.
    var cancellations: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func talk(_ request: TalkRequest) -> AsyncThrowingStream<TalkEvent, Error> {
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
            continuation.onTermination = { [weak self] termination in
                task.cancel()
                if case .cancelled = termination { self?.noteCancelled() }
            }
        }
    }

    private func noteCancelled() {
        lock.lock()
        cancelled += 1
        lock.unlock()
    }
}

/// The speech recognizer, played by the test: `hear` is the player talking.
@MainActor
private final class TalkTestListener: TalkListener {
    var isAvailable = true
    /// The player's answer to the permission prompt.
    var allows = true
    var startError: Error?
    /// Everything heard, which `stop()` hands back.
    var heard = ""
    private(set) var permissionRequests = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private var onText: (@MainActor (String) -> Void)?
    private var onLevel: (@MainActor (Double) -> Void)?
    /// The last start's words callback, kept even after a cancel, to play a result that comes late.
    private var lastOnText: (@MainActor (String) -> Void)?

    func requestPermission() async -> Bool {
        permissionRequests += 1
        return allows
    }

    func start(onText: @escaping @MainActor (String) -> Void, onLevel: @escaping @MainActor (Double) -> Void) throws {
        if let startError { throw startError }
        starts += 1
        self.onText = onText
        self.onLevel = onLevel
        lastOnText = onText
    }

    func stop() -> String {
        stops += 1
        // Like the recognizer, the last words may still come after the button is up.
        onLevel = nil
        return heard
    }

    func cancel() {
        cancels += 1
        onText = nil
        onLevel = nil
    }

    /// The player says something: the words so far, and how loud.
    func hear(_ words: String, level: Double = 0.5) {
        heard = words
        onText?(words)
        onLevel?(level)
    }

    /// A result arriving after the listener was cancelled.
    func lateResult(_ words: String) {
        lastOnText?(words)
    }
}

/// Leo's voice, played by the test: it writes down what it was given.
@MainActor
private final class TalkTestSpeaker: TalkSpeaker {
    private(set) var played: [Data] = []
    private(set) var said: [String] = []
    private(set) var stops = 0
    /// Keeps every line going until `stop()`, like a voice still talking.
    var holds = false
    private var waiting: CheckedContinuation<Void, Never>?

    func play(mp3: Data) async {
        played.append(mp3)
        await hold()
    }

    func say(_ text: String) async {
        said.append(text)
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

/// An engine that scores every legal move as equal, in board order, and writes down what it was asked.
private actor TalkTestEngine: ChessEngine {
    struct Call: Equatable, Sendable {
        let fen: String
        let depth: Int
        let lines: Int
        let maxTimeMs: Int?
    }

    private(set) var calls: [Call] = []
    private let silent: Bool
    private let delay: Duration?

    init(silent: Bool = false, delay: Duration? = nil) {
        self.silent = silent
        self.delay = delay
    }

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        calls.append(Call(fen: fen, depth: depth, lines: lines, maxTimeMs: maxTimeMs))
        if let delay {
            try? await Task.sleep(for: delay)
        }
        if silent { return [] }
        guard let position = Position(fen: fen) else { return [] }
        let moves = TrainingChess.legalMoves(in: Board(position: position))
        return moves.prefix(lines).map { EngineLine(moves: [$0], evaluation: .centipawns(0)) }
    }

    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String? {
        nil
    }
}

/// A session wired to the stand-ins.
@MainActor
private final class TalkTestRig {
    let transport: TalkTestTransport
    let listener: TalkTestListener
    let speaker: TalkTestSpeaker
    let engine: TalkTestEngine
    let session: TalkSession

    init(_ steps: [TalkTestTransport.Step], engine: TalkTestEngine = TalkTestEngine()) {
        transport = TalkTestTransport(steps)
        listener = TalkTestListener()
        speaker = TalkTestSpeaker()
        self.engine = engine
        session = TalkSession(fen: TalkTestData.fen, player: .white, context: .game, reveal: true, lastMove: "f8c5",
                              engine: engine, api: transport, listener: listener, speaker: speaker)
        session.lastWordsGrace = .milliseconds(50)
    }

    /// The player types a plan and sends it.
    func typeAndSend(_ words: String) {
        session.beginTyping()
        session.draft = words
        session.sendDraft()
    }
}

/// Serves canned replies at https://talk.stub/{scenario}/talk, so the live transport runs without a network.
private final class TalkStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "talk.stub"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = url.pathComponents.dropFirst().first ?? ""
        let status = scenario == "limited" ? 429 : 200
        let type = status == 200 ? "application/x-ndjson" : "application/json"
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": type]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        switch scenario {
        case "limited":
            client?.urlProtocol(self, didLoad: Data(#"{"error":"rate_limited"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case "slow":
            // The verdicts, and then nothing more.
            client?.urlProtocol(self, didLoad: Data((TalkTestData.checkedLine + "\n").utf8))
        default:
            client?.urlProtocol(self, didLoad: Data(TalkTestData.stream.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private struct TalkTestTimedOut: Error {}

// MARK: - Tests

@MainActor
final class TalkTests: XCTestCase {

    private var wasMuted = false

    override func setUp() async throws {
        // The coach's mute switch decides whether Leo's voice is asked for; these tests expect it.
        wasMuted = CoachVoice.shared.isMuted
        CoachVoice.shared.isMuted = false
    }

    override func tearDown() async throws {
        CoachVoice.shared.isMuted = wasMuted
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

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The server's lines

    func testDecodesLeosWholeStreamFromTheProtocol() throws {
        var events: [TalkEvent] = []
        for line in TalkTestData.stream.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = try TalkEvent.decode(line: line) {
                events.append(event)
            }
        }
        XCTAssertEqual(events, [
            .checked(TalkTestData.check),
            .answer(TalkAnswer(text: TalkTestData.answerText, source: "leo")),
            .voice(TalkVoice(audio: TalkTestData.mp3)),
            .done,
        ])
        XCTAssertEqual(TalkTestData.check.rightCount, 2)
        XCTAssertEqual(TalkTestData.check.judgedCount, 2)

        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"error","error":"upstream"}"#), TalkEvent.failed("upstream"))
        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"error"}"#), TalkEvent.failed("internal"))
        XCTAssertNil(try TalkEvent.decode(line: #"{"type":"progress","step":2}"#), "a kind of line this app doesn't know")
        XCTAssertNil(try TalkEvent.decode(line: "  \r"))
        XCTAssertThrowsError(try TalkEvent.decode(line: "<html>Bad gateway</html>"))
        XCTAssertThrowsError(try TalkEvent.decode(line: #"{"kind":"checked"}"#))
    }

    func testANewerServerNeverSinksTheAnswer() throws {
        // Unknown grades, kinds, verdicts, tones and marks fall back; missing fields and arrays are empty.
        let line = #"{"type":"checked","player":"black","move":{"said":"h6","grade":"brilliant","arrows":[{"from":"h7","to":"h6","tone":"purple"}]},"claims":[{"id":"c1","kind":"fork","verdict":"maybe"}],"habits":{"threats":"amber"},"extra":{"anything":[1,2,3]}}"#
        guard case .checked(let check)? = try TalkEvent.decode(line: line) else {
            return XCTFail("a checked line")
        }
        XCTAssertTrue(check.understood)
        XCTAssertEqual(check.player, "black")
        XCTAssertEqual(check.move?.grade, .unknown)
        XCTAssertNil(check.move?.san)
        XCTAssertNil(check.move?.reply)
        XCTAssertEqual(check.move?.note, "")
        XCTAssertEqual(check.move?.squares, [])
        XCTAssertEqual(check.move?.arrows, [TalkArrow(from: "h7", to: "h6", tone: .info)])
        XCTAssertEqual(check.claims.count, 1)
        XCTAssertEqual(check.claims.first?.kind, .other)
        XCTAssertEqual(check.claims.first?.verdict, .unclear)
        XCTAssertEqual(check.claims.first?.said, "")
        XCTAssertEqual(check.claims.first?.arrows, [])
        XCTAssertEqual(check.missed, [])
        XCTAssertEqual(check.habits, TalkHabits(threats: .none, forcing: .none, safety: .none))
        XCTAssertNil(check.eval)
        XCTAssertNil(check.best)
        XCTAssertNil(check.nudge)
        XCTAssertEqual(check.judgedCount, 0)

        guard case .checked(let bare)? = try TalkEvent.decode(line: #"{"type":"checked","understood":false}"#) else {
            return XCTFail("a checked line")
        }
        XCTAssertFalse(bare.understood)
        XCTAssertNil(bare.move)
        XCTAssertEqual(bare.claims, [])
        XCTAssertEqual(bare.player, "white")

        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"voice","unavailable":"budget"}"#),
                       TalkEvent.voice(TalkVoice(audio: nil, unavailable: "budget")))
        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"voice"}"#),
                       TalkEvent.voice(TalkVoice(audio: nil, unavailable: "upstream")))
        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"voice","format":"mp3","audio":"not base64!"}"#),
                       TalkEvent.voice(TalkVoice(audio: nil, unavailable: "upstream")))
        XCTAssertEqual(try TalkEvent.decode(line: #"{"type":"answer"}"#),
                       TalkEvent.answer(TalkAnswer(text: "", source: "leo")))
    }

    // MARK: What the app sends

    func testTheRequestLeavesOutWhatIsntThere() throws {
        let bare = TalkRequest(fen: TalkTestData.fen, said: "h6", typed: true, reveal: false, context: .session,
                               lastMove: nil, voice: false, facts: nil)
        let object = try jsonObject(JSONEncoder().encode(bare))
        XCTAssertEqual(Set(object.keys), ["v", "fen", "said", "typed", "reveal", "context", "voice"])
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["fen"] as? String, TalkTestData.fen)
        XCTAssertEqual(object["said"] as? String, "h6")
        XCTAssertEqual(object["typed"] as? Bool, true)
        XCTAssertEqual(object["reveal"] as? Bool, false)
        XCTAssertEqual(object["context"] as? String, "session")
        XCTAssertEqual(object["voice"] as? Bool, false)

        let full = try jsonObject(JSONEncoder().encode(TalkTestData.request))
        XCTAssertEqual(Set(full.keys), ["v", "fen", "said", "typed", "reveal", "context", "lastMove", "voice", "facts"])
        XCTAssertEqual(full["lastMove"] as? String, "f8c5")
        XCTAssertEqual(full["context"] as? String, "game")
        let facts = try XCTUnwrap(full["facts"] as? [String: Any])
        XCTAssertEqual(facts["depth"] as? Int, 12)
        let moves = try XCTUnwrap(facts["moves"] as? [[String: Any]])
        XCTAssertEqual(moves.first?["uci"] as? String, "e1g1")
        XCTAssertEqual(moves.first?["pv"] as? [String], ["e1g1", "d7d6", "c2c3"])
        let eval = try XCTUnwrap(moves.first?["eval"] as? [String: Any])
        XCTAssertEqual(Set(eval.keys), ["cp"], "no mate key when there is no mate")
        XCTAssertEqual(eval["cp"] as? Int, 31)
        let threats = try XCTUnwrap(facts["threats"] as? [[String: Any]])
        XCTAssertEqual(threats.first?["uci"] as? String, "c5f2")
    }

    func testEvalsReadAndWriteAsTheServerDoes() throws {
        for eval in [TalkEval(cp: 35), TalkEval(cp: 0), TalkEval(cp: -120), TalkEval(mate: 3), TalkEval(mate: -2)] {
            let data = try JSONEncoder().encode(eval)
            XCTAssertEqual(try JSONDecoder().decode(TalkEval.self, from: data), eval)
        }
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(TalkEval(cp: 35)), as: UTF8.self), #"{"cp":35}"#)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(TalkEval(mate: 3)), as: UTF8.self), #"{"mate":3}"#)
        XCTAssertEqual(try JSONDecoder().decode(TalkEval.self, from: Data(#"{"mate":-1}"#.utf8)).evaluation, .mate(-1))
        XCTAssertEqual(TalkEval(.centipawns(-40)), TalkEval(cp: -40))
        XCTAssertEqual(TalkEval(.mate(2)), TalkEval(mate: 2))
        XCTAssertEqual(TalkEval(cp: 31).evaluation, .centipawns(31))
        XCTAssertNil(TalkEval().evaluation)

        let long = EngineLine(moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7",
                                      "f1e1", "b7b5"],
                              evaluation: .mate(4))
        let line = try XCTUnwrap(TalkFactLine(long))
        XCTAssertEqual(line.uci, "e2e4")
        XCTAssertEqual(line.pv.count, 10, "at most ten moves of line")
        XCTAssertEqual(line.eval, TalkEval(mate: 4))
        XCTAssertNil(TalkFactLine(EngineLine(moves: [], evaluation: .centipawns(0))))
    }

    // MARK: Stockfish's numbers

    func testTheNullMovePassesTheTurn() {
        // Black passes: white to move, en passant gone, the next move number.
        XCTAssertEqual(TalkFactSheet.nullMoveFEN("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"),
                       "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        // White passes: black to move, castling kept, the same move number.
        XCTAssertEqual(TalkFactSheet.nullMoveFEN(TalkTestData.fen),
                       "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R b KQkq - 1 5")
        XCTAssertEqual(TalkFactSheet.nullMoveFEN("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 12"),
                       "4k3/8/8/3pP3/8/8/8/4K3 b - - 0 12")
        // A short FEN comes back whole.
        XCTAssertEqual(TalkFactSheet.nullMoveFEN("8/8/8/8/8/8/8/K6k w - -"), "8/8/8/8/8/8/8/K6k b - - 0 1")
        XCTAssertNil(TalkFactSheet.nullMoveFEN("hello"))
        XCTAssertNil(TalkFactSheet.nullMoveFEN("8/8/8/8/8/8/8/K6k x - - 0 1"))
    }

    func testTheNumbersCoverEveryMoveAndTheThreats() async throws {
        let engine = TalkTestEngine()
        let start = Position.standard.fen
        let passed = try XCTUnwrap(TalkFactSheet.nullMoveFEN(start))
        let computed = await TalkFactSheet.compute(fen: start, engine: engine)
        let facts = try XCTUnwrap(computed)
        let calls = await engine.calls
        // The moves first, then the threats: one search at a time.
        XCTAssertEqual(calls, [
            TalkTestEngine.Call(fen: start, depth: 12, lines: 20, maxTimeMs: 3000),
            TalkTestEngine.Call(fen: passed, depth: 12, lines: 6, maxTimeMs: 1500),
        ])
        XCTAssertEqual(facts.depth, 12)
        XCTAssertEqual(facts.moves.count, 20)
        XCTAssertEqual(facts.threats.count, 6)
        // The threats are black's moves, as if white had passed.
        XCTAssertTrue(facts.threats.allSatisfy { $0.uci.hasSuffix("5") || $0.uci.hasSuffix("6") })
    }

    func testInCheckThereAreNoThreatsToLookFor() async throws {
        let engine = TalkTestEngine()
        let computed = await TalkFactSheet.compute(fen: "4k3/8/8/8/8/8/4q3/4K3 w - - 0 1", engine: engine)
        let facts = try XCTUnwrap(computed)
        let calls = await engine.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.lines, 1, "only taking the queen gets out of check")
        XCTAssertEqual(facts.moves.map(\.uci), ["e1e2"])
        XCTAssertEqual(facts.threats, [])
    }

    func testTheMovesAskedForAreCappedAndPromotionsCountFour() async throws {
        // A position with 218 legal moves: forty are asked for.
        let engine = TalkTestEngine()
        _ = await TalkFactSheet.compute(fen: "R6R/3Q4/1Q4Q1/4Q3/2Q4Q/Q4Q2/pp1Q4/kBNN1KB1 w - - 0 1", engine: engine)
        let calls = await engine.calls
        XCTAssertEqual(calls.first?.lines, 40)

        let promoting = try XCTUnwrap(Position(fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1"))
        XCTAssertEqual(TalkFactSheet.legalMoveCount(in: Board(position: promoting)), 9, "four promotions and five king moves")
    }

    func testNoNumbersForAPositionThatCantBeAnalyzed() async {
        let engine = TalkTestEngine()
        let notAPosition = await TalkFactSheet.compute(fen: "not a position", engine: engine)
        XCTAssertNil(notAPosition)
        let mated = await TalkFactSheet.compute(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3",
                                                engine: engine)
        XCTAssertNil(mated, "no moves, nothing to score")
        let calls = await engine.calls
        XCTAssertEqual(calls, [], "the engine isn't asked")

        let silent = await TalkFactSheet.compute(fen: Position.standard.fen, engine: TalkTestEngine(silent: true))
        XCTAssertNil(silent, "an engine with nothing to say gives no numbers")
    }

    func testTheNumbersStopWhenNoLongerWanted() async {
        let engine = TalkTestEngine(delay: .seconds(5))
        let work = Task { await TalkFactSheet.compute(fen: Position.standard.fen, engine: engine) }
        try? await Task.sleep(for: .milliseconds(100))
        work.cancel()
        let result = await work.value
        XCTAssertNil(result)
        let calls = await engine.calls
        XCTAssertLessThanOrEqual(calls.count, 1, "the threats search never starts")
    }

    // MARK: The transport

    func testTheRequestIsJSONPostedToTalk() throws {
        let api = TalkAPI(baseURL: try XCTUnwrap(URL(string: "https://coach.example.test")))
        let request = try api.makeRequest(TalkTestData.request)
        XCTAssertEqual(request.url?.absoluteString, "https://coach.example.test/talk")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try jsonObject(try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["said"] as? String, TalkTestData.request.said)
        XCTAssertEqual(body["lastMove"] as? String, "f8c5")
        XCTAssertEqual(TalkAPI.live.baseURL.absoluteString, "https://coach.chess-game-killer.workers.dev")
    }

    func testRefusalsCarryTheServersCode() {
        XCTAssertEqual(TalkAPI.failure(status: 429, body: Data(#"{"error":"rate_limited"}"#.utf8)), .server("rate_limited"))
        XCTAssertEqual(TalkAPI.failure(status: 429, body: Data(#"{"error":"daily_limit"}"#.utf8)), .server("daily_limit"))
        XCTAssertEqual(TalkAPI.failure(status: 400, body: Data(#"{"error":"bad_request","detail":"said is empty"}"#.utf8)),
                       .server("bad_request"))
        XCTAssertEqual(TalkAPI.failure(status: 503, body: Data(#"{"error":"not_configured"}"#.utf8)), .server("not_configured"))
        XCTAssertEqual(TalkAPI.failure(status: 502, body: Data("<html>Bad gateway</html>".utf8)), .server("http_502"))

        XCTAssertEqual(TalkAPI.failure(for: URLError(.notConnectedToInternet)) as? TalkFailure, TalkFailure.offline)
        XCTAssertEqual(TalkAPI.failure(for: URLError(.networkConnectionLost)) as? TalkFailure, TalkFailure.offline)
        XCTAssertEqual(TalkAPI.failure(for: URLError(.timedOut)) as? TalkFailure, TalkFailure.server("timeout"))
        XCTAssertTrue(TalkAPI.failure(for: URLError(.cancelled)) is CancellationError)
        XCTAssertEqual(TalkAPI.failure(for: TalkFailure.badResponse) as? TalkFailure, TalkFailure.badResponse)
    }

    func testTheStreamIsReadLineByLine() async throws {
        let events = try await relayed(TalkTestData.stream)
        XCTAssertEqual(events, [
            .checked(TalkTestData.check),
            .answer(TalkAnswer(text: TalkTestData.answerText)),
            .voice(TalkVoice(audio: TalkTestData.mp3)),
            .done,
        ])

        // Windows line ends and a line that isn't JSON; an error line ends the stream there.
        let rough = [TalkTestData.checkedLine, "not json at all", #"{"type":"error","error":"upstream"}"#,
                     TalkTestData.doneLine].joined(separator: "\r\n")
        let cut = try await relayed(rough)
        XCTAssertEqual(cut, [.checked(TalkTestData.check), .failed("upstream")])

        // The last line needs no newline.
        let last = try await relayed(TalkTestData.doneLine)
        XCTAssertEqual(last, [.done])
    }

    private func relayed(_ text: String) async throws -> [TalkEvent] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in text.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        let (stream, continuation) = AsyncThrowingStream<TalkEvent, Error>.makeStream()
        try await TalkAPI.relay(bytes, to: continuation)
        continuation.finish()
        var events: [TalkEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func testTheLiveTransportReadsTheStreamOverHTTP() async throws {
        let okAPI = try stubbedAPI("ok")
        let limitedAPI = try stubbedAPI("limited")
        let slowAPI = try stubbedAPI("slow", timeout: .milliseconds(500))

        let ok = await collect(okAPI.talk(TalkTestData.request))
        XCTAssertNil(ok.error)
        XCTAssertEqual(ok.events, [
            .checked(TalkTestData.check),
            .answer(TalkAnswer(text: TalkTestData.answerText)),
            .voice(TalkVoice(audio: TalkTestData.mp3)),
            .done,
        ])

        let limited = await collect(limitedAPI.talk(TalkTestData.request))
        XCTAssertEqual(limited.events, [])
        XCTAssertEqual(limited.error as? TalkFailure, TalkFailure.server("rate_limited"))

        // A reply that stops coming ends with "timeout", after the verdicts it did send.
        let slow = await collect(slowAPI.talk(TalkTestData.request))
        XCTAssertEqual(slow.events, [.checked(TalkTestData.check)])
        XCTAssertEqual(slow.error as? TalkFailure, TalkFailure.server("timeout"))
    }

    private func stubbedAPI(_ scenario: String, timeout: Duration = .seconds(10)) throws -> TalkAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TalkStubProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://talk.stub/\(scenario)"))
        return TalkAPI(baseURL: url, session: session, timeout: timeout)
    }

    /// Everything a stream gives, and how it ended. Never waits more than `limit`.
    private func collect(_ stream: AsyncThrowingStream<TalkEvent, Error>,
                         within limit: Duration = .seconds(10)) async -> (events: [TalkEvent], error: Error?) {
        let reader = Task { () -> ([TalkEvent], Error?) in
            var events: [TalkEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                }
            } catch {
                return (events, error)
            }
            if Task.isCancelled { return (events, TalkTestTimedOut()) }
            return (events, nil)
        }
        let watchdog = Task {
            try? await Task.sleep(for: limit)
            reader.cancel()
        }
        let result = await reader.value
        watchdog.cancel()
        return (events: result.0, error: result.1)
    }

    // MARK: Speech

    func testSpeechAcrossAPauseKeepsEveryWord() {
        XCTAssertEqual(SpeechListener.merge(committed: "", latest: "his bishop"), "his bishop")
        // Some systems start afresh after a pause: the first stretch stays in front.
        XCTAssertEqual(SpeechListener.merge(committed: "His bishop eyes h7.", latest: "So h6, and my knight is safe."),
                       "His bishop eyes h7. So h6, and my knight is safe.")
        // Others keep everything: nothing is doubled.
        XCTAssertEqual(SpeechListener.merge(committed: "His bishop eyes h7.", latest: "His bishop eyes h7 so h6"),
                       "His bishop eyes h7 so h6")
        XCTAssertEqual(SpeechListener.merge(committed: "Knight", latest: "Knight takes e5"), "Knight takes e5")
        XCTAssertEqual(SpeechListener.merge(committed: "His bishop eyes h7.", latest: "  "), "His bishop eyes h7.")

        XCTAssertEqual(SpeechListener.level(rms: 0), 0)
        XCTAssertEqual(SpeechListener.level(rms: 0.001), 0, "a quiet room")
        XCTAssertEqual(SpeechListener.level(rms: 1), 1)
        let voice = SpeechListener.level(rms: 0.03)
        XCTAssertGreaterThan(voice, 0.4)
        XCTAssertLessThan(voice, 0.8)
    }

    func testWhatIsSentFitsTheServersLimit() {
        XCTAssertEqual(TalkSession.clipped("  h6  "), "h6")
        XCTAssertEqual(TalkSession.clipped(String(repeating: "a", count: 900)).count, 800)
        // The server counts in UTF-16, where a horse takes two.
        let horses = TalkSession.clipped(String(repeating: "🐴", count: 500))
        XCTAssertEqual(horses.utf16.count, 800)
        XCTAssertEqual(horses.count, 400)
    }

    // MARK: The session

    func testATypedPlanIsCheckedAnsweredAndSpokenInLeosVoice() async throws {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        await waitUntil("Stockfish's numbers are ready") { session.factsReady }

        session.beginTyping()
        XCTAssertEqual(session.phase, .typing)
        session.draft = "  his bishop eyes f2, so I'll castle \n"
        session.sendDraft()
        XCTAssertEqual(session.phase, .checking)
        XCTAssertEqual(session.transcript, "his bishop eyes f2, so I'll castle")
        XCTAssertEqual(session.draft, "")

        await waitUntil("Leo has answered and finished speaking") { session.phase == .answered && !session.isSpeaking }
        XCTAssertEqual(session.check, TalkTestData.check)
        XCTAssertEqual(session.answer, TalkTestData.answerText)
        XCTAssertNil(session.problem)
        XCTAssertNil(session.focus)
        XCTAssertEqual(rig.speaker.played, [TalkTestData.mp3])
        XCTAssertEqual(rig.speaker.said, [])

        XCTAssertEqual(rig.transport.requests.count, 1)
        let request = try XCTUnwrap(rig.transport.requests.first)
        XCTAssertEqual(request.fen, TalkTestData.fen)
        XCTAssertEqual(request.said, "his bishop eyes f2, so I'll castle")
        XCTAssertTrue(request.typed)
        XCTAssertTrue(request.reveal)
        XCTAssertEqual(request.context, .game)
        XCTAssertEqual(request.lastMove, "f8c5")
        XCTAssertTrue(request.voice)
        let facts = try XCTUnwrap(request.facts)
        XCTAssertEqual(facts.depth, 12)
        XCTAssertFalse(facts.moves.isEmpty)
        XCTAssertEqual(facts.threats.count, 6)
    }

    func testASpokenPlanIsSentWhenTheButtonComesUp() async throws {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        XCTAssertTrue(session.canListen)
        XCTAssertEqual(rig.listener.permissionRequests, 0, "opening never asks")

        session.beginListening()
        await waitUntil("listening") { session.phase == .listening }
        XCTAssertEqual(rig.listener.permissionRequests, 1)
        XCTAssertEqual(rig.listener.starts, 1)

        rig.listener.hear("his bishop eyes f2", level: 0.7)
        XCTAssertEqual(session.transcript, "his bishop eyes f2")
        XCTAssertEqual(session.level, 0.7, accuracy: 0.0001)
        rig.listener.hear("his bishop eyes f2 so I'll castle", level: 0.3)

        session.endListening()
        XCTAssertEqual(session.phase, .checking)
        XCTAssertEqual(session.level, 0)
        XCTAssertEqual(rig.listener.stops, 1)

        await waitUntil("Leo has answered") { session.phase == .answered }
        let request = try XCTUnwrap(rig.transport.requests.first)
        XCTAssertFalse(request.typed)
        XCTAssertEqual(request.said, "his bishop eyes f2 so I'll castle")
        XCTAssertEqual(session.transcript, "his bishop eyes f2 so I'll castle")
        XCTAssertEqual(session.check, TalkTestData.check)

        // Another go: no second prompt, and listening starts at once.
        session.beginListening()
        XCTAssertEqual(session.phase, .listening)
        XCTAssertNil(session.check)
        XCTAssertNil(session.answer)
        XCTAssertEqual(session.transcript, "")
        XCTAssertEqual(rig.listener.permissionRequests, 1)
        XCTAssertEqual(rig.listener.starts, 2)
        session.cancelListening()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertGreaterThanOrEqual(rig.listener.cancels, 1)
        XCTAssertEqual(rig.transport.requests.count, 1)
    }

    func testTheRecognizersLastWordsAreKept() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.lastWordsGrace = .milliseconds(400)
        session.open()
        session.beginListening()
        await waitUntil("listening") { session.phase == .listening }
        rig.listener.hear("his bishop eyes")
        session.endListening()

        // The final result comes just after the button is up, with the last word.
        rig.listener.hear("His bishop eyes f2.")
        XCTAssertEqual(session.transcript, "His bishop eyes f2.")
        await waitUntil("Leo has answered") { session.phase == .answered }
        XCTAssertEqual(rig.transport.requests.first?.said, "His bishop eyes f2.")

        // Once it has gone, nothing changes what was said.
        rig.listener.hear("something else")
        XCTAssertEqual(session.transcript, "His bishop eyes f2.")
    }

    func testNothingHeardGoesBackToReady() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        session.beginListening()
        await waitUntil("listening") { session.phase == .listening }
        rig.listener.heard = "   "
        session.endListening()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.transcript, "")
        XCTAssertEqual(rig.listener.cancels, 1)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(rig.transport.requests.isEmpty)
    }

    func testNoPermissionTurnsToTypingWithoutAFuss() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        rig.listener.allows = false
        let session = rig.session
        session.open()
        XCTAssertTrue(session.canListen)
        session.beginListening()
        await waitUntil("the keyboard is up") { session.phase == .typing }
        XCTAssertFalse(session.canListen)
        XCTAssertNil(session.problem)
        XCTAssertEqual(rig.listener.starts, 0)
        session.endListening()
        XCTAssertEqual(session.phase, .typing)
        session.beginListening()
        XCTAssertEqual(session.phase, .typing)
        XCTAssertEqual(rig.listener.permissionRequests, 1, "asked once")
    }

    func testAllowingWhileTheButtonIsUpWaitsForTheNextHold() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        session.beginListening()
        // The prompt took the press: the button is up before the answer comes.
        session.endListening()
        await waitUntil("the prompt is answered") { rig.listener.permissionRequests == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(rig.listener.starts, 0)
        session.beginListening()
        XCTAssertEqual(session.phase, .listening)
        XCTAssertEqual(rig.listener.starts, 1)
        session.close()
    }

    func testNoSpeechOnTheDeviceOffersTypingOnly() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        rig.listener.isAvailable = false
        rig.session.open()
        XCTAssertFalse(rig.session.canListen)
        rig.session.beginListening()
        XCTAssertEqual(rig.session.phase, .typing)
        XCTAssertEqual(rig.listener.permissionRequests, 0)

        // A microphone that won't start (a call, say) also brings up the keyboard.
        let busy = TalkTestRig(TalkTestData.fullAnswer)
        busy.listener.startError = SpeechListenerError.audioBusy
        busy.session.open()
        busy.session.beginListening()
        await waitUntil("the keyboard is up") { busy.session.phase == .typing }
        XCTAssertNil(busy.session.problem)
        XCTAssertTrue(busy.session.canListen, "it may work next time")
    }

    func testFailuresAreSaidInPlainWords() async {
        let offline = "Leo needs the internet to check your plan."
        let couldNot = "Leo couldn't check that one. Try again."
        let cases: [(String, [TalkTestTransport.Step], String)] = [
            ("offline", [.fail(TalkFailure.offline)], offline),
            ("no network", [.fail(URLError(.notConnectedToInternet))], offline),
            ("too many", [.fail(TalkFailure.server("rate_limited"))], "Leo needs a moment. Try again in a minute."),
            ("the day's talks", [.fail(TalkFailure.server("daily_limit"))],
             "Leo has checked a lot of plans today. Try again tomorrow."),
            ("unusable words", [.fail(TalkFailure.server("bad_request"))], "Leo didn't catch that. Try again."),
            ("no key", [.fail(TalkFailure.server("not_configured"))], couldNot),
            ("unreadable", [.fail(TalkFailure.badResponse)], couldNot),
            ("upstream", [.event(.failed("upstream"))], couldNot),
            ("timeout", [.event(.failed("timeout"))], couldNot),
            ("internal", [.event(.failed("internal"))], couldNot),
            ("no verdicts", [.event(.answer(TalkAnswer(text: "Hello."))), .event(.done)], couldNot),
            ("nothing at all", [], couldNot),
        ]
        for (name, steps, words) in cases {
            let rig = TalkTestRig(steps)
            rig.session.open()
            rig.typeAndSend("h6 and my knight is safe")
            await waitUntil("\(name) fails") { rig.session.phase == .failed }
            XCTAssertEqual(rig.session.problem, words, name)
            XCTAssertNil(rig.session.check, name)
            XCTAssertNil(rig.session.answer, name)
            XCTAssertFalse(rig.session.isSpeaking, name)
            XCTAssertTrue(rig.speaker.played.isEmpty, name)
            XCTAssertTrue(rig.speaker.said.isEmpty, name)
            rig.session.close()
        }
    }

    func testAfterAFailureTheWordsAreThereToTryAgain() async {
        let rig = TalkTestRig([.fail(TalkFailure.offline)])
        let session = rig.session
        session.open()
        rig.typeAndSend("h6, his bishop eyes h7")
        await waitUntil("it fails") { session.phase == .failed }
        session.beginTyping()
        XCTAssertEqual(session.phase, .typing)
        XCTAssertEqual(session.draft, "h6, his bishop eyes h7")
        XCTAssertNil(session.problem)
        XCTAssertEqual(session.transcript, "")
    }

    func testVerdictsStayWhenTheRestOfTheAnswerFails() async {
        // The server fails after the verdicts: they stand, and a short answer is said.
        let rig = TalkTestRig([.event(.checked(TalkTestData.check)), .event(.failed("upstream"))])
        rig.session.open()
        rig.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { rig.session.phase == .answered && !rig.session.isSpeaking }
        XCTAssertEqual(rig.session.check, TalkTestData.check)
        XCTAssertNil(rig.session.problem)
        XCTAssertEqual(rig.session.answer, "You're right about both.")
        XCTAssertEqual(rig.speaker.said, ["You're right about both."])

        // The connection drops after Leo's words: they stand too, in the device's voice.
        let dropped = TalkTestRig([.event(.checked(TalkTestData.check)),
                                   .event(.answer(TalkAnswer(text: TalkTestData.answerText))),
                                   .fail(TalkFailure.offline)])
        dropped.session.open()
        dropped.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { dropped.session.phase == .answered && !dropped.session.isSpeaking }
        XCTAssertEqual(dropped.session.answer, TalkTestData.answerText)
        XCTAssertNil(dropped.session.problem)
        XCTAssertEqual(dropped.speaker.said, [TalkTestData.answerText])
        XCTAssertEqual(dropped.speaker.played, [])
    }

    func testTheDeviceVoiceSpeaksWhenLeosVoiceIsMissing() async {
        let unavailable = TalkTestRig([.event(.checked(TalkTestData.check)),
                                       .event(.answer(TalkAnswer(text: TalkTestData.answerText))),
                                       .event(.voice(TalkVoice(audio: nil, unavailable: "budget"))), .event(.done)])
        unavailable.session.open()
        unavailable.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { unavailable.session.phase == .answered && !unavailable.session.isSpeaking }
        XCTAssertEqual(unavailable.speaker.said, [TalkTestData.answerText])
        XCTAssertEqual(unavailable.speaker.played, [])

        let noVoiceLine = TalkTestRig([.event(.checked(TalkTestData.check)),
                                       .event(.answer(TalkAnswer(text: TalkTestData.answerText))), .event(.done)])
        noVoiceLine.session.open()
        noVoiceLine.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { noVoiceLine.session.phase == .answered && !noVoiceLine.session.isSpeaking }
        XCTAssertEqual(noVoiceLine.speaker.said, [TalkTestData.answerText])
        XCTAssertEqual(noVoiceLine.speaker.played, [])
    }

    func testAMutedCoachStaysQuiet() async throws {
        CoachVoice.shared.isMuted = true
        let rig = TalkTestRig([.event(.checked(TalkTestData.check)),
                               .event(.answer(TalkAnswer(text: TalkTestData.answerText))), .event(.done)])
        rig.session.open()
        rig.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { rig.session.phase == .answered }
        let request = try XCTUnwrap(rig.transport.requests.first)
        XCTAssertFalse(request.voice, "no voice is asked for")
        XCTAssertEqual(rig.session.answer, TalkTestData.answerText)
        XCTAssertFalse(rig.session.isSpeaking)
        XCTAssertEqual(rig.speaker.said, [])
        XCTAssertEqual(rig.speaker.played, [])
    }

    func testTalkAgainStartsFreshAndKeepsTheNumbers() async throws {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        rig.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo has answered") { session.phase == .answered && !session.isSpeaking }
        session.focus = .claim("c2")

        session.talkAgain()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.transcript, "")
        XCTAssertNil(session.check)
        XCTAssertNil(session.answer)
        XCTAssertNil(session.problem)
        XCTAssertNil(session.focus)
        XCTAssertEqual(session.level, 0)
        XCTAssertTrue(session.factsReady)

        rig.typeAndSend("h6")
        await waitUntil("Leo has answered again") { session.phase == .answered && !session.isSpeaking }
        let requests = rig.transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.said, "h6")
        XCTAssertNotNil(requests.last?.facts)
        XCTAssertEqual(requests.last?.facts, requests.first?.facts)
        let calls = await rig.engine.calls
        XCTAssertEqual(calls.count, 2, "the moves and the threats, worked out once")
    }

    func testEverySendIsCountedForTheGame() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        var sends = 0
        session.onSend = { sends += 1 }
        session.open()
        XCTAssertEqual(sends, 0, "opening the talk isn't help")

        rig.typeAndSend("his bishop eyes f2")
        XCTAssertEqual(sends, 1)
        await waitUntil("Leo has answered") { session.phase == .answered && !session.isSpeaking }
        session.talkAgain()
        XCTAssertEqual(sends, 1, "talking again counts once the words go")
        rig.typeAndSend("h6")
        XCTAssertEqual(sends, 2)
        await waitUntil("Leo has answered again") { session.phase == .answered && !session.isSpeaking }
    }

    func testStopSpeakingQuietsLeo() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        rig.speaker.holds = true
        let session = rig.session
        session.open()
        rig.typeAndSend("his bishop eyes f2")
        await waitUntil("Leo is speaking") { session.phase == .answered && session.isSpeaking }
        let stops = rig.speaker.stops
        session.stopSpeaking()
        XCTAssertFalse(session.isSpeaking)
        XCTAssertEqual(rig.speaker.stops, stops + 1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(session.isSpeaking)
        XCTAssertEqual(rig.speaker.played, [TalkTestData.mp3])
        XCTAssertEqual(rig.speaker.said, [], "quiet means quiet: no device voice afterwards")
        XCTAssertEqual(session.phase, .answered)
    }

    func testClosingMidRequestStopsEverything() async {
        let rig = TalkTestRig([.event(.checked(TalkTestData.check)), .hang,
                               .event(.answer(TalkAnswer(text: TalkTestData.answerText))), .event(.done)])
        let session = rig.session
        session.open()
        rig.typeAndSend("his bishop eyes f2")
        await waitUntil("the verdicts arrive") { session.check != nil }

        session.close()
        await waitUntil("the request is stopped") { rig.transport.cancellations == 1 }
        XCTAssertGreaterThanOrEqual(rig.listener.cancels, 1)
        XCTAssertGreaterThanOrEqual(rig.speaker.stops, 1)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.phase, .checking, "nothing moves on after closing")
        XCTAssertNil(session.answer)
        XCTAssertFalse(session.isSpeaking)
        XCTAssertEqual(rig.speaker.played, [])
        XCTAssertEqual(rig.speaker.said, [])

        // And nothing starts again.
        session.talkAgain()
        session.beginListening()
        rig.typeAndSend("h6")
        XCTAssertEqual(session.phase, .checking)
        XCTAssertEqual(rig.listener.permissionRequests, 0)
        XCTAssertEqual(rig.listener.starts, 0)
        XCTAssertEqual(rig.transport.requests.count, 1)
    }

    func testClosingWhileListeningStopsTheMicrophone() async {
        let rig = TalkTestRig(TalkTestData.fullAnswer)
        let session = rig.session
        session.open()
        session.beginListening()
        await waitUntil("listening") { session.phase == .listening }
        rig.listener.hear("his bishop", level: 0.8)

        session.close()
        XCTAssertEqual(rig.listener.cancels, 1)
        XCTAssertEqual(session.level, 0)
        rig.listener.lateResult("his bishop eyes h7")
        XCTAssertEqual(session.transcript, "his bishop", "a late result changes nothing")
        session.endListening()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(rig.transport.requests.isEmpty)
    }

    func testASendWaitsForTheNumbersButNotForever() async {
        // Numbers still being worked out: the request waits for them.
        let slow = TalkTestRig(TalkTestData.fullAnswer, engine: TalkTestEngine(delay: .milliseconds(300)))
        slow.session.open()
        slow.typeAndSend("h6")
        XCTAssertFalse(slow.session.factsReady)
        await waitUntil("Leo has answered") { slow.session.phase == .answered }
        XCTAssertNotNil(slow.transport.requests.first?.facts)
        XCTAssertTrue(slow.session.factsReady)

        // Numbers that don't come in time: the request goes without them.
        let stuck = TalkTestRig(TalkTestData.fullAnswer, engine: TalkTestEngine(delay: .seconds(30)))
        stuck.session.factsWait = .milliseconds(200)
        stuck.session.open()
        stuck.typeAndSend("h6")
        await waitUntil("Leo has answered") { stuck.session.phase == .answered }
        XCTAssertEqual(stuck.transport.requests.count, 1)
        XCTAssertNil(stuck.transport.requests.first?.facts)
        XCTAssertFalse(stuck.session.factsReady)
        stuck.session.close()
    }

    func testAPreviewShowsOneMomentAndStartsNothing() {
        let preview = TalkSession.preview(fen: TalkTestData.fen, player: .white, phase: .answered, transcript: "h6",
                                          check: TalkTestData.check, answer: "Right.", canListen: false)
        XCTAssertEqual(preview.phase, .answered)
        XCTAssertEqual(preview.transcript, "h6")
        XCTAssertEqual(preview.check, TalkTestData.check)
        XCTAssertEqual(preview.answer, "Right.")
        XCTAssertTrue(preview.factsReady)
        XCTAssertFalse(preview.canListen)
        XCTAssertFalse(preview.isSpeaking)
        // The panel opening it changes nothing: no engine, no microphone check.
        preview.open()
        XCTAssertFalse(preview.canListen)
        XCTAssertEqual(preview.phase, .answered)
        preview.close()
    }
}
