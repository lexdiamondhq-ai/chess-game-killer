import ChessKit
import XCTest
@testable import ChessGameKiller

/// Challenge a friend without a network: links, the server's words, clocks, the board following
/// the server, and the list of friend games. Every server reply comes from `FakeChallengeAPI`.
@MainActor
final class ChallengeTests: XCTestCase {

    private var defaults: UserDefaults!
    private static let suite = "ChallengeTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: Self.suite)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suite)
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

    private func placement(_ fen: String) -> String {
        fen.split(separator: " ").prefix(2).joined(separator: " ")
    }

    // MARK: Links and codes

    func testReadsInviteLinksAppLinksAndTypedCodes() throws {
        let invite = try XCTUnwrap(URL(string: "https://play.chess-game-killer.workers.dev/c/7KQ2XM"))
        XCTAssertEqual(ChallengeLink.code(from: invite), "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(from: try XCTUnwrap(URL(string: "https://play.chess-game-killer.workers.dev/c/7kq2xm"))), "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(from: try XCTUnwrap(URL(string: "chessgamekiller://c/7KQ2XM"))), "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(from: try XCTUnwrap(URL(string: "chessgamekiller://challenge/7kq2xm"))), "7KQ2XM")
        XCTAssertNil(ChallengeLink.code(from: try XCTUnwrap(URL(string: "https://example.com/c/7KQ2XM"))))
        XCTAssertNil(ChallengeLink.code(from: try XCTUnwrap(URL(string: "https://play.chess-game-killer.workers.dev/7KQ2XM"))))
        XCTAssertNil(ChallengeLink.code(from: try XCTUnwrap(URL(string: "chessgamekiller://c/7KQ2X"))), "five characters")
        XCTAssertNil(ChallengeLink.code(from: try XCTUnwrap(URL(string: "chessgamekiller://c/7KQ2XO"))), "O isn't in the alphabet")
        XCTAssertNil(ChallengeLink.code(from: try XCTUnwrap(URL(string: "chessgamekiller://settings"))))

        XCTAssertEqual(ChallengeLink.code(fromText: "7kq 2xm"), "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(fromText: " 7KQ-2XM\n"), "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(fromText: "Alex challenged you. Tap to play: https://play.chess-game-killer.workers.dev/c/7KQ2XM"),
                       "7KQ2XM")
        XCTAssertEqual(ChallengeLink.code(fromText: "play.chess-game-killer.workers.dev/c/7KQ2XM"), "7KQ2XM")
        XCTAssertNil(ChallengeLink.code(fromText: "hello"))
        XCTAssertNil(ChallengeLink.code(fromText: "1LI0O5"), "look-alike characters aren't used")

        XCTAssertEqual(ChallengeLink.inviteURL(for: "7KQ2XM").absoluteString, "https://play.chess-game-killer.workers.dev/c/7KQ2XM")
        XCTAssertEqual(ChallengeLink.appURL(for: "7KQ2XM").absoluteString, "chessgamekiller://c/7KQ2XM")
        XCTAssertEqual(ChallengeLink.spaced("7KQ2XM"), "7KQ 2XM")
        XCTAssertEqual(ChallengeLink.code(from: ChallengeLink.appURL(for: "7KQ2XM")), "7KQ2XM")
    }

    // MARK: The server's words

    private static let protocolSample = #"""
    {
      "code": "7KQ2XM",
      "status": "waiting",
      "createdAt": 1761187200000,
      "updatedAt": 1761187200000,
      "clock": { "initial": 600, "increment": 0 },
      "creator": "white",
      "white": { "name": "Alex", "seated": true, "online": true, "away": null, "screenshots": 0, "recordings": 0 },
      "black": { "name": null, "seated": false, "online": false, "away": null, "screenshots": 0, "recordings": 0 },
      "moves": ["e2e4", "e7e5"],
      "san": ["e4", "e5"],
      "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
      "turn": "white",
      "clocks": { "white": 600000, "black": 600000, "running": null, "since": null },
      "drawOffer": null,
      "rematch": null,
      "result": null,
      "leaveGraceMs": 20000,
      "now": 1761187200123
    }
    """#

    func testDecodesTheGameStateFromTheProtocol() throws {
        let reply = try JSONDecoder().decode(FriendGameReply.self, from: Data(#"{"game":\#(Self.protocolSample)}"#.utf8))
        let game = reply.game
        XCTAssertEqual(game.code, "7KQ2XM")
        XCTAssertEqual(game.status, .waiting)
        XCTAssertEqual(game.createdAt, 1_761_187_200_000)
        XCTAssertEqual(game.clock, FriendClock(initial: 600, increment: 0))
        XCTAssertEqual(game.clock?.timeControl, .rapid10)
        XCTAssertEqual(game.creator, .white)
        XCTAssertEqual(game.white.name, "Alex")
        XCTAssertTrue(game.white.seated)
        XCTAssertTrue(game.white.online)
        XCTAssertNil(game.white.away)
        XCTAssertNil(game.black.name)
        XCTAssertFalse(game.black.seated)
        XCTAssertEqual(game.moves, ["e2e4", "e7e5"])
        XCTAssertEqual(game.san, ["e4", "e5"])
        XCTAssertEqual(game.fen, "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        XCTAssertEqual(game.turn, .white)
        XCTAssertEqual(game.clocks, FriendGameState.Clocks(white: 600_000, black: 600_000, running: nil, since: nil))
        XCTAssertNil(game.drawOffer)
        XCTAssertNil(game.rematch)
        XCTAssertNil(game.result)
        XCTAssertEqual(game.leaveGraceMs, 20_000)
        XCTAssertEqual(game.now, 1_761_187_200_123)
    }

    func testANewerServerNeverBreaksTheApp() throws {
        // Fields this version doesn't know are ignored, missing ones fall back, an unknown reason is kept.
        let json = #"""
        {"code": "abc234", "status": "over", "spectators": 3, "theme": {"board": "walnut"},
         "white": {"name": "Alex", "seated": true, "rating": 1500},
         "black": {"name": "Sam", "seated": true, "badges": ["early"]},
         "moves": ["e2e4"], "clock": null,
         "result": {"winner": null, "reason": "meteor_strike", "witnesses": 2}}
        """#
        let game = try JSONDecoder().decode(FriendGameState.self, from: Data(json.utf8))
        XCTAssertEqual(game.code, "ABC234")
        XCTAssertEqual(game.status, .over)
        XCTAssertNil(game.clock)
        XCTAssertNil(game.clocks)
        XCTAssertEqual(game.turn, .black, "with no turn given, it follows from the moves")
        XCTAssertEqual(game.fen, Position.standard.fen)
        XCTAssertEqual(game.leaveGraceMs, 20_000)
        XCTAssertEqual(game.white.screenshots, 0)
        XCTAssertEqual(game.result?.reason, .other("meteor_strike"))
        XCTAssertTrue(game.result?.reason.wasPlayed ?? false)
        XCTAssertEqual(FriendResultWords.short(try XCTUnwrap(game.result), me: .white), "Draw · Meteor Strike")

        // Every reason the protocol names, read and written back the same.
        for raw in ["checkmate", "resign", "timeout", "left", "stalemate", "repetition", "fifty_moves", "insufficient",
                    "agreement", "timeout_insufficient", "aborted", "cancelled", "expired"] {
            let reason = FriendGameState.Reason(rawValue: raw)
            XCTAssertNotEqual(reason, .other(raw), raw)
            XCTAssertEqual(reason.rawValue, raw)
        }
    }

    func testReadsTheRepliesAndTheLiveMessages() throws {
        let created = try JSONDecoder().decode(CreatedChallenge.self, from: Data(#"""
        {"code": "7KQ2XM", "url": "https://play.chess-game-killer.workers.dev/c/7KQ2XM",
         "appUrl": "chessgamekiller://c/7KQ2XM", "seat": "black", "token": "0123456789abcdef0123456789abcdef",
         "game": \#(Self.protocolSample)}
        """#.utf8))
        XCTAssertEqual(created.seat, .black)
        XCTAssertEqual(created.token, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(created.inviteURL.absoluteString, "https://play.chess-game-killer.workers.dev/c/7KQ2XM")

        let ticket = try JSONDecoder().decode(SeatTicket.self, from: Data(#"""
        {"seat": "black", "token": "fedcba9876543210fedcba9876543210", "game": \#(Self.protocolSample)}
        """#.utf8))
        XCTAssertEqual(ticket.seat, .black)

        let error = try JSONDecoder().decode(ChallengeErrorReply.self, from: Data(#"""
        {"error": "stale", "message": "The game moved on.", "game": \#(Self.protocolSample)}
        """#.utf8))
        XCTAssertEqual(error.error, "stale")
        XCTAssertEqual(error.game?.moves, ["e2e4", "e7e5"])
        // A game the app can't read never hides the reason.
        let broken = try JSONDecoder().decode(ChallengeErrorReply.self, from: Data(#"{"error": "seat_taken", "game": {"oops": 1}}"#.utf8))
        XCTAssertEqual(broken.error, "seat_taken")
        XCTAssertNil(broken.game)

        let notice = ChallengeLiveMessage.decode(#"{"type": "notice", "kind": "screenshot", "seat": "black", "at": 5}"#)
        XCTAssertEqual(notice, .notice(ChallengeNotice(kind: .screenshot, seat: .black, at: 5)))
        let unknown = ChallengeLiveMessage.decode(#"{"type": "notice", "kind": "confetti", "seat": "white"}"#)
        XCTAssertEqual(unknown, .notice(ChallengeNotice(kind: nil, seat: .white, at: 0)))
        guard case .state(let state)? = ChallengeLiveMessage.decode(#"{"type": "state", "game": \#(Self.protocolSample)}"#) else {
            return XCTFail("a state message should decode")
        }
        XCTAssertEqual(state.code, "7KQ2XM")
        XCTAssertNil(ChallengeLiveMessage.decode("pong"))
        XCTAssertNil(ChallengeLiveMessage.decode(#"{"type": "hello"}"#))
    }

    func testErrorsInPlainWords() {
        let serverError = ChallengeError.server(status: 500, code: "server_error", message: nil, game: nil)
        XCTAssertEqual(serverError.message, "Something went wrong on our side. Try again in a moment.")
        XCTAssertTrue(serverError.isRetryable)
        XCTAssertTrue(ChallengeError.server(status: 429, code: "rate_limited", message: nil, game: nil).isRetryable)
        XCTAssertTrue(ChallengeError.unreachable.isRetryable)
        XCTAssertFalse(ChallengeError.server(status: 409, code: "seat_taken", message: nil, game: nil).isRetryable)
        XCTAssertTrue(ChallengeError.server(status: 404, code: "not_found", message: nil, game: nil).isNotFound)
        XCTAssertEqual(ChallengeError.server(status: 418, code: "teapot", message: "Short and stout.", game: nil).message,
                       "Short and stout.")
        XCTAssertEqual(ChallengeError.server(status: 409, code: "not_your_turn", message: nil, game: nil).message,
                       "It isn't your move yet.")
    }

    // MARK: Words

    func testEveryEndingInPlainWordsFromBothSides() {
        func words(_ reason: FriendGameState.Reason, _ winner: FriendSeat?, me: FriendSeat, flagged: FriendSeat? = nil) -> String {
            FriendResultWords.headline(FriendGameState.Result(winner: winner, reason: reason), me: me, opponent: "Sam",
                                       flagged: flagged, creator: .white)
        }
        XCTAssertEqual(words(.checkmate, .white, me: .white), "Checkmate. You win")
        XCTAssertEqual(words(.checkmate, .white, me: .black), "Checkmate. Sam wins")
        XCTAssertEqual(words(.resign, .white, me: .white), "Sam resigned. You win")
        XCTAssertEqual(words(.resign, .white, me: .black), "You resigned. Sam wins")
        XCTAssertEqual(words(.timeout, .black, me: .black), "Sam ran out of time. You win")
        XCTAssertEqual(words(.timeout, .black, me: .white), "You lost on time")
        XCTAssertEqual(words(.left, .white, me: .white), "Sam left the game. You win")
        XCTAssertEqual(words(.left, .white, me: .black), "You left the game. Sam wins")
        for me in FriendSeat.allCases {
            XCTAssertEqual(words(.stalemate, nil, me: me), "Draw by stalemate")
            XCTAssertEqual(words(.repetition, nil, me: me), "Draw by repetition")
            XCTAssertEqual(words(.fiftyMoves, nil, me: me), "Draw by the 50-move rule")
            XCTAssertEqual(words(.insufficient, nil, me: me), "Draw. Neither side can checkmate")
            XCTAssertEqual(words(.agreement, nil, me: me), "Draw by agreement")
            XCTAssertEqual(words(.aborted, nil, me: me), "Game aborted")
            XCTAssertEqual(words(.expired, nil, me: me), "This challenge expired")
        }
        XCTAssertEqual(words(.timeoutInsufficient, nil, me: .white, flagged: .white), "Draw. Your time ran out, but Sam couldn't mate")
        XCTAssertEqual(words(.timeoutInsufficient, nil, me: .black, flagged: .white), "Draw. Sam's time ran out, but you couldn't mate")
        XCTAssertEqual(words(.cancelled, nil, me: .white), "You cancelled the challenge")
        XCTAssertEqual(words(.cancelled, nil, me: .black), "Sam cancelled the challenge")
        XCTAssertEqual(words(.other("forfeit"), .black, me: .black), "You win")
        XCTAssertEqual(words(.other("forfeit"), .black, me: .white), "Sam wins")

        let mate = FriendGameState.Result(winner: .white, reason: .checkmate)
        XCTAssertEqual(FriendResultWords.short(mate, me: .white), "You won · Checkmate")
        XCTAssertEqual(FriendResultWords.short(mate, me: .black), "You lost · Checkmate")
        XCTAssertEqual(FriendResultWords.short(FriendGameState.Result(winner: nil, reason: .repetition), me: .white), "Draw · Repetition")
        XCTAssertEqual(FriendResultWords.short(FriendGameState.Result(winner: .black, reason: .timeout), me: .black), "You won · On time")
        XCTAssertEqual(FriendResultWords.short(FriendGameState.Result(winner: nil, reason: .aborted), me: .black), "Aborted")

        let game = FriendGameState.sample(moves: ["e2e4", "e7e5", "g1f3"])
        XCTAssertEqual(FriendResultWords.detail(game), "Rapid · 10+0 · 2 moves")
        XCTAssertEqual(FriendResultWords.detail(FriendGameState.sample(clock: nil)), "No clock")
    }

    func testTheInviteSaysWhoWhatClockAndWhichSide() throws {
        let url = try XCTUnwrap(URL(string: "https://play.chess-game-killer.workers.dev/c/7KQ2XM"))
        let tenMinutes = FriendClock(initial: 600, increment: 0)
        XCTAssertEqual(ChallengeInviteText.message(from: "Alex", clock: tenMinutes, friendPlays: .black, url: url),
                       "Alex challenged you to chess on Chess Game Killer. 10 minutes each, you play Black. Tap to play: https://play.chess-game-killer.workers.dev/c/7KQ2XM")
        XCTAssertEqual(ChallengeInviteText.subject(from: "Alex"), "Alex challenged you to a game of chess")
        XCTAssertEqual(ChallengeInviteText.lead(from: "  ", clock: FriendClock(.blitz3Plus2), friendPlays: .white),
                       "A friend challenged you to chess on Chess Game Killer. 3 minutes each plus 2 seconds a move, you play White.")
        XCTAssertEqual(ChallengeInviteText.lead(from: "Alex", clock: nil, friendPlays: .white),
                       "Alex challenged you to chess on Chess Game Killer. No clock, you play White.")
        XCTAssertTrue(ChallengeInviteText.emailBody(from: "Alex", clock: tenMinutes, friendPlays: .black, url: url, code: "7KQ2XM")
            .hasSuffix("enter the code 7KQ 2XM."))

        let content = ChallengeInviteContent(game: FriendGame.sample(FriendGameState.sample(status: .waiting), seat: .white), name: "Alex")
        XCTAssertEqual(content.url, url)
        XCTAssertEqual(content.subject, "Alex challenged you to a game of chess")
        XCTAssertTrue(content.message.contains("you play Black"))

        XCTAssertEqual(ChallengeName.clean("  Sam   the\tGreat \n"), "Sam the Great")
        XCTAssertEqual(ChallengeName.clean(String(repeating: "x", count: 40)).count, ChallengeName.maxLength)
        XCTAssertEqual(ChallengeName.clean("\u{7}"), "")
        // As the server does it: odd spaces are plain ones, marks that flip the text and invisible ones go, emoji stay whole.
        XCTAssertEqual(ChallengeName.clean("Ana\u{00A0}Lu"), "Ana Lu")
        XCTAssertEqual(ChallengeName.clean("Sam\u{202E}"), "Sam")
        XCTAssertEqual(ChallengeName.clean("A\u{200B} B"), "A B")
        XCTAssertEqual(ChallengeName.clean("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"), "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
    }

    func testTheAppsClocksMatchTheServersClocks() {
        XCTAssertEqual(FriendClock(.rapid10), FriendClock(initial: 600, increment: 0))
        XCTAssertEqual(FriendClock(.blitz3Plus2), FriendClock(initial: 180, increment: 2))
        XCTAssertEqual(FriendClock(.rapid15Plus10), FriendClock(initial: 900, increment: 10))
        XCTAssertNil(FriendClock(.unlimited))
        for control in TimeControl.allCases where control.isTimed {
            XCTAssertEqual(FriendClock(control)?.timeControl, control)
            XCTAssertEqual(FriendClock(control)?.label, control.rawValue)
        }
        XCTAssertEqual(FriendClock(initial: 600, increment: 0).phrase, "10 minutes each")
        XCTAssertEqual(FriendClock(initial: 60, increment: 1).phrase, "1 minute each plus 1 second a move")
        XCTAssertEqual(FriendClock(.blitz5)?.kind, "Blitz")
        XCTAssertEqual(FriendClock(.rapid15Plus10)?.kind, "Rapid")
    }

    // MARK: Time

    func testTheServersTimeAsThePhoneReckonsIt() {
        let start = ContinuousClock.now
        var clock = ChallengeServerClock(serverNow: 1_000_000, at: start)
        XCTAssertEqual(clock.now(at: start + .milliseconds(1500)), 1_001_500, accuracy: 0.001)
        // A reading that took longer to arrive is behind: the earlier one stands.
        clock.note(serverNow: 1_000_900, at: start + .seconds(1))
        XCTAssertEqual(clock.now(at: start + .seconds(1)), 1_001_000, accuracy: 0.001)
        // One that is ahead is nearer the truth.
        clock.note(serverNow: 1_001_400, at: start + .seconds(1))
        XCTAssertEqual(clock.now(at: start + .seconds(2)), 1_002_400, accuracy: 0.001)
        // After half a minute even a reading behind is taken, so the two never drift apart.
        clock.note(serverNow: 1_030_000, at: start + .seconds(40))
        XCTAssertEqual(clock.now(at: start + .seconds(40)), 1_030_000, accuracy: 0.001)
    }

    func testClockArithmetic() {
        let clocks = FriendGameState.Clocks(white: 300_000, black: 200_000, running: .white, since: 1_000_000)
        XCTAssertEqual(FriendClockMath.remaining(clocks, for: .white, serverNow: 1_004_500), 295_500)
        XCTAssertEqual(FriendClockMath.remaining(clocks, for: .black, serverNow: 1_004_500), 200_000)
        XCTAssertEqual(FriendClockMath.remaining(clocks, for: .white, serverNow: 2_000_000), 0)
        XCTAssertEqual(FriendClockMath.remaining(clocks, for: .white, serverNow: 999_000), 300_000, "never more than was left")
        XCTAssertEqual(FriendClockMath.label(295_500), "4:56")
        XCTAssertEqual(FriendClockMath.label(9_400), "0:09.4")
        XCTAssertEqual(FriendClockMath.label(-5), "0:00.0")
    }

    func testLeavingCountsOnlyInATimedGameUnderWay() {
        var game = FriendGameState.sample(moves: ["e2e4", "e7e5", "g1f3"])
        game.black.away = game.now - 6_000
        XCTAssertTrue(FriendClockMath.leaveRuleApplies(game))
        XCTAssertEqual(FriendClockMath.awayDeadline(game, seat: .black), game.now + 14_000)
        XCTAssertEqual(FriendClockMath.awaySecondsLeft(game, seat: .black, serverNow: game.now), 14)
        XCTAssertEqual(FriendClockMath.awaySecondsLeft(game, seat: .black, serverNow: game.now + 13_100), 1)
        XCTAssertEqual(FriendClockMath.awaySecondsLeft(game, seat: .black, serverNow: game.now + 30_000), 0)
        XCTAssertNil(FriendClockMath.awaySecondsLeft(game, seat: .white, serverNow: game.now))

        // An absence that began before both sides had moved counts from when they had.
        var early = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        early.white.away = early.now - 60_000
        early.clocks?.since = early.now - 5_000
        XCTAssertEqual(FriendClockMath.awayDeadline(early, seat: .white), early.now + 15_000)

        var untimed = game
        untimed.clock = nil
        XCTAssertFalse(FriendClockMath.leaveRuleApplies(untimed))
        XCTAssertNil(FriendClockMath.awayDeadline(untimed, seat: .black))
        var opening = FriendGameState.sample(moves: ["e2e4"])
        opening.black.away = opening.now
        XCTAssertNil(FriendClockMath.awayDeadline(opening, seat: .black), "not before both sides have moved")
    }

    // MARK: The connection

    func testTheLiveConnectionStopsForGoodOnlyWhenTheServerSaysSo() throws {
        XCTAssertEqual(ChallengeSocket.end(closeCode: 4001, httpStatus: nil), .openElsewhere)
        XCTAssertEqual(ChallengeSocket.end(closeCode: 4002, httpStatus: nil), .refused)
        XCTAssertEqual(ChallengeSocket.end(closeCode: 4000, httpStatus: nil), .refused)
        XCTAssertEqual(ChallengeSocket.end(closeCode: 4999, httpStatus: nil), .refused)
        XCTAssertEqual(ChallengeSocket.end(closeCode: 0, httpStatus: 401), .refused)
        XCTAssertEqual(ChallengeSocket.end(closeCode: 0, httpStatus: 404), .refused)
        XCTAssertNil(ChallengeSocket.end(closeCode: 1000, httpStatus: nil))
        XCTAssertNil(ChallengeSocket.end(closeCode: 1006, httpStatus: nil))
        XCTAssertNil(ChallengeSocket.end(closeCode: 0, httpStatus: 429), "a full game is tried again later")
        XCTAssertNil(ChallengeSocket.end(closeCode: 0, httpStatus: 500))

        XCTAssertEqual(ChallengeSocket.retryDelay(after: 1), 0.5)
        XCTAssertEqual(ChallengeSocket.retryDelay(after: 2), 1)
        XCTAssertEqual(ChallengeSocket.retryDelay(after: 3), 2)
        XCTAssertEqual(ChallengeSocket.retryDelay(after: 12), 15)

        XCTAssertEqual(LiveChallengeAPI.retryAfter("3"), 3)
        XCTAssertEqual(LiveChallengeAPI.retryAfter(" 2.5 "), 2.5)
        XCTAssertEqual(LiveChallengeAPI.retryAfter("0"), 0.25)
        XCTAssertEqual(LiveChallengeAPI.retryAfter("soon"), 1)
        XCTAssertEqual(LiveChallengeAPI.retryAfter(nil), 1)

        let live = try XCTUnwrap(LiveChallengeAPI.liveURL(base: ChallengeLink.serverURL, code: "7KQ2XM", token: "abc123"))
        XCTAssertEqual(live.absoluteString, "wss://play.chess-game-killer.workers.dev/api/games/7KQ2XM/live?token=abc123")
        let local = try XCTUnwrap(LiveChallengeAPI.liveURL(base: try XCTUnwrap(URL(string: "http://localhost:8787")), code: "7KQ2XM", token: "t"))
        XCTAssertEqual(local.absoluteString, "ws://localhost:8787/api/games/7KQ2XM/live?token=t")
    }

    // MARK: The board follows the server

    func testAFriendsMoveIsPlayedOnTheBoard() {
        let sounds = SilentSounds()
        let start = FriendGameState.sample()
        let game = OnlineGame(record: .sample(start, seat: .black), api: FakeChallengeAPI(), sounds: sounds, initial: start)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertTrue(game.match.isBoardFlipped, "Black sees the board from Black's side")
        XCTAssertEqual(game.match.game.humanColors, [.black])
        XCTAssertFalse(game.isMyTurn)

        game.apply(start.playing("e2e4"))
        XCTAssertEqual(game.match.game.moves, ["e4"])
        XCTAssertEqual(game.match.game.lastPlayed?.uci, "e2e4")
        XCTAssertEqual(game.boardMoves, ["e2e4"])
        XCTAssertEqual(sounds.played, [.move])
        XCTAssertTrue(game.isMyTurn)
        XCTAssertEqual(game.ribbon, ["e4"])

        game.apply(game.state!.playing("e7e5").playing("d1h5").playing("b8c6").playing("f1c4").playing("g8f6"))
        XCTAssertEqual(game.boardMoves.count, 6, "several moves at once are caught up in one go")
        var mate = game.state!.playing("h5f7")
        mate.status = .over
        mate.result = FriendGameState.Result(winner: .white, reason: .checkmate)
        mate.setMoves(mate.moves)
        game.apply(mate)
        XCTAssertEqual(sounds.played.last, .gameOver, "mate against the player")
        XCTAssertEqual(game.phase, .over)
        XCTAssertEqual(game.resultHeadline, "Checkmate. Alex wins")
        XCTAssertEqual(game.didWin, false)
    }

    func testAStateThatDisagreesRebuildsTheBoard() {
        let sounds = SilentSounds()
        let first = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        let game = OnlineGame(record: .sample(first, seat: .white), api: FakeChallengeAPI(), sounds: sounds, initial: first)
        XCTAssertEqual(game.boardMoves, ["e2e4", "e7e5"])
        XCTAssertEqual(placement(game.match.game.fen), placement(first.fen))
        XCTAssertTrue(sounds.played.isEmpty, "opening a game is quiet")

        let other = FriendGameState.sample(moves: ["d2d4", "d7d5", "c2c4"], now: first.now + 5_000)
        game.apply(other)
        XCTAssertEqual(game.boardMoves, ["d2d4", "d7d5", "c2c4"])
        XCTAssertEqual(placement(game.match.game.fen), placement(other.fen))
        XCTAssertEqual(game.match.game.lastPlayed?.uci, "c2c4", "the last move is still marked")
        XCTAssertTrue(game.match.game.captureEvents.isEmpty)
        XCTAssertEqual(game.ribbon, ["d4", "d5", "c4"])
        XCTAssertTrue(sounds.played.isEmpty, "a rebuilt board is quiet")
    }

    func testOlderStatesAreIgnored() {
        let newer = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        let older = FriendGameState.sample(moves: ["e2e4"])
        XCTAssertTrue(OnlineGame.isOlder(older, than: newer))
        XCTAssertFalse(OnlineGame.isOlder(newer, than: older))
        var over = newer
        over.status = .over
        XCTAssertTrue(OnlineGame.isOlder(newer, than: over))
        var later = newer
        later.now += 1
        XCTAssertTrue(OnlineGame.isOlder(newer, than: later))
        XCTAssertFalse(OnlineGame.isOlder(later, than: newer))

        let game = OnlineGame(record: .sample(newer, seat: .white), api: FakeChallengeAPI(), sounds: nil, initial: newer)
        game.apply(older)
        XCTAssertEqual(game.state?.moves, newer.moves)
        XCTAssertEqual(game.boardMoves, newer.moves)
    }

    func testYourMovesGoToTheServerWithTheirPly() async throws {
        let api = FakeChallengeAPI()
        let start = FriendGameState.sample()
        api.games[start.code] = start
        let game = OnlineGame(record: .sample(start, seat: .white), api: api, sounds: nil, initial: start)
        XCTAssertTrue(game.isMyTurn)

        game.match.tap(.e2)
        game.match.tap(.e4)
        await waitUntil("the move is sent") { api.moves.count == 1 }
        XCTAssertEqual(api.moves.first, FakeChallengeAPI.MoveRequest(code: "7KQ2XM", uci: "e2e4", ply: 0, token: "token-white"))
        await waitUntil("the server takes it") { game.state?.moves == ["e2e4"] }
        XCTAssertNil(game.pending)
        XCTAssertFalse(game.isMyTurn)
        XCTAssertEqual(game.ribbon, ["e4"])

        // The friend answers over the live connection; the next move is the third half-move.
        let answered = try XCTUnwrap(api.games[start.code]).playing("e7e5")
        api.games[start.code] = answered
        game.apply(answered)
        XCTAssertTrue(game.isMyTurn)
        game.match.tap(.g1)
        game.match.tap(.f3)
        await waitUntil("the second move is sent") { api.moves.count == 2 }
        XCTAssertEqual(api.moves.last?.uci, "g1f3")
        XCTAssertEqual(api.moves.last?.ply, 2)
        await waitUntil("the server takes it") { game.state?.moves.count == 3 }
        XCTAssertEqual(game.boardMoves, ["e2e4", "e7e5", "g1f3"])
    }

    func testAPromotionIsSentWithThePiecePicked() async {
        let api = FakeChallengeAPI()
        let line = ["e2e4", "d7d5", "e4d5", "c7c6", "d5c6", "g8f6", "c6b7", "b8d7"]
        let state = FriendGameState.sample(moves: line)
        api.games[state.code] = state
        let game = OnlineGame(record: .sample(state, seat: .white), api: api, sounds: nil, initial: state)

        game.match.tap(.b7)
        game.match.tap(.a8)
        XCTAssertNotNil(game.match.game.pendingPromotion)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(api.moves.isEmpty, "nothing goes until the piece is picked")

        game.match.promote(to: .knight)
        await waitUntil("the promotion is sent") { api.moves.count == 1 }
        XCTAssertEqual(api.moves.first?.uci, "b7a8n")
        XCTAssertEqual(api.moves.first?.ply, 8)
        await waitUntil("the server takes it") { game.state?.moves.count == 9 }
        XCTAssertEqual(game.match.game.piece(at: .a8)?.kind, .knight)
    }

    func testARefusedMoveGoesBackToTheServersBoard() async {
        let api = FakeChallengeAPI()
        let start = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        api.games[start.code] = start
        api.moveReply = { _ in
            throw ChallengeError.server(status: 422, code: "illegal_move", message: nil, game: start)
        }
        let game = OnlineGame(record: .sample(start, seat: .white), api: api, sounds: nil, initial: start)
        game.match.tap(.g1)
        game.match.tap(.f3)
        await waitUntil("the move is refused") { api.moves.count == 1 && game.pending == nil }
        XCTAssertEqual(game.boardMoves, ["e2e4", "e7e5"])
        XCTAssertEqual(placement(game.match.game.fen), placement(start.fen))
        XCTAssertEqual(game.toast?.text, "That move isn't allowed here.")
        XCTAssertTrue(game.isMyTurn, "the player can try another move")
    }

    func testTheEndLocksTheBoard() {
        let sounds = SilentSounds()
        let state = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        let game = OnlineGame(record: .sample(state, seat: .white), api: FakeChallengeAPI(), sounds: sounds, initial: state)
        let finished = Recorder<FriendGameState>()
        game.onFinish = { _, state in finished.record(state) }
        game.match.tap(.g1)
        XCTAssertEqual(game.match.game.selected, .g1)

        var over = state
        over.status = .over
        over.result = FriendGameState.Result(winner: .white, reason: .resign)
        over.now += 4_000
        over.setMoves(over.moves)
        game.apply(over)
        XCTAssertEqual(game.phase, .over)
        XCTAssertTrue(game.match.game.humanColors.isEmpty)
        XCTAssertNil(game.match.game.selected, "a picked-up piece is put down")
        game.match.tap(.g1)
        game.match.tap(.f3)
        XCTAssertEqual(game.boardMoves, ["e2e4", "e7e5"], "the board takes no more moves")
        XCTAssertEqual(finished.values.count, 1)
        XCTAssertEqual(game.resultHeadline, "Sam resigned. You win")
        XCTAssertEqual(game.didWin, true)
        XCTAssertEqual(sounds.played.last, .victory, "a game won off the board still sounds")
        XCTAssertFalse(game.isClockRunning(for: .white))
        XCTAssertFalse(game.isClockRunning(for: .black))
    }

    func testTheFriendsScreenshotsAbsencesAndAnswersAreToasted() {
        var state = FriendGameState.sample(moves: ["e2e4", "e7e5", "g1f3"])
        let game = OnlineGame(record: .sample(state, seat: .white), api: FakeChallengeAPI(), sounds: nil, initial: state)
        XCTAssertNil(game.toast)

        state.black.screenshots = 1
        state.now += 1_000
        game.apply(state)
        XCTAssertEqual(game.toast?.text, "Sam took a screenshot")

        state.black.recordings = 1
        state.now += 1_000
        game.apply(state)
        XCTAssertEqual(game.toast?.text, "Sam is recording the screen")

        state.black.away = state.now - 6_000
        state.black.online = false
        state.now += 1
        game.apply(state)
        XCTAssertEqual(game.toast?.text, "Sam left the game")
        XCTAssertEqual(game.awaySecondsLeft(for: .black), 14)
        XCTAssertFalse(game.isOnline(.black))

        state.black.away = nil
        state.black.online = true
        state.now += 1_000
        game.apply(state)
        XCTAssertEqual(game.toast?.text, "Sam is back")
        XCTAssertNil(game.awaySecondsLeft(for: .black))

        state.drawOffer = .white
        state.now += 1_000
        game.apply(state)
        XCTAssertTrue(game.drawOfferedByMe)
        state.drawOffer = nil
        state.now += 1_000
        game.apply(state)
        XCTAssertEqual(game.toast?.text, "Sam declined the draw")

        state.drawOffer = .black
        state.now += 1_000
        game.apply(state)
        XCTAssertTrue(game.drawOfferedToMe)
    }

    func testTheClocksFollowTheServerNotThePhone() {
        // The server's clock reads October 2025, whatever this phone's says: only the server's counts.
        var state = FriendGameState.sample(moves: ["e2e4", "e7e5", "g1f3"])
        state.clocks = FriendGameState.Clocks(white: 296_000, black: 287_500, running: .black, since: state.now - 2_000)
        let game = OnlineGame(record: .sample(state, seat: .white), api: FakeChallengeAPI(), sounds: nil, initial: state)
        XCTAssertEqual(game.timeLeft(for: .black) ?? 0, 285_500, accuracy: 300)
        XCTAssertEqual(game.timeLeft(for: .white), 296_000)
        XCTAssertEqual(game.timeLeft(for: .black, at: ContinuousClock.now + .seconds(10)) ?? 0, 275_500, accuracy: 300)
        XCTAssertTrue(game.isClockRunning(for: .black))
        XCTAssertFalse(game.isClockRunning(for: .white))
        XCTAssertNil(OnlineGame(record: .sample(FriendGameState.sample(clock: nil), seat: .white), api: FakeChallengeAPI(),
                                sounds: nil, initial: FriendGameState.sample(clock: nil)).timeLeft(for: .white))
    }

    func testRematchSwitchesToTheNewCodeAndSeat() async {
        let api = FakeChallengeAPI()
        var over = FriendGameState.sample(moves: ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"])
        over.status = .over
        over.result = FriendGameState.Result(winner: .white, reason: .checkmate)
        over.rematch = FriendGameState.Rematch(by: .black, code: nil)
        over.setMoves(over.moves)
        api.games[over.code] = over
        let game = OnlineGame(record: .sample(over, seat: .white), api: api, sounds: nil, initial: over)
        XCTAssertEqual(game.phase, .over)
        XCTAssertEqual(game.rematchStage, .offered)
        XCTAssertEqual(game.resultHeadline, "Checkmate. You win")

        // Both have asked: the server makes the new game with the colors swapped.
        var agreed = over
        agreed.rematch = FriendGameState.Rematch(by: .black, code: "RMATCH")
        agreed.now += 1_000
        let next = FriendGameState.sample(code: "RMATCH", creator: .black, white: "Sam", black: "Alex", now: agreed.now)
        api.actionReply = { request in
            XCTAssertEqual(request.action, .rematch)
            return agreed
        }
        api.tickets["RMATCH"] = SeatTicket(seat: .black, token: "token-white", game: next)

        await game.askForRematch()
        await waitUntil("the rematch opens") { game.code == "RMATCH" }
        XCTAssertEqual(game.seat, .black)
        XCTAssertEqual(game.record.token, "token-white", "the same token holds the new seat")
        XCTAssertEqual(game.phase, .playing)
        XCTAssertTrue(game.match.game.moves.isEmpty)
        XCTAssertTrue(game.match.isBoardFlipped)
        XCTAssertEqual(game.match.game.humanColors, [.black])
        XCTAssertEqual(game.opponentName, "Sam")
        XCTAssertEqual(game.rematchStage, OnlineGame.RematchStage.none)
        XCTAssertEqual(api.joins.last, FakeChallengeAPI.JoinRequest(code: "RMATCH", name: "Alex", token: "token-white"))
        XCTAssertEqual(game.toast?.text, "New game · you play Black")
    }

    // MARK: The list and the screens

    func testALinkOpensTheInviteAndAcceptingTakesTheSeat() async throws {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting)
        api.games[waiting.code] = waiting
        var joined = waiting
        joined.status = .active
        joined.black = FriendGameState.Player(name: "Sam", seated: true, online: true)
        joined.now += 1_000
        api.tickets[waiting.code] = SeatTicket(seat: .black, token: "token-black", game: joined)
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)

        XCTAssertFalse(center.open(try XCTUnwrap(URL(string: "https://example.com/c/7KQ2XM"))))
        XCTAssertFalse(center.isPresenting)
        XCTAssertTrue(center.open(try XCTUnwrap(URL(string: "https://play.chess-game-killer.workers.dev/c/7kq2xm"))))
        guard case .invite(let invite)? = center.screen else { return XCTFail("the invite should be up") }
        await waitUntil("the challenge loads") {
            if case .ready = invite.stage { return true }
            return false
        }
        XCTAssertEqual(invite.host, "Alex")

        await invite.accept(name: "  Sam ")
        XCTAssertEqual(api.joins, [FakeChallengeAPI.JoinRequest(code: "7KQ2XM", name: "Sam", token: nil)])
        guard case .game(let game)? = center.screen else { return XCTFail("the game should be up") }
        XCTAssertEqual(game.seat, .black)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(center.store.games.map(\.code), ["7KQ2XM"])
        XCTAssertEqual(center.store.games.first?.isCreator, false)
        XCTAssertEqual(center.playerName, "Sam")
        XCTAssertEqual(api.lives.count, 1)

        // The same link again opens the same game, not a second one.
        center.open(code: "7KQ 2XM")
        guard case .game(let same)? = center.screen else { return XCTFail("the game should still be up") }
        XCTAssertTrue(same === game)

        center.dismiss()
        XCTAssertFalse(center.isPresenting)
        XCTAssertTrue(api.lives.allSatisfy { $0.isStopped })
    }

    func testATakenCancelledOrMissingChallengeSaysSo() async {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting)
        api.games[waiting.code] = waiting
        api.joinError = ChallengeError.server(status: 409, code: "seat_taken", message: nil, game: nil)
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
        center.open(code: waiting.code)
        guard case .invite(let invite)? = center.screen else { return XCTFail("the invite should be up") }
        await waitUntil("the challenge loads") { invite.stage == .ready(waiting) }
        await invite.accept(name: "Sam")
        XCTAssertEqual(invite.stage, .unavailable(title: "This challenge was taken", detail: "Someone else accepted it first."))
        XCTAssertTrue(center.store.games.isEmpty)

        var cancelled = waiting
        cancelled.status = .over
        cancelled.result = FriendGameState.Result(winner: nil, reason: .cancelled)
        XCTAssertEqual(ChallengeInvite.stage(for: cancelled),
                       .unavailable(title: "Alex cancelled this challenge", detail: "Ask Alex for a new link."))
        cancelled.result = FriendGameState.Result(winner: nil, reason: .expired)
        XCTAssertEqual(ChallengeInvite.stage(for: cancelled),
                       .unavailable(title: "This challenge expired", detail: "Nobody took it within 7 days. Ask Alex for a new link."))

        center.open(code: "ZZZZZZ")
        guard case .invite(let missing)? = center.screen else { return XCTFail("the invite should be up") }
        await waitUntil("the server answers") { missing.stage != .loading }
        XCTAssertEqual(missing.stage, .unavailable(title: "No game with this code",
                                                   detail: "Check the code and try again. A challenge nobody takes expires after 7 days."))

        api.failure = .unreachable
        center.open(code: "YYYYYY")
        guard case .invite(let offline)? = center.screen else { return XCTFail("the invite should be up") }
        await waitUntil("the request fails") { offline.stage != .loading }
        XCTAssertEqual(offline.stage, .failed(ChallengeError.unreachable.message))
        center.dismiss()
    }

    func testCreatingAChallengeKeepsItAndGoesToTheBoardWhenTheFriendJoins() async throws {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting)
        api.created = CreatedChallenge(code: waiting.code, url: "https://play.chess-game-killer.workers.dev/c/7KQ2XM",
                                       appUrl: "chessgamekiller://c/7KQ2XM", seat: .white, token: "token-white", game: waiting)
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
        center.compose()
        guard case .composer(let composer)? = center.screen else { return XCTFail("the composer should be up") }

        await composer.create(name: " Alex ", clock: FriendClock(.rapid10), side: .white)
        XCTAssertEqual(api.creates, [FakeChallengeAPI.CreateRequest(name: "Alex", side: .white, clock: FriendClock(initial: 600, increment: 0))])
        XCTAssertEqual(composer.link?.absoluteString, "https://play.chess-game-killer.workers.dev/c/7KQ2XM")
        XCTAssertEqual(composer.created?.isCreator, true)
        XCTAssertEqual(composer.friendSeat, .black)
        XCTAssertEqual(center.store.games.first?.code, "7KQ2XM")
        XCTAssertEqual(center.store.games.first?.statusLine, "Waiting for your friend to join")
        XCTAssertEqual(center.playerName, "Alex")
        let lobby = try XCTUnwrap(composer.game)
        XCTAssertEqual(lobby.phase, .waiting)

        // The friend opens the link while the player is still on the composer: on to the board.
        var joined = waiting
        joined.status = .active
        joined.black = FriendGameState.Player(name: "Sam", seated: true, online: true)
        joined.now += 1_000
        try XCTUnwrap(api.lives.last).push(joined)
        guard case .game(let game)? = center.screen else { return XCTFail("the board should be up") }
        XCTAssertTrue(game === lobby)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.toast?.text, "Sam joined the game")
        XCTAssertEqual(center.store.games.first?.title, "vs Sam")
        XCTAssertEqual(center.store.games.first?.statusLine, "Your move")
        center.dismiss()
    }

    func testAFinishedFriendGameIsKeptOnce() {
        let api = FakeChallengeAPI()
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
        let kept = Recorder<SavedGame>()
        center.onGameFinished = { kept.record($0) }
        // Played today: a finished game more than a month old leaves the list, and sampleNow is long past.
        let state = FriendGameState.sample(moves: ["e2e4", "e7e5", "g1f3"], now: Date.now.timeIntervalSince1970 * 1000)
        let record = FriendGame.sample(state, seat: .white)
        center.store.add(record)
        let game = center.makeGame(record, initial: state)

        var over = state
        over.status = .over
        over.result = FriendGameState.Result(winner: .black, reason: .left)
        over.now += 30_000
        over.setMoves(over.moves)
        game.apply(over)
        XCTAssertEqual(kept.values.count, 1)
        let saved = kept.values.first
        XCTAssertEqual(saved?.opponent, "Sam")
        XCTAssertNil(saved?.level, "a friend has no rival level")
        XCTAssertEqual(saved?.result, .loss)
        XCTAssertEqual(saved?.moves, ["e4", "e5", "Nf3"])
        XCTAssertEqual(saved?.positions.count, 4)
        XCTAssertEqual(saved?.id, record.id)
        XCTAssertEqual(center.store.game(code: state.code)?.recorded, true)
        XCTAssertEqual(center.store.game(code: state.code)?.statusLine, "You lost · Left the game")

        var again = over
        again.now += 1_000
        game.apply(again)
        XCTAssertEqual(kept.values.count, 1, "kept once")

        // A game that never really happened isn't kept at all.
        var aborted = FriendGameState.sample(code: "ABORTD", moves: ["e2e4"])
        aborted.status = .over
        aborted.result = FriendGameState.Result(winner: nil, reason: .aborted)
        XCTAssertNil(FriendGameArchive.savedGame(aborted, seat: .white, id: UUID(), date: .now, opponent: "Sam"))
    }

    func testAbortIsSentAsAnAbortSoALateTapNeverResigns() async {
        let api = FakeChallengeAPI()
        let opening = FriendGameState.sample(moves: ["e2e4"])
        api.games[opening.code] = opening
        let game = OnlineGame(record: .sample(opening, seat: .white), api: api, sounds: nil, initial: opening)
        XCTAssertTrue(game.canAbort)
        await game.abort()
        XCTAssertEqual(api.actions.map(\.action), [.abort])
    }

    func testALinkDuringATimedGameWaitsUntilTheGameIsClosed() async {
        let api = FakeChallengeAPI()
        let playing = FriendGameState.sample(moves: ["e2e4", "e7e5"])
        api.games[playing.code] = playing
        let other = FriendGameState.sample(code: "AAAAAA", status: .waiting, white: "Jordan")
        api.games[other.code] = other
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
        let record = FriendGame.sample(playing, seat: .white)
        center.store.add(record)
        center.play(record, initial: playing)
        guard case .game(let game)? = center.screen else { return XCTFail("the game should be up") }

        center.open(code: "AAAAAA")
        guard case .game(let still)? = center.screen else { return XCTFail("the timed game should stay up") }
        XCTAssertTrue(still === game)
        XCTAssertEqual(center.heldCode, "AAAAAA")
        XCTAssertEqual(game.toast?.text, "Finish this game first. The other challenge opens after it.")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(api.actions.map(\.action).contains(.away), "the player never left the game")

        center.dismiss()
        guard case .invite(let invite)? = center.screen else { return XCTFail("the held challenge should open") }
        XCTAssertEqual(invite.code, "AAAAAA")
        XCTAssertNil(center.heldCode)
        center.dismiss()
    }

    func testClosingTheComposerWhileTheChallengeIsMadeLeavesNothingRunning() async {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting)
        api.created = CreatedChallenge(code: waiting.code, url: "https://play.chess-game-killer.workers.dev/c/7KQ2XM",
                                       appUrl: "chessgamekiller://c/7KQ2XM", seat: .white, token: "token-white", game: waiting)
        let center = ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
        center.compose()
        guard case .composer(let composer)? = center.screen else { return XCTFail("the composer should be up") }
        let making = Task { await composer.create(name: "Alex", clock: nil, side: .white) }
        center.dismiss()
        await making.value
        XCTAssertNil(composer.game)
        XCTAssertTrue(api.lives.isEmpty, "no live connection is left running")
        XCTAssertEqual(center.store.games.first?.code, "7KQ2XM", "the challenge waits in Friend games")
    }

    func testRefreshingTheListBringsItUpToDate() async {
        let api = FakeChallengeAPI()
        let going = FriendGameState.sample(code: "AAAAAA", moves: ["e2e4"])
        let forgotten = FriendGameState.sample(code: "BBBBBB", status: .waiting)
        let store = ChallengeStore(games: [.sample(going, seat: .white), .sample(forgotten, seat: .white)])
        api.games["AAAAAA"] = going.playing("e7e5")
        let center = ChallengeCenter(api: api, store: store, sounds: nil, defaults: defaults)

        await center.refreshGames(force: true)
        XCTAssertEqual(store.game(code: "AAAAAA")?.statusLine, "Your move")
        XCTAssertEqual(store.game(code: "AAAAAA")?.moveCount, 2)
        XCTAssertEqual(store.game(code: "BBBBBB")?.statusLine, "Expired", "the server no longer has it")
        XCTAssertEqual(store.sorted.map(\.code), ["AAAAAA", "BBBBBB"])

        // Only so often, unless asked.
        let fetched = api.fetches.count
        await center.refreshGames()
        XCTAssertEqual(api.fetches.count, fetched)

        // Finished games can be taken off the list; games still going can't.
        center.remove(store.game(code: "AAAAAA")!)
        XCTAssertNotNil(store.game(code: "AAAAAA"))
        center.remove(store.game(code: "BBBBBB")!)
        XCTAssertNil(store.game(code: "BBBBBB"))
    }

    func testFriendGamesSurviveARelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("friend-games.json")
        let now = Date.now.timeIntervalSince1970 * 1000

        let store = ChallengeStore(fileURL: url)
        store.add(.sample(FriendGameState.sample(code: "AAAAAA", moves: ["e2e4"], now: now), seat: .white))
        var won = FriendGameState.sample(code: "CCCCCC", moves: ["e2e4", "e7e5"], now: now)
        won.status = .over
        won.result = FriendGameState.Result(winner: .black, reason: .resign)
        store.add(.sample(won, seat: .black))
        store.markRecorded(code: "CCCCCC")

        let reopened = ChallengeStore(games: ChallengeStore.load(from: url), fileURL: url)
        XCTAssertEqual(reopened.games, store.games)
        XCTAssertEqual(reopened.game(code: "CCCCCC")?.statusLine, "You won · Resignation")
        XCTAssertEqual(reopened.game(code: "CCCCCC")?.recorded, true)
        XCTAssertEqual(reopened.game(code: "AAAAAA")?.token, "token-white")

        // A record written by another version still reads.
        let old = Data(#"[{"code": "DDDDDD", "token": "t", "seat": "black", "someday": true}]"#.utf8)
        let decoded = try JSONDecoder().decode([FriendGame].self, from: old)
        XCTAssertEqual(decoded.first?.code, "DDDDDD")
        XCTAssertEqual(decoded.first?.seat, .black)
        XCTAssertEqual(decoded.first?.recorded, false)
    }

    func testFinishedGamesLeaveTheListAfterAMonth() {
        let now = Date.now
        var old = FriendGame.sample(FriendGameState.sample(code: "AAA222"), seat: .white)
        old.status = .over
        old.updatedAt = now.addingTimeInterval(-40 * 24 * 60 * 60)
        var recent = old
        recent.code = "BBB333"
        recent.updatedAt = now.addingTimeInterval(-2 * 24 * 60 * 60)
        var going = old
        going.code = "CCC444"
        going.status = .active
        let kept = ChallengeStore.pruned([old, recent, going], now: now)
        XCTAssertEqual(kept.map(\.code), ["BBB333", "CCC444"])
    }
}
