import Foundation

/// What a crowd of real players did from one position: every move they played, with how often.
struct CrowdPosition: Equatable, Sendable {
    struct Move: Equatable, Sendable {
        let uci: String
        let san: String
        /// Games that went on with this move.
        let games: Int
    }

    let moves: [Move]

    /// Games that reached the position.
    var games: Int { moves.reduce(0) { $0 + $1.games } }
}

/// The crowd's move, and the vote behind it: "62% played Nf3".
struct CrowdVote: Equatable, Sendable {
    struct Option: Equatable, Sendable {
        let san: String
        /// 0 to 1.
        let share: Double
    }

    let uci: String
    let san: String
    /// The share of the crowd that played this move, 0 to 1.
    let share: Double
    /// Games that reached the position.
    let games: Int
    /// The three most played moves, most played first. The crowd's own move may be any of them.
    let top: [Option]

    /// "62%".
    var percent: String { "\(max(1, Int((share * 100).rounded())))%" }
}

/// Where each crowd's games come from.
enum CrowdSource: Equatable, Sendable {
    /// Lichess players around this rating, in blitz, rapid and classical games.
    case lichess(ratings: [Int])
    /// Over-the-board games between masters.
    case masters
}

extension MatchController.Level {
    /// The games this level's crowd plays from.
    var crowdSource: CrowdSource {
        switch self {
        case .beginner: return .lichess(ratings: [1000])
        case .casual: return .lichess(ratings: [1200])
        case .club: return .lichess(ratings: [1600])
        case .expert: return .lichess(ratings: [2000])
        case .grandmaster: return .masters
        }
    }
}

/// The crowd's games, position by position. A protocol so tests never reach the network.
protocol CrowdBookSource: AnyObject, Sendable {
    /// What the crowd played from `fen`, or nil when it can't be reached in time.
    func position(fen: String, source: CrowdSource) async -> CrowdPosition?
}

enum CrowdBook {
    /// Fewer games than this and the position is too rare to call it the crowd's choice:
    /// Maia, players of the same rating, takes over (Stockfish for the Masters).
    static func minimumGames(for source: CrowdSource) -> Int {
        switch source {
        case .lichess: return 40
        case .masters: return 12
        }
    }

    /// A move nobody much plays is never the crowd's: under this share it is left out.
    static let minimumShare = 0.05

    /// The crowd's move from `position`: drawn in proportion to how often real players chose
    /// it, so the most played move comes most often but a game never repeats itself exactly.
    /// `pick` is in 0..<1. `weight`, given each move in standard notation, leans the draw; 1 leaves
    /// it alone. Nil when the
    /// position is too rare.
    static func vote(from position: CrowdPosition, source: CrowdSource, pick: Double,
                     weight: (String) -> Double = { _ in 1 }) -> CrowdVote? {
        let total = position.games
        guard total >= minimumGames(for: source) else { return nil }
        let ranked = position.moves.sorted { $0.games > $1.games }
        let options = ranked.filter { Double($0.games) / Double(total) >= minimumShare }
        guard !options.isEmpty else { return nil }
        let weights = options.map { Double($0.games) * max(0, weight($0.san)) }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return nil }
        var target = min(max(pick, 0), 0.999_999) * sum
        var chosen = options[options.count - 1]
        for (index, option) in options.enumerated() {
            if target < weights[index] {
                chosen = option
                break
            }
            target -= weights[index]
        }
        let top = ranked.prefix(3).map { CrowdVote.Option(san: $0.san, share: Double($0.games) / Double(total)) }
        return CrowdVote(uci: chosen.uci, san: chosen.san, share: Double(chosen.games) / Double(total),
                         games: total, top: top)
    }

    /// Reads Lichess's opening explorer reply.
    static func parse(_ data: Data) -> CrowdPosition? {
        struct Reply: Decodable {
            struct Move: Decodable {
                let uci: String
                let san: String
                let white: Int
                let draws: Int
                let black: Int
            }
            let moves: [Move]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return CrowdPosition(moves: reply.moves.map {
            CrowdPosition.Move(uci: $0.uci, san: $0.san, games: $0.white + $0.draws + $0.black)
        })
    }

    /// The explorer's address for `fen` from `source`.
    static func url(fen: String, source: CrowdSource) -> URL? {
        var components: URLComponents
        switch source {
        case .lichess(let ratings):
            components = URLComponents(string: "https://explorer.lichess.ovh/lichess")!
            components.queryItems = [
                URLQueryItem(name: "variant", value: "standard"),
                URLQueryItem(name: "speeds", value: "blitz,rapid,classical"),
                URLQueryItem(name: "ratings", value: ratings.map(String.init).joined(separator: ",")),
            ]
        case .masters:
            components = URLComponents(string: "https://explorer.lichess.ovh/masters")!
            components.queryItems = []
        }
        components.queryItems? += [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "moves", value: "12"),
            URLQueryItem(name: "topGames", value: "0"),
            URLQueryItem(name: "recentGames", value: "0"),
        ]
        return components.url
    }
}

/// The crowd from Lichess's opening explorer, a free database of real games by rating.
/// One question at a time, as Lichess asks, and each answer kept for the session.
actor LichessCrowdBook: CrowdBookSource {
    static let shared = LichessCrowdBook()

    private let session: URLSession
    private var cache: [String: CrowdPosition] = [:]
    /// Set after Lichess says to slow down; nothing is asked until then.
    private var quietUntil: Date?

    init(session: URLSession = LichessCrowdBook.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // The crowd must never hold up a move: past this, Stockfish plays instead.
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 3
        configuration.httpAdditionalHeaders = ["User-Agent": "ChessGameKiller-iOS (github.com/lexdiamondhq-ai/chess-game-killer)"]
        return URLSession(configuration: configuration)
    }

    func position(fen: String, source: CrowdSource) async -> CrowdPosition? {
        let key = "\(source)|\(fen)"
        if let hit = cache[key] { return hit }
        if let quietUntil, quietUntil > Date() { return nil }
        guard let url = CrowdBook.url(fen: fen, source: source) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 {
                // Lichess asks for a minute's rest after too many questions.
                quietUntil = Date().addingTimeInterval(60)
                return nil
            }
            guard status == 200, let position = CrowdBook.parse(data) else {
                NSLog("Crowd: explorer answered %d", status)
                return nil
            }
            cache[key] = position
            return position
        } catch {
            NSLog("Crowd: %@", error.localizedDescription)
            return nil
        }
    }
}
