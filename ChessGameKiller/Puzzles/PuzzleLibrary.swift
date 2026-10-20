import Foundation

/// A theme in the puzzle picker, named the way Lichess tags its puzzles.
/// Keep in step with THEMES in scripts/puzzles/build_puzzle_pack.py.
struct PuzzleTheme: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case mates = "Checkmates"
        case tactics = "Tactics"
        case advanced = "Advanced ideas"
        case phases = "Game phases"
    }

    /// The Lichess tag, like "fork". Empty for every theme at once.
    let id: String
    let name: String
    let symbol: String
    let group: Group
    /// Other tags that count as this theme, like mate in 5 for "Mate in 4+".
    var alsoMatches: [String] = []

    var tags: Set<String> { Set([id] + alsoMatches) }

    static let all = PuzzleTheme(id: "", name: "All themes", symbol: "square.grid.3x3.fill", group: .tactics)

    static let choices: [PuzzleTheme] = [
        PuzzleTheme(id: "mateIn1", name: "Mate in 1", symbol: "1.circle.fill", group: .mates),
        PuzzleTheme(id: "mateIn2", name: "Mate in 2", symbol: "2.circle.fill", group: .mates),
        PuzzleTheme(id: "mateIn3", name: "Mate in 3", symbol: "3.circle.fill", group: .mates),
        PuzzleTheme(id: "mateIn4", name: "Mate in 4+", symbol: "4.circle.fill", group: .mates, alsoMatches: ["mateIn5"]),
        PuzzleTheme(id: "backRankMate", name: "Back-rank mate", symbol: "rectangle.bottomhalf.filled", group: .mates),
        PuzzleTheme(id: "smotheredMate", name: "Smothered mate", symbol: "square.stack.3d.down.forward.fill", group: .mates),

        PuzzleTheme(id: "fork", name: "Fork", symbol: "arrow.triangle.branch", group: .tactics),
        PuzzleTheme(id: "pin", name: "Pin", symbol: "pin.fill", group: .tactics),
        PuzzleTheme(id: "skewer", name: "Skewer", symbol: "arrow.right.to.line", group: .tactics),
        PuzzleTheme(id: "discoveredAttack", name: "Discovered attack", symbol: "eye.fill", group: .tactics),
        PuzzleTheme(id: "doubleCheck", name: "Double check", symbol: "exclamationmark.2", group: .tactics),
        PuzzleTheme(id: "hangingPiece", name: "Free piece", symbol: "gift.fill", group: .tactics),
        PuzzleTheme(id: "trappedPiece", name: "Trapped piece", symbol: "lock.fill", group: .tactics),
        PuzzleTheme(id: "promotion", name: "Promotion", symbol: "crown.fill", group: .tactics),
        PuzzleTheme(id: "advancedPawn", name: "Advanced pawn", symbol: "arrow.up.circle.fill", group: .tactics),
        PuzzleTheme(id: "kingsideAttack", name: "Kingside attack", symbol: "flame.fill", group: .tactics),
        PuzzleTheme(id: "queensideAttack", name: "Queenside attack", symbol: "flame", group: .tactics),

        PuzzleTheme(id: "sacrifice", name: "Sacrifice", symbol: "bolt.heart.fill", group: .advanced),
        PuzzleTheme(id: "deflection", name: "Deflection", symbol: "arrow.uturn.right", group: .advanced),
        PuzzleTheme(id: "attraction", name: "Attraction", symbol: "scope", group: .advanced),
        PuzzleTheme(id: "clearance", name: "Clearance", symbol: "wind", group: .advanced),
        PuzzleTheme(id: "interference", name: "Interference", symbol: "rectangle.split.2x1.fill", group: .advanced),
        PuzzleTheme(id: "intermezzo", name: "In-between move", symbol: "pause.circle.fill", group: .advanced),
        PuzzleTheme(id: "xRayAttack", name: "X-ray", symbol: "rays", group: .advanced),
        PuzzleTheme(id: "quietMove", name: "Quiet move", symbol: "moon.fill", group: .advanced),
        PuzzleTheme(id: "defensiveMove", name: "Defense", symbol: "shield.fill", group: .advanced),
        PuzzleTheme(id: "zugzwang", name: "Zugzwang", symbol: "hourglass", group: .advanced),
        PuzzleTheme(id: "veryLong", name: "Long combination", symbol: "list.number", group: .advanced),

        PuzzleTheme(id: "opening", name: "Opening", symbol: "door.left.hand.open", group: .phases),
        PuzzleTheme(id: "middlegame", name: "Middlegame", symbol: "circle.grid.cross.fill", group: .phases),
        PuzzleTheme(id: "endgame", name: "Endgame", symbol: "flag.checkered", group: .phases),
        PuzzleTheme(id: "rookEndgame", name: "Rook endgame", symbol: "building.columns.fill", group: .phases),
        PuzzleTheme(id: "pawnEndgame", name: "Pawn endgame", symbol: "person.fill", group: .phases),
        PuzzleTheme(id: "bishopEndgame", name: "Bishop endgame", symbol: "triangle.fill", group: .phases),
        PuzzleTheme(id: "knightEndgame", name: "Knight endgame", symbol: "figure.equestrian.sports", group: .phases),
        PuzzleTheme(id: "queenEndgame", name: "Queen endgame", symbol: "sparkles", group: .phases),
    ]

    static func named(_ id: String) -> PuzzleTheme {
        choices.first { $0.id == id } ?? .all
    }
}

/// One puzzle from the Lichess database, as the pack keeps it.
struct LichessPuzzle: Identifiable, Hashable {
    let id: String
    /// The position before the opponent's move.
    let fen: String
    /// The opponent's move first, then the answer and replies, in UCI.
    let moves: [String]
    let rating: Int
    let themes: [String]

    /// How many moves the player has to find.
    var length: Int { moves.count / 2 }

    var mateIn: Int? {
        for n in 1...5 where themes.contains("mateIn\(n)") { return n }
        return nil
    }

    /// Readable names of its themes, for after it is solved.
    var themeNames: [String] {
        let names = Set(PuzzleTheme.choices.flatMap { theme in
            theme.tags.contains(where: themes.contains) ? [theme.name] : []
        })
        return PuzzleTheme.choices.map(\.name).filter(names.contains)
    }

    var url: URL? { URL(string: "https://lichess.org/training/\(id)") }

    /// The puzzle as a training drill, so it plays on Coach Leo's board.
    var drill: Drill {
        let prompt: String
        if let mateIn {
            prompt = mateIn == 1 ? "Checkmate in one move." : "Checkmate in \(mateIn) moves."
        } else {
            prompt = length == 1 ? "Find the best move." : "Find the best move. It takes \(length) moves."
        }
        return Drill(id: "lichess-\(id)", skill: "puzzles", type: .move, rating: rating, fen: fen,
                     setup: moves.first, solution: Array(moves.dropFirst()), alts: nil, mate: mateIn,
                     squares: nil, move: nil, answer: nil, reply: nil, explain: nil, options: nil,
                     prompt: prompt, limit: nil)
    }

    /// Reads one line of the pack: "id,fen,moves,rating,themes".
    init?(line: Substring) {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 5, let rating = Int(fields[3]) else { return nil }
        let moves = fields[2].split(separator: " ").map(String.init)
        // The opponent's move, then at least one of the player's.
        guard moves.count >= 2, moves.count % 2 == 0 else { return nil }
        id = String(fields[0])
        fen = String(fields[1])
        self.moves = moves
        self.rating = rating
        themes = fields[4].split(separator: " ").map(String.init)
    }

    init(id: String, fen: String, moves: [String], rating: Int, themes: [String]) {
        self.id = id
        self.fen = fen
        self.moves = moves
        self.rating = rating
        self.themes = themes
    }
}

/// Every puzzle in the app, from the Lichess pack in the bundle.
struct PuzzleLibrary {
    let puzzles: [LichessPuzzle]

    init(puzzles: [LichessPuzzle]) {
        self.puzzles = puzzles.sorted { $0.rating < $1.rating }
    }

    /// Reads the pack. Nil when it isn't in the bundle.
    static func bundled(_ bundle: Bundle = .main) -> PuzzleLibrary? {
        guard let url = bundle.url(forResource: "lichess-puzzles", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return PuzzleLibrary(csv: text)
    }

    init(csv text: String) {
        self.init(puzzles: text.split(separator: "\n").dropFirst().compactMap(LichessPuzzle.init(line:)))
    }

    func count(of theme: PuzzleTheme) -> Int {
        theme.id.isEmpty ? puzzles.count : puzzles.filter { $0.themes.contains(where: theme.tags.contains) }.count
    }

    /// A puzzle near `rating` in the theme, not one of `avoid`. The window widens until something fits.
    func pick(near rating: Int, theme: PuzzleTheme, avoid: Set<String>,
              using generator: inout some RandomNumberGenerator) -> LichessPuzzle? {
        let pool = theme.id.isEmpty ? puzzles : puzzles.filter { $0.themes.contains(where: theme.tags.contains) }
        guard !pool.isEmpty else { return nil }
        for window in [75, 150, 300, 600, 3000] {
            let near = pool.filter { abs($0.rating - rating) <= window && !avoid.contains($0.id) }
            if let puzzle = near.randomElement(using: &generator) { return puzzle }
        }
        // Everything in the theme was played recently: allow repeats rather than nothing.
        return pool.min { abs($0.rating - rating) < abs($1.rating - rating) }
    }
}
