import Foundation

/// Names the opening a game reached, by position, so a different move order still finds
/// it. Every named line is indexed by the position it ends in (opening-positions.tsv, built
/// by scripts/grandmaster/build_opening_positions.py from openings.tsv), so nothing is
/// replayed on the phone.
struct OpeningIndex {
    /// The named lines, in openings.tsv order.
    let lines: [OpeningLine]
    /// Piece placement and side to move (TrainingChess.key) to a line's place in `lines`.
    let byKey: [String: Int]

    /// Openings are named in the first 20 moves each.
    static let maxPlies = 40

    static let shared: OpeningIndex = {
        let text = Bundle.main.url(forResource: "opening-positions", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return OpeningIndex(lines: GrandmasterContent.shared.openings, byKey: parse(text))
    }()

    static func parse(_ text: String) -> [String: Int] {
        var keys: [String: Int] = [:]
        for row in text.split(separator: "\n").dropFirst() {
            let fields = row.split(separator: "\t")
            guard fields.count == 2, let line = Int(fields[1]) else { continue }
            keys[String(fields[0])] = line
        }
        return keys
    }

    /// The deepest named opening among a game's positions (the start first), or nil when
    /// the game never reached one.
    func opening(of positions: [String]) -> OpeningLine? {
        for fen in positions.prefix(Self.maxPlies + 1).reversed() {
            if let index = byKey[TrainingChess.key(fen)], lines.indices.contains(index) {
                return lines[index]
            }
        }
        return nil
    }

    /// The main line of a named opening: the line with exactly that name, shortest first,
    /// or else the shortest line of the family.
    func line(named name: String) -> OpeningLine? {
        let exact = lines.filter { $0.name == name }
        if let shortest = exact.min(by: { $0.moves.count < $1.moves.count }) { return shortest }
        return lines.filter { $0.family == name }.min { $0.moves.count < $1.moves.count }
    }
}
