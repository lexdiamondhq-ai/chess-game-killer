import ChessKit
import XCTest
@testable import ChessGameKiller

/// Play online without a network: the lobby's words, finding a game, taking on a waiting
/// player, leaving the lobby, and ratings in a game. Every reply comes from `FakeChallengeAPI`.
@MainActor
final class OnlineLobbyTests: XCTestCase {

    private var defaults: UserDefaults!
    private static let suite = "OnlineLobbyTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: Self.suite)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suite)
    }

    private func center(_ api: FakeChallengeAPI) -> ChallengeCenter {
        ChallengeCenter(api: api, store: ChallengeStore(), sounds: nil, defaults: defaults)
    }

    private func lobby(of center: ChallengeCenter) throws -> OnlineLobby {
        var shown: OnlineLobby?
        if case .online(let lobby)? = center.screen { shown = lobby }
        return try XCTUnwrap(shown, "Play online should be up")
    }

    private func shownGame(_ center: ChallengeCenter) -> OnlineGame? {
        if case .game(let game)? = center.screen { return game }
        return nil
    }

    private static let blitz = FriendClock(initial: 300, increment: 0)

    private func rated(code: String = "ONL1NE", white: String = "Alex", black: String = "Sam") -> FriendGameState {
        var state = FriendGameState.sample(code: code, clock: Self.blitz, white: white, black: black)
        state.rated = true
        state.ratings = .init(white: .init(rating: 1200, provisional: true), black: .init(rating: 1450))
        return state
    }

    // MARK: The server's words

    func testReadsTheLobbyAndRatings() throws {
        let list = try JSONDecoder().decode(LobbyList.self, from: Data("""
        {"players":[{"id":"a1b2c3d4e5f6","name":"  Sam  ","rating":1450,"provisional":false,
        "clock":{"initial":300,"increment":0},"look":"gilded","waitingFor":42000},{"id":"broken"}],"waiting":2,"now":1}
        """.utf8))
        XCTAssertEqual(list.players, [LobbyPlayer(id: "a1b2c3d4e5f6", name: "Sam", rating: 1450, clock: Self.blitz, waitingFor: 42000)])
        XCTAssertEqual(list.waiting, 2)

        let game = try JSONDecoder().decode(FriendGameState.self, from: Data("""
        {"code":"onl1ne","status":"over","rated":true,"ratings":{"white":{"rating":1200,"provisional":true,"after":1180,"change":-20},
        "black":{"rating":1450,"provisional":false,"after":1462,"change":12}}}
        """.utf8))
        XCTAssertTrue(game.rated)
        XCTAssertEqual(game.ratings?[.white].label, "1200?")
        XCTAssertEqual(game.ratings?[.black].change, 12)

        // A friend game from an older server: unrated, no ratings.
        let friend = try JSONDecoder().decode(FriendGameState.self, from: Data(#"{"code":"7KQ2XM","status":"active"}"#.utf8))
        XCTAssertFalse(friend.rated)
        XCTAssertNil(friend.ratings)
    }

    func testThePlayerKeyIsMadeOnceAndKept() {
        let key = OnlinePlayerKey.current(defaults)
        XCTAssertEqual(key.count, 32)
        XCTAssertTrue(key.allSatisfy(\.isHexDigit))
        XCTAssertEqual(OnlinePlayerKey.current(defaults), key)
    }

    // MARK: Finding a game

    func testFindingAGameWhenSomeoneIsWaitingOpensItAtOnce() async throws {
        let api = FakeChallengeAPI()
        let state = rated()
        api.seekReply = LobbyReply(match: LobbyMatch(code: state.code, seat: .white, token: "token-white", game: state))
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.find(clock: Self.blitz, name: " Alex ")
        XCTAssertEqual(api.seeks.first?.name, "Alex")
        XCTAssertEqual(api.seeks.first?.clock, Self.blitz)
        XCTAssertEqual(api.seeks.first?.player, OnlinePlayerKey.current(defaults))
        let game = try XCTUnwrap(shownGame(center))
        XCTAssertEqual(game.code, "ONL1NE")
        XCTAssertTrue(game.isRated)
        XCTAssertEqual(center.store.game(code: "ONL1NE")?.seat, .white)
        center.dismiss()
    }

    func testWaitingUntilSomeoneTakesYouOn() async throws {
        let api = FakeChallengeAPI()
        let state = rated()
        api.games[state.code] = state
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.find(clock: Self.blitz, name: "Alex")
        XCTAssertTrue(lobby.isSearching)

        await lobby.tick()
        XCTAssertTrue(lobby.isSearching, "still waiting after a quiet check-in")
        // Someone took the player on: the check-in hands over the seat, and the game is fetched.
        api.checkReplies = [LobbyReply(match: LobbyMatch(code: state.code, seat: .black, token: "token-black"))]
        await lobby.tick()
        XCTAssertEqual(shownGame(center)?.seat, .black)
        XCTAssertTrue(api.fetches.contains(state.code))
        center.dismiss()
    }

    func testClosingWhileWaitingLeavesTheLobby() async throws {
        let api = FakeChallengeAPI()
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.find(clock: Self.blitz, name: "Alex")
        center.dismiss()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while api.cancels.isEmpty, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(api.cancels, ["a1b2c3d4e5f6"])
        XCTAssertFalse(lobby.isSearching)
    }

    func testCancellingJustAsSomeoneTookYouOnOpensTheGame() async throws {
        let api = FakeChallengeAPI()
        let state = rated()
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.find(clock: Self.blitz, name: "Alex")
        // The cancel answers with the game the player was just paired into.
        api.cancelReply = LobbyReply(match: LobbyMatch(code: state.code, seat: .white, token: "token-white", game: state))
        await lobby.cancel()
        XCTAssertEqual(shownGame(center)?.code, state.code)
        center.dismiss()
    }

    // MARK: Taking a player on

    func testTakingOnAWaitingPlayer() async throws {
        let api = FakeChallengeAPI()
        let sam = LobbyPlayer(id: "0a1b2c3d4e5f", name: "Sam", rating: 1450, clock: Self.blitz)
        api.lobbyList = LobbyList(players: [sam])
        let state = rated()
        api.playReplies[sam.id] = LobbyReply(you: api.onlineRating,
                                             match: LobbyMatch(code: state.code, seat: .white, token: "token-white", game: state))
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.tick()
        XCTAssertEqual(lobby.players, [sam])
        await lobby.challenge(sam, name: "Alex")
        XCTAssertEqual(api.plays.first?.id, sam.id)
        let game = try XCTUnwrap(shownGame(center))
        XCTAssertEqual(game.opponentName, "Sam")
        center.dismiss()
    }

    func testAPlayerWhoLeftIsTakenOffTheList() async throws {
        let api = FakeChallengeAPI()
        let gone = LobbyPlayer(id: "0a1b2c3d4e5f", name: "Kim", rating: 1300, clock: Self.blitz)
        api.lobbyList = LobbyList(players: [gone])
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.tick()
        await lobby.challenge(gone, name: "Alex")
        XCTAssertTrue(lobby.players.isEmpty)
        XCTAssertEqual(lobby.problem, "Kim isn't waiting any more. Pick someone else, or find a game.")
        XCTAssertNil(shownGame(center))
        center.dismiss()
    }

    func testPlayersAtYourClockComeFirst() async throws {
        let api = FakeChallengeAPI()
        let rapid = LobbyPlayer(id: "111111111111", name: "Lee", rating: 1500, clock: FriendClock(initial: 600, increment: 0))
        let blitz = LobbyPlayer(id: "222222222222", name: "Max", rating: 1100, clock: Self.blitz)
        api.lobbyList = LobbyList(players: [rapid, blitz])
        let center = center(api)
        center.playOnline()
        let lobby = try lobby(of: center)
        await lobby.tick()
        XCTAssertEqual(lobby.sorted(for: Self.blitz).map(\.name), ["Max", "Lee"])
        center.dismiss()
    }

    // MARK: In the game

    func testTheEndOfARatedGameShowsTheNewRating() {
        var state = rated()
        state.status = .over
        state.result = FriendGameState.Result(winner: .black, reason: .resign)
        state.ratings?.white.after = 1180
        state.ratings?.white.change = -20
        let game = OnlineGame(record: FriendGame.sample(state, seat: .white), api: FakeChallengeAPI(), sounds: nil, initial: state)
        XCTAssertTrue(game.resultDetail.hasPrefix("Rating 1180 (−20) · Blitz · 5+0"), game.resultDetail)
    }

    func testTheHomeCountComesFromTheLobby() async {
        let api = FakeChallengeAPI()
        api.lobbyList = LobbyList(players: [LobbyPlayer(id: "333333333333", name: "Ana", rating: 1200, clock: Self.blitz)])
        let center = center(api)
        XCTAssertNil(center.onlineWaiting)
        await center.refreshOnlineCount()
        XCTAssertEqual(center.onlineWaiting, 1)
    }
}
