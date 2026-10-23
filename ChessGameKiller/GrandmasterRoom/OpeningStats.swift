import ChessKit
import Foundation

/// How people really continue from each named-opening position, counted from the Lichess
/// databases (CC0) by scripts/grandmaster/build_masters.py: top over-the-board games between
/// players rated 2500+ (masters-stats.tsv), and Lichess rated games in five rating bands
/// (club-stats.tsv). Everything ships with the app, so it works offline.
struct OpeningStats: Sendable {
    /// Whose games to count.
    enum Book: Hashable, Sendable {
        case masters
        case band(Band)

        /// The book's column in the stats files: "m", or the band's number.
        var code: String {
            switch self {
            case .masters: return "m"
            case .band(let band): return String(band.rawValue)
            }
        }

        /// "Masters" or "Players 1500–1800".
        var title: String {
            switch self {
            case .masters: return "Masters"
            case .band(let band): return "Players \(band.range)"
            }
        }
    }

    /// Lichess ratings, by the average of the two players. Keep in step with BAND_FLOORS
    /// in scripts/grandmaster/build_masters.py.
    enum Band: Int, CaseIterable, Identifiable, Sendable {
        case under1200, to1500, to1800, to2100, over2100

        var id: Int { rawValue }

        var floor: Int { [0, 1200, 1500, 1800, 2100][rawValue] }

        /// "under 1200", "1500–1800", "2100+".
        var range: String {
            switch self {
            case .under1200: return "under 1200"
            case .over2100: return "2100+"
            default: return "\(floor)–\(Band(rawValue: rawValue + 1)!.floor)"
            }
        }

        /// The band for a rating, like the player's puzzle rating. Puzzle ratings run about
        /// 200 points above game ratings, so that much comes off first.
        static func forPuzzleRating(_ rating: Int) -> Band {
            let game = rating - 200
            return allCases.last { game >= $0.floor } ?? .under1200
        }
    }

    /// One move from a position and how it turned out.
    struct Move: Hashable, Sendable {
        let uci: String
        let games: Int
        let whiteWins: Int
        let draws: Int

        var blackWins: Int { max(0, games - whiteWins - draws) }

        /// Each result as a share of this move's games, 0...1.
        var whiteShare: Double { games == 0 ? 0 : Double(whiteWins) / Double(games) }
        var drawShare: Double { games == 0 ? 0 : Double(draws) / Double(games) }
        var blackShare: Double { games == 0 ? 0 : Double(blackWins) / Double(games) }

        /// The score for the side that plays it, 0...1: wins plus half the draws.
        func score(for mover: Piece.Color) -> Double {
            (mover == .white ? whiteShare : blackShare) + drawShare / 2
        }
    }

    /// The moves from one position, most played first.
    struct Entry: Hashable, Sendable {
        let moves: [Move]
        var total: Int { moves.reduce(0) { $0 + $1.games } }

        /// How often a move is played here, 0...1. Moves too rare to keep count as 0.
        func share(of uci: String) -> Double {
            guard let move = moves.first(where: { $0.uci == uci }), total > 0 else { return 0 }
            return Double(move.games) / Double(total)
        }
    }

    /// "<placement> <side>\t<book>" to its moves.
    private let table: [String: [Move]]

    var isEmpty: Bool { table.isEmpty }

    init(table: [String: [Move]] = [:]) {
        self.table = table
    }

    /// Reads both files from the bundle. Empty when they aren't there yet.
    static func load(from bundle: Bundle = .main) -> OpeningStats {
        var table: [String: [Move]] = [:]
        for name in ["masters-stats", "club-stats"] {
            guard let url = bundle.url(forResource: name, withExtension: "tsv"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            table.merge(parse(text), uniquingKeysWith: { first, _ in first })
        }
        return OpeningStats(table: table)
    }

    static let shared = load()

    /// Lines of "key<TAB>book<TAB>uci games white draws,...", after a header line.
    static func parse(_ text: String) -> [String: [Move]] {
        var table: [String: [Move]] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let moves: [Move] = fields[2].split(separator: ",").compactMap { cell in
                let parts = cell.split(separator: " ")
                guard parts.count == 4, let games = Int(parts[1]), let white = Int(parts[2]),
                      let draws = Int(parts[3]), games > 0 else { return nil }
                return Move(uci: String(parts[0]), games: games, whiteWins: white, draws: draws)
            }
            if !moves.isEmpty { table["\(fields[0])\t\(fields[1])"] = moves }
        }
        return table
    }

    /// What the book's players play in a position, or nil when too few games reached it.
    func entry(fen: String, book: Book) -> Entry? {
        table["\(TrainingChess.key(fen))\t\(book.code)"].map(Entry.init(moves:))
    }
}
