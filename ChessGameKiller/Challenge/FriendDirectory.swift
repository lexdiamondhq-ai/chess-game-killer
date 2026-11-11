import Foundation
import Observation

// Friends by @username (play/PROTOCOL.md, "Friends by username"): a player picks a username once,
// then finds friends by username or name and sends them a challenge in the app. The server knows a
// player only by the hash of the app's player key, the same one Play online uses.

/// Another player, as the server shows them.
struct FriendPerson: Codable, Hashable, Identifiable, Sendable {
    var username: String
    var name: String
    var online: Bool

    var id: String { username }
    /// "@maria".
    var handle: String { "@\(username)" }
    /// The letter on their round face.
    var initial: String { String((name.first { $0.isLetter } ?? username.first ?? "?")).uppercased() }
}

/// The player's own username and the name friends see.
struct FriendYou: Codable, Equatable, Sendable {
    var username: String
    var name: String
}

/// A challenge another player sent by username, waiting to be opened.
struct FriendInviteNote: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var code: String
    var clock: FriendClock?
    /// The seat this player takes.
    var seat: FriendSeat
    var from: FriendPerson

    /// "10+0 · you play Black", "No clock · you play White".
    var detail: String {
        "\(clock?.label ?? "No clock") · you play \(seat.name)"
    }
}

/// The friends server, as the app uses it. Tests leave it out: nothing is asked then.
@MainActor
protocol FriendDirectoryAPI: AnyObject {
    func me(player: String, name: String?) async throws -> FriendYou?
    func claim(player: String, username: String, name: String) async throws -> FriendYou
    func search(player: String, query: String) async throws -> [FriendPerson]
    func people(player: String) async throws -> [FriendPerson]
    func invite(player: String, to username: String, code: String) async throws -> FriendPerson
    func inbox(player: String) async throws -> [FriendInviteNote]
    func dismiss(player: String, id: String) async throws
}

/// The friends server over HTTPS, on the same game server as everything else.
@MainActor
final class LiveFriendDirectoryAPI: FriendDirectoryAPI {
    private let base: URL
    private let session: URLSession

    init(base: URL = ChallengeLink.serverURL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    private struct YouReply: Decodable { var you: FriendYou? }
    private struct PlayersReply: Decodable { var players: [FriendPerson] }
    private struct PeopleReply: Decodable { var people: [FriendPerson] }
    private struct SentReply: Decodable { var sent: FriendPerson }
    private struct InboxReply: Decodable { var invites: [FriendInviteNote] }
    private struct Ignored: Decodable {}

    func me(player: String, name: String?) async throws -> FriendYou? {
        var body = ["player": player]
        if let name { body["name"] = name }
        let reply: YouReply = try await post("me", body)
        return reply.you
    }

    func claim(player: String, username: String, name: String) async throws -> FriendYou {
        let reply: YouReply = try await post("claim", ["player": player, "username": username, "name": name])
        guard let you = reply.you else { throw ChallengeError.badReply }
        return you
    }

    func search(player: String, query: String) async throws -> [FriendPerson] {
        let reply: PlayersReply = try await post("search", ["player": player, "q": query])
        return reply.players
    }

    func people(player: String) async throws -> [FriendPerson] {
        let reply: PeopleReply = try await post("people", ["player": player])
        return reply.people
    }

    func invite(player: String, to username: String, code: String) async throws -> FriendPerson {
        let reply: SentReply = try await post("invite", ["player": player, "to": username, "code": code])
        return reply.sent
    }

    func inbox(player: String) async throws -> [FriendInviteNote] {
        let reply: InboxReply = try await post("inbox", ["player": player])
        return reply.invites
    }

    func dismiss(player: String, id: String) async throws {
        let _: Ignored = try await post("dismiss", ["player": player, "id": id])
    }

    private func post<Reply: Decodable>(_ part: String, _ body: [String: String]) async throws -> Reply {
        var request = URLRequest(url: base.appending(path: "api/friends/\(part)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ChallengeError.unreachable
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw ChallengeError.badReply }
        guard (200..<300).contains(http.statusCode) else {
            let reply = try? JSONDecoder().decode(ChallengeErrorReply.self, from: data)
            throw ChallengeError.server(status: http.statusCode, code: reply?.error ?? "http_\(http.statusCode)",
                                        message: reply?.message, game: nil)
        }
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw ChallengeError.badReply
        }
    }
}

/// Friends by username for the whole app: the player's own username, the people they play,
/// finding someone, and challenges waiting for them. ChallengeCenter owns one.
@MainActor
@Observable
final class FriendDirectory {
    /// The player's username, once picked (remembered on this phone, checked with the server).
    private(set) var you: FriendYou?
    /// The player's people: whoever they added by hand, then whoever they have challenged or
    /// been challenged by, the latest first.
    private(set) var people: [FriendPerson] = []
    /// Players matching what's typed in the find box.
    private(set) var results: [FriendPerson] = []
    private(set) var isSearching = false
    /// Challenges sent to this player by username, newest first.
    private(set) var inbox: [FriendInviteNote] = []

    @ObservationIgnored private let api: FriendDirectoryAPI?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastInboxCheck: Date?
    /// People added by hand, kept on this phone: the server lists only those a game went to or came from.
    @ObservationIgnored private var added: [FriendPerson] = []

    static let youKey = "friends.you"
    static let peopleKey = "friends.people"
    static let addedKey = "friends.added"
    /// The most people kept by hand.
    static let addedLimit = 40

    /// `api` nil: nothing is asked of a server (tests and CI's pictures).
    init(api: FriendDirectoryAPI?, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.youKey) {
            you = try? JSONDecoder().decode(FriendYou.self, from: data)
        }
        if let data = defaults.data(forKey: Self.peopleKey),
           let saved = try? JSONDecoder().decode([FriendPerson].self, from: data) {
            // Nobody counts as online until the server says so.
            people = saved.map { var person = $0; person.online = false; return person }
        }
        if let data = defaults.data(forKey: Self.addedKey),
           let saved = try? JSONDecoder().decode([FriendPerson].self, from: data) {
            added = saved
        }
    }

    private var player: String { OnlinePlayerKey.current(defaults) }

    private func keep(you: FriendYou?) {
        self.you = you
        if let you, let data = try? JSONEncoder().encode(you) {
            defaults.set(data, forKey: Self.youKey)
        } else {
            defaults.removeObject(forKey: Self.youKey)
        }
    }

    private func keep(people: [FriendPerson]) {
        self.people = people
        if let data = try? JSONEncoder().encode(people) { defaults.set(data, forKey: Self.peopleKey) }
    }

    /// Checks in: the player's username (and the name friends see), and the people they play.
    func refresh(name: String) async {
        guard let api else { return }
        let clean = ChallengeName.clean(name)
        do {
            // Kept on this phone when the server can't be reached; only a clear "nobody" clears it.
            keep(you: try await api.me(player: player, name: clean.isEmpty ? nil : clean))
        } catch {
            return
        }
        guard you != nil, let found = try? await api.people(player: player) else { return }
        // The server's word on anyone it knows; the ones added by hand it doesn't list yet come first.
        keep(people: added.filter { person in !found.contains { $0.username == person.username } } + found)
    }

    /// Adds someone to the player's people without sending them a game. They stay for next time.
    func add(_ person: FriendPerson) {
        guard person.username != you?.username else { return }
        if !added.contains(where: { $0.username == person.username }) {
            // Whether they're online is the server's to say, each time.
            var kept = person
            kept.online = false
            added = Array(([kept] + added).prefix(Self.addedLimit))
            if let data = try? JSONEncoder().encode(added) { defaults.set(data, forKey: Self.addedKey) }
        }
        if !people.contains(where: { $0.username == person.username }) {
            keep(people: [person] + people)
        }
    }

    /// Picks (or changes) the player's username. Answers why not, or nil once it's theirs.
    func claim(_ username: String, name: String) async -> String? {
        guard let api else { return ChallengeError.unreachable.message }
        do {
            keep(you: try await api.claim(player: player, username: username, name: ChallengeName.clean(name)))
            return nil
        } catch let error as ChallengeError {
            if error.code == "username_taken" { return "That username is taken. Try another." }
            if case .server(_, _, let message?, _) = error { return message }
            return error.message
        } catch {
            return ChallengeError.unreachable.message
        }
    }

    /// Finds players as the player types, a moment after they stop.
    func search(_ text: String) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard let api, query.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let player = player
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = (try? await api.search(player: player, query: query)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.results = found
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }

    /// Sends a waiting game to someone. Answers why not, or nil once it's on its way.
    func send(code: String, to person: FriendPerson) async -> String? {
        guard let api else { return ChallengeError.unreachable.message }
        do {
            let sent = try await api.invite(player: player, to: person.username, code: code)
            keep(people: [sent] + people.filter { $0.username != sent.username })
            return nil
        } catch let error as ChallengeError {
            if case .server(_, _, let message?, _) = error { return message }
            return error.message
        } catch {
            return ChallengeError.unreachable.message
        }
    }

    /// Looks for challenges sent by username, at most every few seconds unless asked.
    func checkInbox(force: Bool = false) async {
        guard let api, you != nil else { return }
        if !force, let last = lastInboxCheck, Date().timeIntervalSince(last) < 5 { return }
        lastInboxCheck = Date()
        guard let found = try? await api.inbox(player: player) else { return }
        inbox = found
    }

    /// The player opened or turned down a challenge: it stops showing.
    func dismiss(_ note: FriendInviteNote) {
        inbox.removeAll { $0.id == note.id }
        guard let api else { return }
        let player = player
        Task { try? await api.dismiss(player: player, id: note.id) }
    }

    /// A username suggested from the player's name: "Alex Medina" → "alexmedina".
    static func suggestion(from name: String) -> String {
        let letters = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        let trimmed = String(letters.drop { !("a"..."z").contains($0) }.prefix(20))
        return trimmed.count >= 3 ? trimmed : ""
    }
}
