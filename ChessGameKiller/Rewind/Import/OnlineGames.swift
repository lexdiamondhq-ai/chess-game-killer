import Foundation

/// The chess sites a player can bring their games in from.
enum OnlineSite: String, Codable, CaseIterable, Identifiable {
    case chessCom = "chess.com"
    case lichess

    var id: Self { self }

    var title: String {
        switch self {
        case .chessCom: return "Chess.com"
        case .lichess: return "Lichess"
        }
    }
}

/// A finished game from a chess site, before it is graded: who played, how it ended, and the moves.
struct ImportedGame: Equatable, Identifiable {
    let site: OnlineSite
    /// The game's id on the site.
    let gameID: String
    let white: String
    let black: String
    let whiteRating: Int?
    let blackRating: Int?
    /// Nil for a draw.
    let winner: Winner?
    let date: Date
    /// Moves in standard notation, from the usual starting position.
    let moves: [String]
    /// The time control as the app names it ("3+2"), when it is one the app knows.
    let clock: String?

    enum Winner: String, Equatable {
        case white, black
    }

    var id: String { sourceID }

    /// The id kept with the saved game, so a game is brought in once.
    var sourceID: String { "\(site.rawValue):\(gameID)" }

    /// Whether `username` played White. Nil when they played neither side.
    func playerIsWhite(_ username: String) -> Bool? {
        let name = username.lowercased()
        if white.lowercased() == name { return true }
        if black.lowercased() == name { return false }
        return nil
    }
}

// MARK: Reading what the sites send

enum OnlineGames {
    /// How many games one import reads, newest first: enough for Leo to see habits, and
    /// quick enough to grade while the player waits.
    static let importCount = 10

    // MARK: Lichess

    /// Lichess's game export for a player: newest first, standard chess only, as one JSON object per line.
    static func lichessURL(username: String, max: Int) -> URL? {
        guard let name = cleaned(username) else { return nil }
        var components = URLComponents(string: "https://lichess.org/api/games/user/\(name)")
        components?.queryItems = [
            URLQueryItem(name: "max", value: "\(max)"),
            URLQueryItem(name: "moves", value: "true"),
            URLQueryItem(name: "clocks", value: "false"),
            URLQueryItem(name: "evals", value: "false"),
            URLQueryItem(name: "opening", value: "false"),
            URLQueryItem(name: "finished", value: "true"),
            URLQueryItem(name: "perfType", value: "ultraBullet,bullet,blitz,rapid,classical,correspondence"),
        ]
        return components?.url
    }

    /// Games from Lichess's export (one JSON object per line). Lines that aren't finished games
    /// of standard chess are skipped.
    static func parseLichess(_ data: Data) -> [ImportedGame] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let json = try? JSONDecoder().decode(LichessGame.self, from: Data(line.utf8)) else { return nil }
            return json.game
        }
    }

    private struct LichessGame: Decodable {
        struct Player: Decodable {
            struct User: Decodable { let name: String }
            let user: User?
            let rating: Int?
            let aiLevel: Int?

            var name: String {
                if let user { return user.name }
                if let aiLevel { return "Stockfish level \(aiLevel)" }
                return "Anonymous"
            }
        }

        struct Players: Decodable {
            let white: Player
            let black: Player
        }

        struct Clock: Decodable {
            let initial: Int
            let increment: Int
        }

        let id: String
        let variant: String?
        let status: String?
        let createdAt: Double?
        let lastMoveAt: Double?
        let players: Players
        let winner: String?
        let moves: String?
        let initialFen: String?
        let clock: Clock?

        /// Endings that aren't a finished game.
        static let unfinished: Set<String> = ["created", "started", "aborted", "noStart", "unknownFinish", "cheat"]

        var game: ImportedGame? {
            guard variant == nil || variant == "standard", initialFen == nil else { return nil }
            guard let status, !Self.unfinished.contains(status) else { return nil }
            let moves = (moves ?? "").split(separator: " ").map(String.init)
            guard !moves.isEmpty else { return nil }
            let millis = lastMoveAt ?? createdAt ?? 0
            return ImportedGame(
                site: .lichess, gameID: id,
                white: players.white.name, black: players.black.name,
                whiteRating: players.white.rating, blackRating: players.black.rating,
                winner: winner.flatMap(ImportedGame.Winner.init(rawValue:)),
                date: Date(timeIntervalSince1970: millis / 1000),
                moves: moves,
                clock: clock.flatMap { OnlineGames.clockName(seconds: $0.initial, increment: $0.increment) }
            )
        }
    }

    // MARK: Chess.com

    /// The list of a player's monthly game archives on Chess.com, oldest month first.
    static func chessComArchivesURL(username: String) -> URL? {
        guard let name = cleaned(username) else { return nil }
        return URL(string: "https://api.chess.com/pub/player/\(name.lowercased())/games/archives")
    }

    static func parseChessComArchives(_ data: Data) -> [URL] {
        struct Archives: Decodable { let archives: [String] }
        guard let list = try? JSONDecoder().decode(Archives.self, from: data) else { return [] }
        return list.archives.compactMap(URL.init(string:))
    }

    /// One month of a player's Chess.com games, newest first. Games of other variants are skipped.
    static func parseChessComMonth(_ data: Data) -> [ImportedGame] {
        struct Month: Decodable { let games: [Lossy<ChessComGame>] }
        guard let month = try? JSONDecoder().decode(Month.self, from: data) else { return [] }
        return month.games.compactMap { $0.value?.game }.sorted { $0.date > $1.date }
    }

    private struct ChessComGame: Decodable {
        struct Player: Decodable {
            let username: String
            let rating: Int?
            let result: String
        }

        let url: String?
        let uuid: String?
        let pgn: String?
        let time_control: String?
        let end_time: Double?
        let rules: String?
        let initial_setup: String?
        let white: Player
        let black: Player

        /// Results that end the game level.
        static let draws: Set<String> = ["agreed", "repetition", "stalemate", "insufficient", "50move", "timevsinsufficient"]

        var game: ImportedGame? {
            guard rules == nil || rules == "chess" else { return nil }
            if let setup = initial_setup, !setup.isEmpty, !OnlineGames.isStandardStart(setup) { return nil }
            guard let pgn, let id = uuid ?? url?.split(separator: "/").last.map(String.init) else { return nil }
            let moves = PGN.moves(in: pgn)
            guard !moves.isEmpty else { return nil }
            let winner: ImportedGame.Winner?
            if white.result == "win" {
                winner = .white
            } else if black.result == "win" {
                winner = .black
            } else if Self.draws.contains(white.result) || Self.draws.contains(black.result) {
                winner = nil
            } else {
                // Still being played, or an ending this app doesn't know.
                return nil
            }
            return ImportedGame(
                site: .chessCom, gameID: id,
                white: white.username, black: black.username,
                whiteRating: white.rating, blackRating: black.rating,
                winner: winner,
                date: Date(timeIntervalSince1970: end_time ?? 0),
                moves: moves,
                clock: time_control.flatMap(OnlineGames.clockName(chessCom:))
            )
        }
    }

    // MARK: Small helpers

    /// A username as the sites allow them: letters, digits, "_" and "-". Nil for anything else.
    static func cleaned(_ username: String) -> String? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard (2...30).contains(name.count), name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              name.allSatisfy(\.isASCII) else { return nil }
        return name
    }

    /// The app's name for a time control ("3+2"), only when the app plays it too.
    static func clockName(seconds: Int, increment: Int) -> String? {
        guard seconds % 60 == 0 else { return nil }
        let name = "\(seconds / 60)+\(increment)"
        return TimeControl(rawValue: name) == nil ? nil : name
    }

    /// Chess.com writes "180+2" or "600"; a daily game ("1/86400") has no clock the app plays.
    static func clockName(chessCom text: String) -> String? {
        let parts = text.split(separator: "+")
        guard let seconds = parts.first.flatMap({ Int($0) }) else { return nil }
        let increment = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return clockName(seconds: seconds, increment: increment)
    }

    static func isStandardStart(_ fen: String) -> Bool {
        TrainingChess.key(fen) == TrainingChess.key(standardStart)
    }

    static let standardStart = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}

/// Reading the moves out of a PGN.
enum PGN {
    /// The main line's moves in standard notation: headers, comments, side lines, move numbers,
    /// annotation marks and the result are left out.
    static func moves(in pgn: String) -> [String] {
        // The tags are lines in square brackets; the moves are everything else.
        let body = pgn
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
            .joined(separator: " ")
        var text = ""
        var commentDepth = 0
        var variationDepth = 0
        for character in body {
            switch character {
            case "{": commentDepth += 1
            case "}": commentDepth = max(0, commentDepth - 1)
            case "(" where commentDepth == 0: variationDepth += 1
            case ")" where commentDepth == 0: variationDepth = max(0, variationDepth - 1)
            default:
                if commentDepth == 0, variationDepth == 0 { text.append(character) }
            }
        }
        var moves: [String] = []
        for raw in text.split(whereSeparator: \.isWhitespace) {
            var token = Substring(raw)
            // "12." or "12..." alone, or glued to the move as in "1.e4".
            while let first = token.first, first.isNumber {
                token = token.drop { $0.isNumber }
                guard token.first == "." else { token = raw[...]; break }
                token = token.drop { $0 == "." }
            }
            if token.isEmpty || token.hasPrefix("$") { continue }
            if ["1-0", "0-1", "1/2-1/2", "*"].contains(String(token)) { continue }
            moves.append(String(token))
        }
        return moves
    }
}
