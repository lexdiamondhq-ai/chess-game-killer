import XCTest
@testable import ChessGameKiller

/// Friends by @username without a network: picking a username, sending a challenge to someone,
/// and challenges waiting for the player. Every reply comes from `FakeFriendAPI`.
@MainActor
final class FriendDirectoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private static let suite = "FriendDirectoryTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: Self.suite)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suite)
    }

    private static let maria = FriendPerson(username: "maria", name: "Maria Lopez", online: true)
    private static let jay = FriendPerson(username: "jdog", name: "Jay", online: false)

    func testAUsernameIsSuggestedFromTheName() {
        XCTAssertEqual(FriendDirectory.suggestion(from: "Alex Medina"), "alexmedina")
        XCTAssertEqual(FriendDirectory.suggestion(from: "José_2"), "jose_2")
        XCTAssertEqual(FriendDirectory.suggestion(from: "42 Alfie"), "alfie")
        XCTAssertEqual(FriendDirectory.suggestion(from: "Bo"), "")
    }

    func testClaimingKeepsTheUsernameOnThisPhone() async {
        let api = FakeFriendAPI()
        let friends = FriendDirectory(api: api, defaults: defaults)
        XCTAssertNil(friends.you)
        let problem = await friends.claim("alex_k", name: "Alex")
        XCTAssertNil(problem)
        XCTAssertEqual(friends.you?.username, "alex_k")
        // A new launch remembers it.
        XCTAssertEqual(FriendDirectory(api: nil, defaults: defaults).you?.username, "alex_k")
    }

    func testATakenUsernameSaysSo() async {
        let api = FakeFriendAPI()
        api.taken = ["maria"]
        let friends = FriendDirectory(api: api, defaults: defaults)
        let problem = await friends.claim("maria", name: "Alex")
        XCTAssertEqual(problem, "That username is taken. Try another.")
        XCTAssertNil(friends.you)
    }

    func testSendingPutsThemFirstInYourPeople() async {
        let api = FakeFriendAPI()
        api.people = [Self.jay]
        let friends = FriendDirectory(api: api, defaults: defaults)
        _ = await friends.claim("alex_k", name: "Alex")
        await friends.refresh(name: "Alex")
        XCTAssertEqual(friends.people.map(\.username), ["jdog"])
        let problem = await friends.send(code: "7KQ2XM", to: Self.maria)
        XCTAssertNil(problem)
        XCTAssertEqual(api.sent.first?.code, "7KQ2XM")
        XCTAssertEqual(friends.people.map(\.username), ["maria", "jdog"])
        // Kept for the next launch, nobody online until the server says so.
        let later = FriendDirectory(api: nil, defaults: defaults)
        XCTAssertEqual(later.people.map(\.username), ["maria", "jdog"])
        XCTAssertFalse(later.people[0].online)
    }

    func testAddingKeepsSomeoneWithoutAGame() async {
        let api = FakeFriendAPI()
        api.people = [Self.jay]
        let friends = FriendDirectory(api: api, defaults: defaults)
        _ = await friends.claim("alex_k", name: "Alex")
        friends.add(Self.maria)
        friends.add(Self.maria)
        XCTAssertEqual(friends.people.map(\.username), ["maria"])
        // The server doesn't list her yet: she stays, ahead of the people it does.
        await friends.refresh(name: "Alex")
        XCTAssertEqual(friends.people.map(\.username), ["maria", "jdog"])
        // And on the next launch.
        let later = FriendDirectory(api: nil, defaults: defaults)
        XCTAssertEqual(later.people.map(\.username), ["maria", "jdog"])
        // Once a game went to her the server lists her, and its word on her is the one shown.
        api.people = [Self.maria, Self.jay]
        await friends.refresh(name: "Alex")
        XCTAssertEqual(friends.people.map(\.username), ["maria", "jdog"])
        XCTAssertTrue(friends.people[0].online)
    }

    func testTheInboxNeedsAUsernameAndForgetsADismissedChallenge() async {
        let api = FakeFriendAPI()
        let note = FriendInviteNote(id: "0123456789ab", code: "7KQ2XM", clock: FriendClock(initial: 600, increment: 0),
                                    seat: .black, from: Self.maria)
        api.inbox = [note]
        let friends = FriendDirectory(api: api, defaults: defaults)
        await friends.checkInbox(force: true)
        XCTAssertTrue(friends.inbox.isEmpty, "no username, no challenges by username")
        _ = await friends.claim("alex_k", name: "Alex")
        await friends.checkInbox(force: true)
        XCTAssertEqual(friends.inbox, [note])
        XCTAssertEqual(note.detail, "10+0 · you play Black")
        friends.dismiss(note)
        XCTAssertTrue(friends.inbox.isEmpty)
    }

    func testAnInviteFromTheServerDecodes() throws {
        let json = """
        {"invites":[{"id":"0123456789ab","code":"7KQ2XM","clock":null,"seat":"white","at":1761187200000,
        "from":{"username":"maria","name":"Maria Lopez","online":false}}]}
        """
        struct Reply: Decodable { var invites: [FriendInviteNote] }
        let reply = try JSONDecoder().decode(Reply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.invites.first?.clock, nil)
        XCTAssertEqual(reply.invites.first?.detail, "No clock · you play White")
        XCTAssertEqual(reply.invites.first?.from.initial, "M")
    }
}

/// The friends server, faked: usernames claimed, people, invites sent and waiting.
@MainActor
final class FakeFriendAPI: FriendDirectoryAPI {
    var you: FriendYou?
    var taken: Set<String> = []
    var people: [FriendPerson] = []
    var inbox: [FriendInviteNote] = []
    private(set) var sent: [(to: String, code: String)] = []

    func me(player: String, name: String?) async throws -> FriendYou? { you }

    func claim(player: String, username: String, name: String) async throws -> FriendYou {
        if taken.contains(username) {
            throw ChallengeError.server(status: 409, code: "username_taken", message: nil, game: nil)
        }
        let claimed = FriendYou(username: username, name: name)
        you = claimed
        return claimed
    }

    func search(player: String, query: String) async throws -> [FriendPerson] { [] }

    func people(player: String) async throws -> [FriendPerson] { people }

    func invite(player: String, to username: String, code: String) async throws -> FriendPerson {
        sent.append((username, code))
        return FriendPerson(username: username, name: username, online: true)
    }

    func inbox(player: String) async throws -> [FriendInviteNote] { inbox }

    func dismiss(player: String, id: String) async throws {
        inbox.removeAll { $0.id == id }
    }
}
