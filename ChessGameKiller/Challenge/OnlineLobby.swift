import Foundation
import Observation

// Play online: rated games with players waiting right now, not only friends with a link.
// The server keeps a lobby (play/PROTOCOL.md, "Play online"): a player waits there with a clock,
// and anyone can take them on by name, or find a game and be paired with the closest rating.
// A paired game is an ordinary friend game on the server, rated, so OnlineGame plays it.

/// One player waiting in the lobby.
struct LobbyPlayer: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var rating: Int
    var provisional = false
    var clock: FriendClock
    /// How long they have waited, in milliseconds.
    var waitingFor: Double = 0

    /// "1250", or "1200?" while their rating is still settling.
    var ratingLabel: String { "\(rating)\(provisional ? "?" : "")" }

    enum CodingKeys: String, CodingKey {
        case id, name, rating, provisional, clock, waitingFor
    }

    init(id: String, name: String, rating: Int, provisional: Bool = false, clock: FriendClock, waitingFor: Double = 0) {
        self.id = id
        self.name = name
        self.rating = rating
        self.provisional = provisional
        self.clock = clock
        self.waitingFor = waitingFor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let raw = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let clean = ChallengeName.clean(raw)
        name = clean.isEmpty ? "Player" : clean
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 1200
        provisional = try c.decodeIfPresent(Bool.self, forKey: .provisional) ?? false
        clock = try c.decode(FriendClock.self, forKey: .clock)
        waitingFor = try c.decodeIfPresent(Double.self, forKey: .waitingFor) ?? 0
    }
}

struct LobbyList: Decodable, Equatable, Sendable {
    var players: [LobbyPlayer] = []
    var waiting = 0

    enum CodingKeys: String, CodingKey {
        case players, waiting
    }

    init(players: [LobbyPlayer] = [], waiting: Int? = nil) {
        self.players = players
        self.waiting = waiting ?? players.count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One entry the app can't read never hides the others.
        let entries = try c.decodeIfPresent([Lossy<LobbyPlayer>].self, forKey: .players) ?? []
        players = entries.compactMap(\.value)
        waiting = try c.decodeIfPresent(Int.self, forKey: .waiting) ?? players.count
    }
}

/// The player's online rating.
struct OnlineRating: Codable, Equatable, Sendable {
    var rating: Int
    var games: Int
    var provisional: Bool

    var label: String { "\(rating)\(provisional ? "?" : "")" }
}

/// A game the lobby started: the seat and token that prove it is ours.
struct LobbyMatch: Decodable, Equatable, Sendable {
    var code: String
    var seat: FriendSeat
    var token: String
    /// Sent to the player who took the other on; the one who waited fetches it.
    var game: FriendGameState?
}

/// Every lobby reply: still waiting (`seek`, `token` the first time), a game (`match`), or cancelled.
struct LobbyReply: Decodable, Equatable, Sendable {
    var seek: LobbyPlayer?
    var token: String?
    var you: OnlineRating?
    var match: LobbyMatch?
    var cancelled: Bool?
    /// How many wait in the lobby, the player included.
    var waiting: Int?
}

/// The app's private id for its player online. Ratings are kept by it on the server, which only
/// ever stores its hash. Made once, kept on this phone, never shown.
enum OnlinePlayerKey {
    static let key = "online.playerKey"

    static func current(_ defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key), saved.count == 32, saved.allSatisfy(\.isHexDigit) {
            return saved
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        let made = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(made, forKey: key)
        return made
    }
}

/// The Play online screen's work: who is waiting, taking one of them on, and finding a game.
@MainActor
@Observable
final class OnlineLobby {
    enum Phase: Equatable {
        /// Looking at who is waiting.
        case browsing
        /// Waiting in the lobby at a clock, since a moment.
        case searching(FriendClock, since: Date)
        /// A game was found: opening it.
        case starting
    }

    /// The clocks Play online offers. Online games always have a clock, so leaving can be claimed.
    static let clocks: [TimeControl] = [.blitz3Plus2, .blitz5, .rapid10, .rapid15Plus10]

    private(set) var players: [LobbyPlayer] = []
    private(set) var waiting = 0
    private(set) var you: OnlineRating?
    private(set) var phase: Phase = .browsing
    private(set) var problem: String?
    /// Loaded the list at least once.
    private(set) var hasLoaded = false
    /// The player being taken on, while that is under way.
    private(set) var challenging: String?

    @ObservationIgnored private weak var center: ChallengeCenter?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var seekID: String?
    @ObservationIgnored private var seekToken: String?
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// How often the list and a waiting seek are checked.
    static let interval: Duration = .seconds(2)

    init(center: ChallengeCenter, defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    private var player: String { OnlinePlayerKey.current(defaults) }

    var isSearching: Bool {
        if case .searching = phase { return true }
        return false
    }

    /// Players waiting at `clock` first, then the rest; never the player's own seek.
    func sorted(for clock: FriendClock?) -> [LobbyPlayer] {
        let others = players.filter { $0.id != seekID }
        guard let clock else { return others }
        return others.filter { $0.clock == clock } + others.filter { $0.clock != clock }
    }

    // MARK: Running

    /// Keeps the list fresh (and a waiting seek checked in) while the screen is up.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            if let self, self.you == nil {
                self.you = try? await self.center?.api.rating(player: self.player)
            }
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// The screen closed: stop checking, and leave the lobby.
    func stop() {
        loop?.cancel()
        loop = nil
        guard let id = seekID, let token = seekToken, let api = center?.api else { return }
        seekID = nil
        seekToken = nil
        if isSearching { phase = .browsing }
        Task { _ = try? await api.cancelSeek(id, token: token) }
    }

    func tick() async {
        guard let api = center?.api else { return }
        if let id = seekID, let token = seekToken {
            do {
                let reply = try await api.checkSeek(id, token: token)
                if let match = reply.match {
                    await open(match)
                    return
                }
            } catch let error as ChallengeError where error.isNotFound {
                // The lobby lost the seek (the server restarted, say): wait again.
                if case .searching(let clock, _) = phase {
                    seekID = nil
                    seekToken = nil
                    await find(clock: clock, name: center?.playerName ?? "")
                }
            } catch {}
        }
        do {
            let list = try await api.lobby()
            players = list.players
            waiting = list.waiting
            hasLoaded = true
            if problem == ChallengeError.unreachable.message { problem = nil }
        } catch let error as ChallengeError {
            if !hasLoaded { problem = error.message }
        } catch {}
    }

    // MARK: Playing

    /// Waits for a game at `clock`, taking on the closest-rated player already waiting at it.
    func find(clock: FriendClock, name: String) async {
        guard let center, phase == .browsing || isSearching, seekID == nil else { return }
        center.rememberName(name)
        problem = nil
        phase = .searching(clock, since: .now)
        do {
            let reply = try await center.api.seek(name: ChallengeName.clean(name), clock: clock, player: player)
            if let you = reply.you { self.you = you }
            if let match = reply.match {
                await open(match)
            } else if let seek = reply.seek, let token = reply.token {
                // Closed while the seek was being made: leave at once.
                guard isSearching else {
                    _ = try? await center.api.cancelSeek(seek.id, token: token)
                    return
                }
                seekID = seek.id
                seekToken = token
                if let waiting = reply.waiting { self.waiting = waiting }
            } else {
                phase = .browsing
                problem = ChallengeError.badReply.message
            }
        } catch is CancellationError {
            phase = .browsing
        } catch let error as ChallengeError {
            phase = .browsing
            problem = error.message
        } catch {
            phase = .browsing
            problem = ChallengeError.unreachable.message
        }
    }

    /// Stops waiting. If someone took the player on just then, their game opens instead.
    func cancel() async {
        guard let center, let id = seekID, let token = seekToken else {
            phase = .browsing
            return
        }
        seekID = nil
        seekToken = nil
        phase = .browsing
        if let reply = try? await center.api.cancelSeek(id, token: token), let match = reply.match {
            await open(match)
        }
    }

    /// Takes on one waiting player: challenging the online player.
    func challenge(_ opponent: LobbyPlayer, name: String) async {
        guard let center, challenging == nil, phase != .starting else { return }
        center.rememberName(name)
        challenging = opponent.id
        problem = nil
        defer { challenging = nil }
        // Waiting meanwhile? Leave the lobby first, so nobody else pairs with this player too.
        if seekID != nil { await cancel() }
        guard phase == .browsing else { return }
        do {
            let reply = try await center.api.play(opponent.id, name: ChallengeName.clean(name), player: player)
            if let you = reply.you { self.you = you }
            if let match = reply.match { await open(match) }
        } catch let error as ChallengeError {
            if error.isNotFound {
                players.removeAll { $0.id == opponent.id }
                problem = "\(opponent.name) isn't waiting any more. Pick someone else, or find a game."
            } else {
                problem = error.message
            }
        } catch {
            problem = ChallengeError.unreachable.message
        }
    }

    /// Opens the game the lobby started.
    private func open(_ match: LobbyMatch) async {
        guard let center else { return }
        phase = .starting
        seekID = nil
        seekToken = nil
        var state = match.game
        if state == nil {
            for _ in 0..<3 where state == nil {
                state = try? await center.api.game(match.code)
            }
        }
        guard let state else {
            // Kept anyway, so the seat isn't lost: the friend games list opens it once the server answers.
            center.store.add(FriendGame(code: match.code, token: match.token, seat: match.seat, isCreator: false, status: .active))
            phase = .browsing
            problem = "Your game started, but couldn't be opened yet. It's in your games with friends."
            return
        }
        let record = FriendGame(code: match.code, token: match.token, seat: match.seat, state: state)
        center.store.add(record)
        center.play(record, initial: state)
    }
}
