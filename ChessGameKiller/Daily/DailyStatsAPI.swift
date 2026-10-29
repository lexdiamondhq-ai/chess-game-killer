import Foundation

// How the world did on Today's Move: the game server counts each player once a day (by the hash
// of the same private key Play online uses) and answers how many played and how many found it.
// See play/PROTOCOL.md, "Today's Move".

/// The day's count across every player.
struct DailyTally: Decodable, Equatable, Sendable {
    var players: Int
    var found: Int

    /// Out of 100, rounded; nil before anyone has played.
    var percentFound: Int? {
        players > 0 ? Int((Double(found) * 100 / Double(players)).rounded()) : nil
    }

    /// "62% of 1,284 players found it." — or, with only a few in, "You're one of the first 8."
    var line: String {
        guard let percent = percentFound else { return "You're the first to try it today." }
        if players < 20 { return "You're one of the first \(players) players to try it today." }
        let count = players.formatted(.number)
        return "\(percent)% of \(count) players found it."
    }
}

protocol DailyStatsAPI: AnyObject {
    /// Counts this player's try (once a day; a second report changes nothing) and answers the tally.
    func report(day: String, puzzle: String, found: Bool, player: String) async throws -> DailyTally
}

final class LiveDailyStatsAPI: DailyStatsAPI {
    static let shared = LiveDailyStatsAPI()

    private let base: URL
    private let session: URLSession

    init(base: URL = ChallengeLink.serverURL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    private struct ReportBody: Encodable {
        let player: String
        let puzzle: String
        let found: Bool
    }

    func report(day: String, puzzle: String, found: Bool, player: String) async throws -> DailyTally {
        var request = URLRequest(url: base.appending(path: "api/daily/\(day)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ReportBody(player: player, puzzle: puzzle, found: found))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DailyTally.self, from: data)
    }
}
