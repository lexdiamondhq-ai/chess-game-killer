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

    /// The side the player guesses for: the winner's.
    var hero: Piece.Color { result == "0-1" ? .black : .white }
    var heroName: String { hero == .white ? white : black }
    var title: String { "\(white) – \(black)" }
}

/// An endgame to play perfectly against the tablebase.
struct EndgameStudy: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    /// 1 basic, 2 classic, 3 hard.
    let level: Int
    let fen: String
    let idea: String

    var player: Piece.Color { fen.split(separator: " ").dropFirst().first == "b" ? .black : .white }
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
        return GrandmasterContent(games: games, endgames: endgames, openings: parseOpenings(text))
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
struct TablebaseResult: Decodable {
    struct Move: Decodable {
        let uci: String
        let san: String
        /// The result for the side to move after this move: "loss" here is a win for the mover.
        let category: String
        let dtm: Int?
    }

    let category: String
    let dtm: Int?
    let checkmate: Bool?
    let stalemate: Bool?
    let moves: [Move]

    /// +1 win, 0 draw, -1 loss for the side to move.
    var value: Int { Self.value(of: category) }

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
    static func probe(_ fen: String) async throws -> TablebaseResult {
        var components = URLComponents(string: "https://tablebase.lichess.ovh/standard")!
        components.queryItems = [URLQueryItem(name: "fen", value: fen)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TablebaseResult.self, from: data)
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
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("repertoire.json")
        let saved = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([RepertoireEntry].self, from: $0) } ?? []
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
