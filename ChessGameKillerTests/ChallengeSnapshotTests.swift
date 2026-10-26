import ChessKit
import SceneKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Pictures of Challenge a friend at iPhone size: the composer before and after the challenge
/// exists, the lobby, an invite, a game under way, a draw offer, the end card with a rematch,
/// the friend games list and the way in from New Game. Saved to SNAPSHOT_DIR as challenge-*.png
/// (CI prints them in its log). Every server reply comes from FakeChallengeAPI.
@MainActor
final class ChallengeSnapshotTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var saved: [String: Any?] = [:]
    private static let keys = ["boardTheme", "sculpted3D", ChallengeName.key, "challenge.clock", "challenge.side", "online.clock"]

    /// The phone's own time, for games that must look recent. Clocks and absences count from the server's `now`.
    private var realNow: Double { Date.now.timeIntervalSince1970 * 1000 }

    /// A real middlegame: a closed Ruy Lopez after 16 moves each, White to move.
    private static let ruyLopez = [
        "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7", "f1e1", "b7b5",
        "a4b3", "d7d6", "c2c3", "e8g8", "h2h3", "c6a5", "b3c2", "c7c5", "d2d4", "d8c7", "b1d2", "c5d4",
        "c3d4", "a5c6", "d2b3", "a6a5", "c1e3", "a5a4", "b3d2", "c8d7",
    ]

    override func setUp() async throws {
        for key in Self.keys {
            saved[key] = defaults.object(forKey: key)
        }
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(true, forKey: "sculpted3D")
        defaults.set("Alex", forKey: ChallengeName.key)
        defaults.set(TimeControl.rapid10.rawValue, forKey: "challenge.clock")
        defaults.set(SideChoice.white.rawValue, forKey: "challenge.side")
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    // MARK: Making a challenge

    func testComposer() throws {
        let api = FakeChallengeAPI()
        let center = makeCenter(api, games: listGames(on: api))
        center.compose()
        try snapshot("challenge-composer", center: center)
        center.dismiss()
    }

    func testComposerOnceTheChallengeExists() throws {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting, now: realNow)
        api.created = CreatedChallenge(code: waiting.code, url: ChallengeLink.inviteURL(for: waiting.code).absoluteString,
                                       appUrl: ChallengeLink.appURL(for: waiting.code).absoluteString,
                                       seat: .white, token: "token-white", game: waiting)
        let center = makeCenter(api)
        center.compose()
        guard case .composer(let composer)? = center.screen else { return XCTFail("the composer should be up") }
        Task { await composer.create(name: "Alex", clock: FriendClock(.rapid10), side: .white) }
        spin(until: "the challenge exists") { composer.created != nil }
        try snapshot("challenge-composer-created", center: center)
        center.dismiss()
    }

    // MARK: Play online

    func testOnlineLobby() throws {
        let api = FakeChallengeAPI()
        api.onlineRating = OnlineRating(rating: 1236, games: 4, provisional: true)
        api.lobbyList = LobbyList(players: [
            LobbyPlayer(id: "111111111111", name: "Sam Okafor", rating: 1310, clock: FriendClock(initial: 300, increment: 0), waitingFor: 42_000),
            LobbyPlayer(id: "222222222222", name: "Priya", rating: 1188, provisional: true, clock: FriendClock(initial: 300, increment: 0), waitingFor: 3_000),
            LobbyPlayer(id: "333333333333", name: "Jordan", rating: 1544, clock: FriendClock(initial: 600, increment: 0), waitingFor: 130_000),
            LobbyPlayer(id: "444444444444", name: "Mia", rating: 1402, clock: FriendClock(initial: 180, increment: 2), waitingFor: 18_000),
        ])
        defaults.set(TimeControl.blitz5.rawValue, forKey: "online.clock")
        let center = makeCenter(api)
        center.playOnline()
        try snapshot("online-lobby", center: center, wait: 2.5)
        center.dismiss()
    }

    func testOnlineFindingAGame() throws {
        let api = FakeChallengeAPI()
        defaults.set(TimeControl.blitz5.rawValue, forKey: "online.clock")
        let center = makeCenter(api)
        center.playOnline()
        guard case .online(let lobby)? = center.screen else { return XCTFail("Play online should be up") }
        Task { await lobby.find(clock: FriendClock(initial: 300, increment: 0), name: "Alex") }
        spin(until: "waiting in the lobby") { lobby.isSearching }
        try snapshot("online-finding", center: center, wait: 2.5)
        center.dismiss()
    }

    func testOnlineRatedGame() throws {
        let api = FakeChallengeAPI()
        var state = FriendGameState.sample(code: "ONL1NE", moves: Array(Self.ruyLopez.prefix(12)),
                                           clock: FriendClock(initial: 300, increment: 0), black: "Sam Okafor", now: realNow)
        state.rated = true
        state.ratings = .init(white: .init(rating: 1236, provisional: true), black: .init(rating: 1310))
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("online-rated-game", center: center, wait: 3)
        center.dismiss()
    }

    func testOnlineRatedGameOver() throws {
        let api = FakeChallengeAPI()
        var state = FriendGameState.sample(code: "ONL1NE", moves: Array(Self.ruyLopez.prefix(20)),
                                           clock: FriendClock(initial: 300, increment: 0), black: "Sam Okafor", now: realNow)
        state.status = .over
        state.result = FriendGameState.Result(winner: .white, reason: .resign)
        state.rated = true
        state.ratings = .init(white: .init(rating: 1236, provisional: true, after: 1262, change: 26),
                              black: .init(rating: 1310, after: 1297, change: -13))
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("online-rated-over", center: center, wait: 3)
        center.dismiss()
    }

    func testLobby() throws {
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting, now: realNow)
        api.games[waiting.code] = waiting
        let record = FriendGame.sample(waiting, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: waiting)
        try snapshot("challenge-lobby", center: center, wait: 3)
        center.dismiss()
    }

    // MARK: Taking one

    func testJoin() throws {
        // A friend who has never given a name is asked for one.
        defaults.removeObject(forKey: ChallengeName.key)
        let api = FakeChallengeAPI()
        let waiting = FriendGameState.sample(status: .waiting, clock: FriendClock(initial: 300, increment: 0), now: realNow)
        api.games[waiting.code] = waiting
        let center = makeCenter(api)
        center.open(code: waiting.code)
        guard case .invite(let invite)? = center.screen else { return XCTFail("the invite should be up") }
        spin(until: "the challenge loads") { invite.stage == .ready(waiting) }
        try snapshot("challenge-join", center: center)
        center.dismiss()
    }

    // MARK: Playing

    /// A real middlegame in 3D, both clocks running in turn, the friend away with the seconds counting down.
    func testGameInProgress() throws {
        let api = FakeChallengeAPI()
        let now = realNow
        var state = FriendGameState.sample(moves: Self.ruyLopez, now: now)
        state.clocks = FriendGameState.Clocks(white: 312_400, black: 287_900, running: .white, since: now - 4_000)
        // Away for about six and a half seconds when the picture is taken: "Away · 54s".
        state.black.away = now - 3_300
        state.black.online = false
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("challenge-game", center: center, wait: 3)
        center.dismiss()
    }

    /// The friend left over a minute ago: the claim offer over the dock, Wait or Claim win.
    func testClaimTheWin() throws {
        defaults.set(false, forKey: "sculpted3D")
        let api = FakeChallengeAPI()
        let now = realNow
        var state = FriendGameState.sample(moves: Self.ruyLopez, now: now)
        state.clocks = FriendGameState.Clocks(white: 241_000, black: 198_500, running: .white, since: now - 1_500)
        state.black.away = now - 75_000
        state.black.claimableAt = now - 15_000
        state.black.online = false
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("challenge-claim-win", center: center)
        center.dismiss()
    }

    /// A game just begun: the fair-play rules across the top of the first screen.
    func testFairPlayOnTheFirstScreen() throws {
        defaults.set(false, forKey: "sculpted3D")
        let api = FakeChallengeAPI()
        let state = FriendGameState.sample(now: realNow)
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("challenge-fair-play", center: center)
        center.dismiss()
    }

    func testDrawOffer() throws {
        defaults.set(false, forKey: "sculpted3D")
        let api = FakeChallengeAPI()
        let now = realNow
        var state = FriendGameState.sample(moves: Self.ruyLopez, now: now)
        state.clocks = FriendGameState.Clocks(white: 241_000, black: 198_500, running: .white, since: now - 1_500)
        state.drawOffer = .black
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("challenge-draw-offer", center: center)
        center.dismiss()
    }

    func testEndCardWithARematch() throws {
        defaults.set(false, forKey: "sculpted3D")
        let api = FakeChallengeAPI()
        let now = realNow
        var state = FriendGameState.sample(moves: Self.ruyLopez, now: now)
        state.status = .over
        state.result = FriendGameState.Result(winner: .white, reason: .resign)
        state.rematch = FriendGameState.Rematch(by: .black, code: nil)
        state.setMoves(Self.ruyLopez)
        state.clocks?.white = 231_000
        state.clocks?.black = 176_000
        api.games[state.code] = state
        let record = FriendGame.sample(state, seat: .white)
        let center = makeCenter(api, games: [record])
        center.play(record, initial: state)
        try snapshot("challenge-end-rematch", center: center)
        center.dismiss()
    }

    // MARK: The list, and the way in

    func testFriendGamesList() throws {
        let api = FakeChallengeAPI()
        let center = makeCenter(api, games: listGames(on: api))
        let theme = BoardTheme.named(.gilded)
        let view = ZStack {
            ThemeBackdrop(theme: theme)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    FriendGamesList(theme: theme)
                    VStack(alignment: .leading, spacing: 10) {
                        ChallengeSectionTitle(title: "Home screen card")
                        FriendGamesCard(limit: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .environment(center)
        .tint(theme.challengeAccent)
        .preferredColorScheme(.dark)
        try snapshot("challenge-friend-games", view: view, wait: 1.5)
    }

    func testTheWayInFromNewGame() throws {
        let theme = BoardTheme.named(.gilded)
        let view = Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                NewGameSheet(theme: theme, start: { _ in }, challenge: {})
            }
        try snapshot("challenge-entry", view: view, wait: 2)
    }

    // MARK: Helpers

    private func makeCenter(_ api: FakeChallengeAPI, games: [FriendGame] = []) -> ChallengeCenter {
        ChallengeCenter(api: api, store: ChallengeStore(games: games), sounds: nil)
    }

    /// One of each kind of row: your move, their move, an open challenge, a win and a draw.
    /// The server has them too, so bringing the list up to date leaves it as it is.
    private func listGames(on api: FakeChallengeAPI) -> [FriendGame] {
        let now = realNow
        let yourMove = FriendGameState.sample(code: "7KQ2XM", moves: ["e2e4", "c7c5"], now: now - 60_000)
        let theirMove = FriendGameState.sample(code: "P4HRWN", moves: ["d2d4", "g8f6", "c2c4"],
                                               clock: FriendClock(initial: 300, increment: 0), black: "Jordan", now: now - 600_000)
        let unanswered = FriendGameState.sample(code: "M8TQ3D", status: .waiting, clock: FriendClock(initial: 180, increment: 2),
                                                now: now - 3_600_000)
        var won = FriendGameState.sample(code: "XR29BF", moves: ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"],
                                         black: "Priya", now: now - 86_400_000)
        won.status = .over
        won.result = FriendGameState.Result(winner: .white, reason: .checkmate)
        var drawn = FriendGameState.sample(code: "H6KC4T", moves: ["e2e4", "e7e5"], clock: nil, black: "Mia",
                                           now: now - 2 * 86_400_000)
        drawn.status = .over
        drawn.result = FriendGameState.Result(winner: nil, reason: .repetition)
        let states = [yourMove, theirMove, unanswered, won, drawn]
        for state in states {
            api.games[state.code] = state
        }
        return states.map { FriendGame.sample($0, seat: .white) }
    }

    /// Lets the run loop turn until `condition` holds, so the work queued on the main actor runs.
    private func spin(until what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting until \(what)")
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func snapshot(_ name: String, center: ChallengeCenter, wait: TimeInterval = 1.5) throws {
        try snapshot(name, view: ChallengeScreens().environment(center), wait: wait)
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
            // Metal content is drawn by SceneKit itself, so 3D boards are pictured separately.
            for view in Self.sceneViews(in: window) {
                view.snapshot().draw(in: view.convert(view.bounds, to: window))
            }
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.rootViewController?.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
    }

    private static func sceneViews(in view: UIView) -> [SCNView] {
        ((view as? SCNView).map { [$0] } ?? []) + view.subviews.flatMap { sceneViews(in: $0) }
    }
}
