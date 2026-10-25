import ChessKit
import Foundation
import Observation

/// A famous game for Guess the Move. Built by scripts/grandmaster/build_room.py.
struct ClassicGame: Decodable, Identifiable, Hashable {
    let id: String
    let white: String
    let black: String
    let event: String
    let year: Int
    let result: String
    let blurb: String
    /// Every move, in UCI.
    let moves: [String]
    /// The named opening it starts with, for master games from the Lichess broadcasts.
    var opening: String? = nil
    /// "2830 – 2760", for master games.
    var ratings: String? = nil

    /// A game from the Lichess broadcasts, not one of the hand-picked classics.
    var isMasterGame: Bool { id.hasPrefix("m-") }

    /// The side the player guesses for: the winner's.
    var hero: Piece.Color { result == "0-1" ? .black : .white }
    var heroName: String { hero == .white ? white : black }
    var title: String { "\(white) – \(black)" }
    /// "Tata Steel Chess 2025", or just the event when the year isn't known.
    var playedAt: String { year > 0 ? "\(event) \(String(year))" : event }
}

/// An endgame every player must know, played against perfect defence. Built and checked
/// by scripts/grandmaster/build_endgames.py.
struct EndgameStudy: Decodable, Identifiable, Hashable {
    /// The shelves of the endgame library, in the order they are shown.
    enum Group: String, Decodable, CaseIterable {
        case mustKnow = "Must know"
        case rookEndings = "Rook endings"
        case expert = "Expert"
    }

    /// The side the player takes: always the side to move in the position.
    enum Side: String, Decodable {
        case white, black

        var color: Piece.Color { self == .white ? .white : .black }
    }

    /// The result the player must keep, which is the position's true result.
    enum Goal: String, Decodable {
        case win, draw

        /// 1 for a win, 0 for a draw, the way judges score a position for the player.
        var value: Int { self == .win ? 1 : 0 }
    }

    let id: String
    let title: String
    let group: Group
    /// 1 basic, 2 classic, 3 hard.
    let level: Int
    let fen: String
    let side: Side
    let goal: Goal
    /// The plan, shown before the first move.
    let idea: String
    /// The one thing to remember, shown after a slip.
    let tip: String
    /// For a draw: how many good moves in a row count as holding it, when not the usual number.
    let hold: Int?

    var player: Piece.Color { side.color }

    /// Good moves in a row that hold a draw.
    var movesToHold: Int { hold ?? 10 }

    /// "White to play and win", "Black to play and draw".
    var goalText: String {
        "\(player.displayName) to play and \(goal.rawValue)"
    }

    /// The level in a word: "Basic", "Classic" or "Hard".
    var levelName: String {
        ["Basic", "Classic", "Hard"][min(max(level, 1), 3) - 1]
    }
}

/// A named opening line from lichess-org/chess-openings (CC0).
struct OpeningLine: Identifiable, Hashable {
    let eco: String
    let name: String
    let moves: [String]

    var id: String { name + "|" + moves.joined(separator: " ") }
    /// "Sicilian Defense" for "Sicilian Defense: Najdorf Variation".
    var family: String { String(name.split(separator: ":", maxSplits: 1).first ?? Substring(name)) }
    var variation: String {
        let parts = name.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "Main line"
    }
    /// The side that plays the last move of the line, which is usually the side that chose it.
    var naturalSide: Piece.Color { moves.count % 2 == 1 ? .white : .black }
}

/// Everything in the Grandmaster Room that ships with the app.
struct GrandmasterContent {
    let games: [ClassicGame]
    /// Recent decisive classical games between people rated 2500+, from the Lichess broadcast database
    /// (CC0), newest first. Built by scripts/grandmaster/build_masters.py.
    var masterGames: [ClassicGame] = []
    let endgames: [EndgameStudy]
    let openings: [OpeningLine]

    static let shared: GrandmasterContent = load(from: .main)

    static func load(from bundle: Bundle) -> GrandmasterContent {
        struct Games: Decodable { let games: [ClassicGame] }
        struct Endgames: Decodable { let endgames: [EndgameStudy] }
        let decoder = JSONDecoder()
        let games = bundle.url(forResource: "classic-games", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode(Games.self, from: $0).games } ?? []
        let endgames = bundle.url(forResource: "endgames", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode(Endgames.self, from: $0).endgames } ?? []
        let text = bundle.url(forResource: "openings", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let masters = bundle.url(forResource: "masters-games", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .map(parseMasterGames) ?? []
        return GrandmasterContent(games: games, masterGames: masters, endgames: endgames, openings: parseOpenings(text))
    }

    /// masters-games.json keeps each game's moves as one string, to stay small.
    static func parseMasterGames(_ data: Data) -> [ClassicGame] {
        struct Record: Decodable {
            let id, white, black, event, result, blurb, moves: String
            let year: Int
            let opening: String?
            let whiteElo, blackElo: Int?
        }
        struct File: Decodable { let games: [Record] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.games.compactMap { record in
            let moves = record.moves.split(separator: " ").map(String.init)
            guard !moves.isEmpty else { return nil }
            let ratings = record.whiteElo.flatMap { white in record.blackElo.map { "\(white) – \($0)" } }
            return ClassicGame(id: record.id, white: record.white, black: record.black, event: record.event,
                               year: record.year, result: record.result, blurb: record.blurb, moves: moves,
                               opening: record.opening, ratings: ratings)
        }
    }

    /// Master games that follow a line from the start, newest first, as model games for it.
    func masterGames(following moves: [String], limit: Int = 8) -> [ClassicGame] {
        Array(masterGames.lazy.filter { $0.moves.starts(with: moves) }.prefix(limit))
    }

    static func parseOpenings(_ text: String) -> [OpeningLine] {
        text.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return nil }
            let moves = fields[2].split(separator: " ").map(String.init)
            guard !moves.isEmpty else { return nil }
            return OpeningLine(eco: String(fields[0]), name: String(fields[1]), moves: moves)
        }
    }

    /// Opening families in alphabetical order, each with its lines shortest first.
    var openingFamilies: [(name: String, lines: [OpeningLine])] {
        Dictionary(grouping: openings, by: \.family)
            .map { (name: $0.key, lines: $0.value.sorted { ($0.moves.count, $0.name) < ($1.moves.count, $1.name) }) }
            .sorted { $0.name < $1.name }
    }
}

// MARK: Tablebase

/// What the Lichess tablebase says about a position, from the side to move.
struct TablebaseResult: Decodable, Sendable {
    struct Move: Decodable, Sendable {
        let uci: String
        let san: String
        /// The result for the side to move after this move: "loss" here is a win for the mover.
        let category: String
        let dtm: Int?
    }

    let category: String
    /// Plies to mate with perfect play (five pieces or fewer): positive when the side to move mates.
    let dtm: Int?
    let checkmate: Bool?
    let stalemate: Bool?
    /// Every legal move, best first.
    let moves: [Move]

    /// +1 win, 0 draw, -1 loss for the side to move.
    var value: Int { Self.value(of: category) }

    /// Moves (not plies) to mate with perfect play, when the tablebase knows: positive when the
    /// side to move mates, negative when it is mated.
    var mateInMoves: Int? {
        guard let dtm, dtm != 0 else { return nil }
        let moves = (abs(dtm) + 1) / 2
        return dtm > 0 ? moves : -moves
    }

    /// The value of a move for the side that plays it.
    func value(of uci: String) -> Int? {
        moves.first { $0.uci == uci }.map { -Self.value(of: $0.category) }
    }

    static func value(of category: String) -> Int {
        switch category {
        case "win", "syzygy-win", "maybe-win": return 1
        case "loss", "syzygy-loss", "maybe-loss": return -1
        default: return 0
        }
    }
}

/// Looks positions up in the Lichess endgame tablebase (up to seven pieces).
enum Tablebase {
    /// The most pieces, kings included, the tablebase knows.
    static let maxPieces = 7

    /// Whether the tablebase can answer for a position: seven pieces or fewer, and no castling rights.
    static func covers(_ fen: String) -> Bool {
        let fields = fen.split(separator: " ")
        guard let placement = fields.first else { return false }
        let castling = fields.count > 2 ? fields[2] : "-"
        return placement.filter(\.isLetter).count <= maxPieces && castling == "-"
    }

    static func probe(_ fen: String, timeout: TimeInterval = 8) async throws -> TablebaseResult {
        var components = URLComponents(string: "https://tablebase.lichess.ovh/standard")!
        components.queryItems = [URLQueryItem(name: "fen", value: fen)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TablebaseResult.self, from: data)
    }
}

/// Something that looks positions up in a tablebase: Lichess in the app, a fake in tests.
protocol TablebaseProbing: Sendable {
    func probe(_ fen: String) async throws -> TablebaseResult
}

/// The Lichess tablebase, with a short timeout so a weak connection soon hands over to Stockfish.
struct LichessTablebase: TablebaseProbing {
    var timeout: TimeInterval = 4

    func probe(_ fen: String) async throws -> TablebaseResult {
        try await Tablebase.probe(fen, timeout: timeout)
    }
}

// MARK: Repertoire

/// One opening line the player is learning, on a spaced-repetition schedule.
struct RepertoireEntry: Codable, Identifiable, Hashable {
    var id: String { lineID + "|" + side }
    let lineID: String
    let name: String
    let moves: [String]
    /// "w" or "b": the side the player plays in this line.
    let side: String
    /// Leitner box: 0 is new; each clean review moves it up.
    var box: Int = 0
    var due: Date = .now

    var color: Piece.Color { side == "b" ? .black : .white }

    init(lineID: String, name: String, moves: [String], side: String, box: Int = 0, due: Date = .now) {
        self.lineID = lineID
        self.name = name
        self.moves = moves
        self.side = side
        self.box = box
        self.due = due
    }

    private enum CodingKeys: String, CodingKey { case lineID, name, moves, side, box, due }

    /// Reads any saved version: a key a file doesn't have yet keeps its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try c.decode(String.self, forKey: .lineID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        moves = try c.decodeIfPresent([String].self, forKey: .moves) ?? []
        side = try c.decodeIfPresent(String.self, forKey: .side) ?? "w"
        box = try c.decodeIfPresent(Int.self, forKey: .box) ?? 0
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? .now
    }
}

/// The player's opening repertoire and when each line is next due.
@MainActor
@Observable
final class RepertoireStore {
    private(set) var entries: [RepertoireEntry]
    private let fileURL: URL?
    /// Days until the next review, by box, as in Coach Leo's mistake reviews.
    static let gaps = [0, 1, 3, 7, 16, 35]

    init(entries: [RepertoireEntry] = [], fileURL: URL? = nil) {
        self.entries = entries
        self.fileURL = fileURL
    }

    static func live() -> RepertoireStore {
        let url = ProgressFile.url("repertoire.json")
        let saved = ProgressFile.read([Lossy<RepertoireEntry>].self, at: url)?.compactMap(\.value) ?? []
        return RepertoireStore(entries: saved, fileURL: url)
    }

    var due: [RepertoireEntry] {
        entries.filter { $0.due <= .now }.sorted { $0.due < $1.due }
    }

    func contains(_ line: OpeningLine, side: Piece.Color) -> Bool {
        entries.contains { $0.lineID == line.id && $0.color == side }
    }

    func add(_ line: OpeningLine, side: Piece.Color) {
        guard !contains(line, side: side) else { return }
        entries.append(RepertoireEntry(lineID: line.id, name: line.name, moves: line.moves, side: side == .white ? "w" : "b"))
        save()
    }

    func remove(_ entry: RepertoireEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// A clean run moves the line up a box; any slip sends it back to the start.
    func reviewed(_ entry: RepertoireEntry, clean: Bool, now: Date = .now) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries[index]
        updated.box = clean ? min(updated.box + 1, Self.gaps.count - 1) : 0
        let days = clean ? Self.gaps[updated.box] : 1
        updated.due = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        entries[index] = updated
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
