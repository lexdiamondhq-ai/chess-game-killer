import Foundation

/// Your Chess DNA: what the coach has learned about how this player plays, rebuilt from
/// every graded game and every rated puzzle after each one. It places four habits next to
/// real players (`RealPlayers`) and names a style from the one that stands out most, lists
/// what the player is good at (the first is their weapon) and what to work on (the first is
/// their leak), what they really play in the opening and how it goes, one opening that suits
/// them, and whether each area is getting better. Pure data in, so it's easy to test, and it
/// runs off the main thread.
struct ChessDNA: Equatable {
    // MARK: Style

    enum Style: String, CaseIterable, Identifiable {
        case attacker, tactician, counterpuncher, grinder, builder, allRounder

        var id: String { rawValue }

        var title: String {
            switch self {
            case .attacker: return "Attacker"
            case .tactician: return "Tactician"
            case .counterpuncher: return "Counterpuncher"
            case .grinder: return "Grinder"
            case .builder: return "Builder"
            case .allRounder: return "All-rounder"
            }
        }

        var symbol: String {
            switch self {
            case .attacker: return "flame.fill"
            case .tactician: return "bolt.fill"
            case .counterpuncher: return "arrow.uturn.backward.circle.fill"
            case .grinder: return "hourglass"
            case .builder: return "building.columns.fill"
            case .allRounder: return "circle.hexagongrid.fill"
            }
        }

        /// One or two sentences, in the coach's voice.
        var portrait: String {
            switch self {
            case .attacker: return "You go for the king. You'd rather give up material than sit still, and you play for the win from move one."
            case .tactician: return "You see checks and captures first and punish every loose piece. Sharp, but you keep your own king safe."
            case .counterpuncher: return "You're hard to put away. You absorb pressure, wait for their slip, then hit back."
            case .grinder: return "You like long games. You keep pieces on, squeeze, and win the endgame."
            case .builder: return "You set up soundly and avoid risks. Your games are calm until you decide they aren't."
            case .allRounder: return "No single habit stands out yet: you play the position in front of you."
            }
        }

        /// Puzzle themes that sharpen this style: one is mixed into every daily session.
        var themes: [String] {
            switch self {
            case .attacker: return ["kingsideAttack", "sacrifice", "attraction", "mateIn3"]
            case .tactician: return ["fork", "discoveredAttack", "deflection", "intermezzo"]
            case .counterpuncher: return ["defensiveMove", "equality", "intermezzo", "quietMove"]
            case .grinder: return ["rookEndgame", "pawnEndgame", "endgame", "zugzwang"]
            case .builder: return ["quietMove", "middlegame", "clearance", "defensiveMove"]
            case .allRounder: return ["fork", "pin", "mateIn2", "endgame"]
            }
        }

        /// Openings that fit the style, as names in openings.tsv: one for White, one for Black.
        var openings: (white: String, black: String) {
            switch self {
            case .attacker: return ("Italian Game: Evans Gambit", "Sicilian Defense: Dragon Variation")
            case .tactician: return ("Scotch Game", "Scandinavian Defense")
            case .counterpuncher: return ("English Opening", "King's Indian Defense: Normal Variation")
            case .grinder: return ("London System", "Caro-Kann Defense")
            case .builder: return ("Queen's Gambit", "Queen's Gambit Declined")
            case .allRounder: return ("Ruy Lopez", "French Defense")
            }
        }

        /// Why that opening, in a few words.
        var openingReason: String {
            switch self {
            case .attacker: return "fast development and early pressure on the king"
            case .tactician: return "open lines and pieces in contact early"
            case .counterpuncher: return "you let them come forward, then strike back"
            case .grinder: return "solid structures that last into the endgame"
            case .builder: return "classical, sound and easy to build on"
            case .allRounder: return "rich, classical positions with every kind of play"
            }
        }
    }

    /// One of the four habits, placed next to real players.
    struct Trait: Equatable, Identifiable {
        enum Kind: String, CaseIterable {
            case aggression, risk, patience, endgames

            var title: String {
                switch self {
                case .aggression: return "Aggression"
                case .risk: return "Risk"
                case .patience: return "Patience"
                case .endgames: return "Endgames"
                }
            }

            /// The words at each end of the bar.
            var ends: (low: String, high: String) {
                switch self {
                case .aggression: return ("Quiet", "Aggressive")
                case .risk: return ("Safe", "Daring")
                case .patience: return ("Quick", "Patient")
                case .endgames: return ("Shaky", "Strong")
                }
            }

            /// The words for a player clearly short of most players on this habit, or clearly past them.
            var compared: (less: String, more: String) {
                switch self {
                case .aggression: return ("Quieter", "More aggressive")
                case .risk: return ("Safer", "More daring")
                case .patience: return ("Quicker", "More patient")
                case .endgames: return ("Shakier", "Stronger")
                }
            }
        }

        let kind: Kind
        /// Where the habit sits among real players. Nil until there's enough to judge.
        let standing: RealPlayers.Standing?

        var id: String { kind.rawValue }

        /// Where to draw it on the bar, 0 to 1. The typical player is the middle.
        var value: Double? { standing?.place }

        /// One word, for a small card: an end's word once the player is clearly on that side
        /// of most players, "Balanced" otherwise.
        var word: String {
            guard let standing else { return "Not enough yet" }
            if standing.isAhead { return kind.ends.high }
            if standing.isBehind { return kind.ends.low }
            return "Balanced"
        }

        /// The comparison in full: "Safer than 8 in 10", or "Like most players".
        var comparison: String {
            guard let standing else { return "Not enough yet" }
            if standing.isAhead { return "\(kind.compared.more) than \(RealPlayers.Standing.inTen(standing.below)) in 10" }
            if standing.isBehind { return "\(kind.compared.less) than \(RealPlayers.Standing.inTen(standing.above)) in 10" }
            return "Like most players"
        }
    }

    // MARK: Strengths

    /// Something the player is good at, with the proof.
    struct Strength: Equatable, Identifiable {
        /// Like "Forks".
        let title: String
        /// The proof in a sentence: "You found 9 of 9. Most players find 7."
        let detail: String
        let symbol: String
        /// The puzzle theme that keeps it sharp, when there is one.
        var theme: String?
        /// Where it showed in the player's games, newest game first.
        var sightings: [Sighting] = []

        var id: String { title }
    }

    /// One place in one game.
    struct Sighting: Hashable, Identifiable {
        let game: UUID
        /// The player's move, by ply. 0 is the game as a whole.
        let ply: Int

        var id: String { "\(game.uuidString)-\(ply)" }
    }

    // MARK: Weapon

    /// The player's best weapon, with the evidence for it: the first strength that has
    /// puzzles to keep it sharp.
    struct Weapon: Equatable {
        let title: String
        let detail: String
        let symbol: String
        /// The puzzle theme that keeps it sharp.
        let theme: String
    }

    // MARK: Openings

    /// How one opening has gone for the player with one color.
    struct OpeningRecord: Equatable, Identifiable {
        /// Like "Sicilian Defense".
        let family: String
        let playerIsWhite: Bool
        /// The line the player reached most often in it, for the trainer.
        let line: OpeningLine
        let wins: Int
        let draws: Int
        let losses: Int
        /// Average accuracy in those games, when graded.
        let accuracy: Int?

        var id: String { family + (playerIsWhite ? "|w" : "|b") }
        var games: Int { wins + draws + losses }
        /// Points per game, 0 to 1: a win 1, a draw ½.
        var score: Double { games == 0 ? 0 : (Double(wins) + Double(draws) / 2) / Double(games) }
        /// "3–1–0".
        var tally: String { "\(wins)–\(draws)–\(losses)" }
    }

    /// One opening to learn next, and why.
    struct OpeningPick: Equatable, Identifiable {
        let line: OpeningLine
        let playerIsWhite: Bool
        let reason: String
        /// True when it's one the player already plays and does well in.
        let isTheirs: Bool

        var id: String { line.id + (playerIsWhite ? "|w" : "|b") }
    }

    // MARK: Growth

    /// Costly moves a game in one area, the last games against the ones before them.
    struct Trend: Equatable, Identifiable {
        let area: CoachReport.Area
        let before: Double
        let now: Double

        var id: String { area.rawValue }
        /// At least a quarter fewer costly moves, and a real number to start from.
        var improved: Bool { before >= 0.5 && now <= before * 0.75 }
        var worse: Bool { now >= 0.5 && now >= max(before, 0.25) * 1.33 }
    }

    // MARK: The profile

    let gamesRead: Int
    /// The games long enough to read a style from: a quick resignation tells nothing.
    let gamesCounted: Int
    /// Games read that were brought in from Lichess or Chess.com.
    let gamesImported: Int
    let puzzlesRead: Int
    /// Nil until enough games are read.
    let style: Style?
    let traits: [Trait]
    /// The six areas and what to work on, from the recent games.
    let report: CoachReport
    /// Up to three things the player is good at, the best proof first.
    let strengths: [Strength]
    let weapon: Weapon?
    /// Most played first, up to three for each color.
    let openings: [OpeningRecord]
    let picks: [OpeningPick]
    /// Nil until there are two windows of games to compare.
    let trends: [Trend]
    /// Average accuracy, the last games against the ones before them.
    let accuracyTrend: AccuracyTrend?

    struct AccuracyTrend: Equatable {
        let before: Int
        let now: Int
    }

    var leak: CoachReport.Leak? { report.leak }
    /// Up to three things to work on, the furthest behind real players first.
    var weakSpots: [CoachReport.Leak] { report.weakSpots }
    var hasStyle: Bool { style != nil }

    /// The small print under the profile: which games it was read from, and what the bars
    /// are measured against.
    var basisNote: String {
        let games = gamesRead == 1 ? "1 game" : "\(gamesRead) games"
        return "Read from \(games) and your rated puzzles. Every game counts: against the rivals, against people (read a little after the game ends) and the ones you bring in from online. The bars and your style come from your newest \(Self.habitWindow) games, next to \(RealPlayers.players) real online players."
    }

    /// How long the style has to stand: said under it once it is named.
    var styleNote: String? {
        guard style != nil else { return nil }
        let games = gamesCounted >= Self.habitWindow ? "your last \(Self.habitWindow) games" : "\(gamesCounted) games"
        return "Named from \(games). It stays until your games really change."
    }

    /// "Play one more game": what the style is still waiting for, counting only games long
    /// enough to read, so the number goes down when a game is played out.
    var styleWait: String {
        let left = max(1, Self.gamesForStyle - gamesCounted)
        let games = left == 1 ? "one more game" : "\(left) more games"
        // Games were played but too short to read: say what counts, or the number looks stuck.
        let long = gamesRead > gamesCounted ? " of ten moves or more" : ""
        return "Play \(games)\(long)"
    }

    /// The area that improved most, for the headline.
    var biggestImprovement: Trend? {
        trends.filter(\.improved).max { ($0.before - $0.now) < ($1.before - $1.now) }
    }

    /// The puzzle theme that trains the leak, when there is one.
    var leakTheme: PuzzleTheme? { leak.map(PuzzleSessionBuilder.theme(for:)) }
    var weaponTheme: PuzzleTheme? { weapon.map { PuzzleTheme.named($0.theme) } }

    /// A style theme for the day, turning through the style's list, skipping any in `excluding`.
    func styleTheme(on date: Date, excluding: Set<String> = [], calendar: Calendar = .current) -> PuzzleTheme? {
        guard let style else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        for step in 0..<style.themes.count {
            let id = style.themes[(day + step) % style.themes.count]
            if !excluding.contains(id) { return PuzzleTheme.named(id) }
        }
        return nil
    }

    // MARK: Limits

    /// Games read for the openings and for how the style grew: everything the vault keeps.
    static let gameLimit = 150
    /// Games the habits are read from: the newest ones long enough to read. The same number the
    /// ruler was measured on (`RealPlayers`), so "more patient than 7 in 10" means what it says,
    /// and few enough that a real change in how the player plays shows.
    static let habitWindow = CoachReport.gameLimit
    /// A game counts once the player made this many moves in it.
    static let movesToCount = 10
    /// Games needed before a style is named. Fewer, and one odd game renames the player.
    static let gamesForStyle = 8
    /// How far a style's habits have to stand out before it is named: 0.5 is the typical player.
    static let styleFloor = 0.62
    /// How much further another style has to stand out before the name changes.
    static let styleMargin = 0.12
    /// Games the player stood clearly worse in before their comebacks are judged.
    static let gamesForComebacks = 3
    /// Chances at a pattern before the share the player found counts as proof.
    static let chancesToCount = 4
    /// How far past the usual share that has to be, in `RealPlayers.FindRate` spreads.
    static let clearLead = 0.3
    /// The most strengths listed.
    static let strengthLimit = 3
    /// Games in each window when comparing then and now.
    static let trendWindow = 10
    static let minimumTrendWindow = 4
    /// Puzzles in a theme before its record counts as evidence.
    static let puzzlesToCount = 8

    // MARK: Building it

    static func make(games: [SavedGame], puzzleStats: [String: ThemeRecord] = [:], puzzlesPlayed: Int = 0,
                     index: OpeningIndex = .shared) -> ChessDNA {
        let own = Array(games.filter(\.isPlayersOwn).sorted { $0.date > $1.date }.prefix(gameLimit))
        let tallies = own.map { CoachReport.Tally($0) }
        let report = CoachReport.make(tallies: tallies)
        // A game too short to read has no habits.
        let habits: [GameHabits?] = own.map { game in
            game.playerMoments.count >= movesToCount || game.moves.count >= 2 * movesToCount ? GameHabits(game) : nil
        }
        let reading = Self.reading(habits: habits, tallies: tallies)
        let openings = Self.openings(games: own, index: index)
        let strengths = Self.strengths(games: own, report: report, puzzleStats: puzzleStats, index: index)
        let sharpest = strengths.first { $0.theme != nil }
        return ChessDNA(
            gamesRead: own.count,
            gamesCounted: habits.compactMap { $0 }.count,
            gamesImported: own.filter(\.isImported).count,
            puzzlesRead: puzzlesPlayed,
            style: reading.style,
            traits: reading.traits,
            report: report,
            strengths: Array(strengths.prefix(strengthLimit)),
            weapon: sharpest.map { Weapon(title: $0.title, detail: $0.detail, symbol: $0.symbol, theme: $0.theme ?? "") },
            openings: openings,
            picks: picks(style: reading.style, openings: openings, index: index),
            trends: trends(games: own),
            accuracyTrend: accuracyTrend(games: own)
        )
    }

    // MARK: Habits

    /// The habits of one game, from the player's side.
    struct GameHabits: Equatable {
        var moves = 0
        var checks = 0
        var captures = 0
        /// Moves that land in the opponent's half.
        var forward = 0
        /// The player's move number when they castled, nil if they never did.
        var castledOn: Int?
        /// Material given up for at least a move, without the engine calling it a mistake,
        /// while the game was still to be decided.
        var sacrifices = 0
        /// The queen out before move 6.
        var earlyQueen = false
        /// Captures by either side in the first 15 moves each.
        var earlyCaptures = 0
        /// The whole game's length, in moves each.
        var length = 0
        /// The player stood clearly worse after one of their own moves, while the game was
        /// still being played. How it ended doesn't count: every lost game ends badly.
        var wasWorse = false
        /// ...and still won or drew.
        var saved = false

        init(_ game: SavedGame) {
            length = game.moveCount
            let playerIsWhite = game.playerIsWhite
            let grades = Dictionary(game.playerMoments.map { ($0.ply, $0.moveGrade) }, uniquingKeysWith: { a, _ in a })
            let chances = Dictionary(game.playerMoments.map { ($0.ply, $0.before) }, uniquingKeysWith: { a, _ in a })
            for (offset, san) in game.moves.enumerated() {
                let ply = offset + 1
                let fen = game.positions.indices.contains(offset) ? game.positions[offset] : ""
                let whiteMoved = Self.whiteToMove(fen) ?? (offset % 2 == 0)
                if ply <= 30, san.contains("x") { earlyCaptures += 1 }
                guard whiteMoved == playerIsWhite else { continue }
                moves += 1
                let number = (offset / 2) + 1
                if san.contains("+") || san.contains("#") { checks += 1 }
                if san.contains("x") { captures += 1 }
                if san.hasPrefix("O-O") {
                    if castledOn == nil { castledOn = number }
                    continue
                }
                if let rank = Self.targetRank(of: san) {
                    if playerIsWhite ? rank >= 5 : rank <= 4 { forward += 1 }
                }
                if san.hasPrefix("Q"), number < 6 { earlyQueen = true }
                // A sacrifice: still two points or more down after their answer and the player's
                // next move (so not a trade halfway through), and the move wasn't a mistake.
                // Only while the game was alive: more material going in a game already lost
                // isn't daring, and neither is handing some back when winning by a mile.
                let grade = grades[ply] ?? .good
                let sound: Set<MoveReview.Grade> = [.best, .excellent, .good]
                let stood = chances[ply] ?? 0
                if sound.contains(grade), stood > Self.clearlyWorse, stood < Self.wonByAMile,
                   game.positions.indices.contains(offset + 3),
                   let before = Self.balance(game.positions[offset], white: playerIsWhite),
                   let reply = Self.balance(game.positions[offset + 2], white: playerIsWhite),
                   let next = Self.balance(game.positions[offset + 3], white: playerIsWhite),
                   reply <= before - 2, next <= before - 2 {
                    sacrifices += 1
                }
            }
            wasWorse = game.playerMoments.contains { $0.after <= Self.clearlyWorse }
            saved = wasWorse && (game.result == .win || game.result == .draw)
        }

        /// Winning chances at which the player stands clearly worse: about two pawns down.
        static let clearlyWorse = -0.35
        /// Winning chances at which the game is as good as won: about seven pawns up.
        static let wonByAMile = 0.85

        static func whiteToMove(_ fen: String) -> Bool? {
            let fields = fen.split(separator: " ")
            guard fields.count >= 2 else { return nil }
            return fields[1] == "w"
        }

        /// The rank a move lands on, 1 to 8, from its standard notation.
        static func targetRank(of san: String) -> Int? {
            var text = san
            while let last = text.last, "+#!?".contains(last) { text.removeLast() }
            if let equals = text.firstIndex(of: "=") { text = String(text[..<equals]) }
            guard let last = text.last, let rank = Int(String(last)), (1...8).contains(rank) else { return nil }
            return rank
        }

        /// Material for one side minus the other's, in pawns, from a FEN.
        static func balance(_ fen: String, white: Bool) -> Int? {
            guard let board = fen.split(separator: " ").first, !board.isEmpty else { return nil }
            var total = 0
            for char in board {
                let value: Int
                switch char.lowercased() {
                case "p": value = 1
                case "n", "b": value = 3
                case "r": value = 5
                case "q": value = 9
                default: continue
                }
                total += char.isUppercase == white ? value : -value
            }
            return total
        }
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    /// The habits of many games, added up.
    struct HabitSums: Equatable {
        var games = 0
        var moves = 0
        /// Checks and captures.
        var sharp = 0
        var forward = 0
        /// Games castled after move 12, or never.
        var late = 0
        /// Sacrifices, at most two counted in a game.
        var sacrifices = 0
        var earlyQueens = 0
        var length = 0
        var earlyCaptures = 0
        var worse = 0
        var saved = 0

        init() {}

        init(_ games: [GameHabits]) {
            for game in games { add(game) }
        }

        mutating func add(_ game: GameHabits) {
            games += 1
            moves += game.moves
            sharp += game.checks + game.captures
            forward += game.forward
            if (game.castledOn ?? 99) > 12, game.length >= 15 { late += 1 }
            sacrifices += min(game.sacrifices, 2)
            if game.earlyQueen { earlyQueens += 1 }
            length += game.length
            earlyCaptures += game.earlyCaptures
            if game.wasWorse { worse += 1 }
            if game.saved { saved += 1 }
        }

        /// Of the games the player stood clearly worse in, the share they still won or drew.
        /// Nil until there are a few such games.
        var comebacks: Double? {
            worse >= ChessDNA.gamesForComebacks ? Double(saved) / Double(worse) : nil
        }
    }

    /// The four habits, each placed next to real players. `endgames` is the Endgames score
    /// from the recent games.
    static func traits(_ sums: HabitSums, endgames: Double?) -> [Trait] {
        guard sums.games >= gamesForStyle else {
            return Trait.Kind.allCases.map { Trait(kind: $0, standing: nil) }
        }
        let games = Double(sums.games)
        let moves = Double(max(1, sums.moves))
        // Checks and captures, and at half weight moves into their half, as a share of the
        // player's moves.
        let aggression = (Double(sums.sharp) + Double(sums.forward) * 0.5) / moves
        let risk = Double(sums.late) / games * 0.5 + Double(sums.sacrifices) / games * 0.45
            + Double(sums.earlyQueens) / games * 0.25
        let length = Double(sums.length) / games
        let early = Double(sums.earlyCaptures) / games
        let patience = clamp((length - 22) / 40) * 0.65 + clamp(1 - early / 14) * 0.35
        return [
            Trait(kind: .aggression, standing: RealPlayers.aggression.standing(of: aggression)),
            Trait(kind: .risk, standing: RealPlayers.risk.standing(of: risk)),
            Trait(kind: .patience, standing: RealPlayers.patience.standing(of: patience)),
            Trait(kind: .endgames, standing: endgames.map { RealPlayers.area(.endgames).standing(of: $0) }),
        ]
    }

    // MARK: The style

    /// How far each style's habits stand out, 0 to 1: 0.5 is the typical player. A style whose
    /// habit can't be judged yet (no endgames played, never clearly worse) has no score.
    static func styleScores(traits: [Trait], comebacks: Double?) -> [Style: Double] {
        func place(_ kind: Trait.Kind) -> Double? { traits.first { $0.kind == kind }?.value }
        guard let aggression = place(.aggression), let risk = place(.risk), let patience = place(.patience) else { return [:] }
        var scores: [Style: Double] = [
            .attacker: (aggression + risk) / 2,
            .tactician: (aggression + (1 - risk)) / 2,
            .builder: ((1 - aggression) + (1 - risk)) / 2,
        ]
        if let endgames = place(.endgames) {
            scores[.grinder] = (patience + endgames) / 2
        }
        if let comebacks {
            scores[.counterpuncher] = (RealPlayers.comebacks.standing(of: comebacks).place + (1 - aggression)) / 2
        }
        return scores
    }

    /// The style to show: the one whose habits stand out most, once they stand out enough to
    /// name. A style already named stays until another clearly passes it, so one odd game
    /// doesn't rename the player.
    static func style(scores: [Style: Double], current: Style?) -> Style {
        // Ties go to the earlier one.
        let order: [Style] = [.attacker, .tactician, .counterpuncher, .grinder, .builder]
        var best = Style.allRounder
        var top = -1.0
        for style in order {
            if let score = scores[style], score > top {
                best = style
                top = score
            }
        }
        let named: Style = top >= styleFloor ? best : .allRounder
        guard let current, current != named else { return named }
        if named == .allRounder {
            // Nothing stands out now: the old name stays while its own habits are still close.
            return (scores[current] ?? 0) >= styleFloor - styleMargin ? current : .allRounder
        }
        let held = current == .allRounder ? styleFloor : (scores[current] ?? styleFloor)
        return top >= held + styleMargin ? named : current
    }

    /// The habits and the style, read the way they grew: game by game from the oldest, so the
    /// style named today is the one the player has held until their games really changed.
    /// Both lists run newest first, one entry a game; a game too short to read has no habits.
    static func reading(habits: [GameHabits?], tallies: [CoachReport.Tally]) -> (traits: [Trait], style: Style?) {
        var window: [GameHabits] = []
        var style: Style?
        var traits = Self.traits(HabitSums(), endgames: nil)
        let oldestFirst = Array(tallies.reversed())
        for (index, game) in habits.reversed().enumerated() {
            if let game {
                window.append(game)
                if window.count > habitWindow { window.removeFirst() }
            }
            guard window.count >= gamesForStyle, oldestFirst.indices.contains(index) else { continue }
            let sums = HabitSums(window)
            // The Endgames score as the report had it then: from the newest games of that day.
            let recent = oldestFirst[max(0, index + 1 - CoachReport.gameLimit)...index]
            traits = Self.traits(sums, endgames: CoachReport.score(for: .endgames, in: recent).value)
            style = Self.style(scores: styleScores(traits: traits, comebacks: sums.comebacks), current: style)
        }
        return (traits, style)
    }

    // MARK: Strengths

    /// What the player is good at, the best proof first: patterns they find more often than
    /// real players do, an opening that keeps scoring, areas where they sit ahead of most
    /// players, and a puzzle theme well above their own average. Read from the same recent
    /// games as the report.
    static func strengths(games: [SavedGame], report: CoachReport, puzzleStats: [String: ThemeRecord],
                          index: OpeningIndex) -> [Strength] {
        let recent = games.prefix(CoachReport.gameLimit)
        var list: [Strength] = []

        // Patterns: how often the player plays one when it is on the board.
        var found: [CoachMoment.Kind: [Sighting]] = [:]
        for game in recent {
            for moment in game.playerMoments where [.best, .excellent, .checkmate].contains(moment.moveGrade) {
                if let kind = MomentFinder.find(in: game.review(of: moment))?.kind, kind.isPraise {
                    found[kind, default: []].append(Sighting(game: game.id, ply: moment.ply))
                }
            }
        }
        struct Pattern {
            let found, missed: CoachMoment.Kind
            let rate: RealPlayers.FindRate
            let title, symbol, theme, did, usually: String
        }
        let patterns = [
            Pattern(found: .foundFork, missed: .missedFork, rate: RealPlayers.forks,
                    title: "Forks", symbol: "arrow.triangle.branch", theme: "fork", did: "found", usually: "find"),
            Pattern(found: .foundFreePiece, missed: .missedFreePiece, rate: RealPlayers.freePieces,
                    title: "Free pieces", symbol: "gift.fill", theme: "hangingPiece", did: "took", usually: "take"),
            Pattern(found: .foundMate, missed: .missedMate, rate: RealPlayers.mates,
                    title: "Finishing with mate", symbol: "crown.fill", theme: "mateIn2", did: "finished", usually: "finish"),
        ]
        var leads: [(lead: Double, strength: Strength)] = []
        for pattern in patterns {
            let sightings = found[pattern.found] ?? []
            let chances = sightings.count + (report.missed[pattern.missed] ?? 0)
            guard chances >= chancesToCount else { continue }
            let lead = pattern.rate.lead(of: Double(sightings.count) / Double(chances))
            guard lead >= clearLead else { continue }
            let usual = Int((pattern.rate.typical * Double(chances)).rounded())
            var detail = "You \(pattern.did) \(sightings.count) of \(chances)."
            if usual < sightings.count { detail += " Most players \(pattern.usually) \(usual)." }
            leads.append((lead, Strength(title: pattern.title, detail: detail, symbol: pattern.symbol,
                                         theme: pattern.theme, sightings: sightings)))
        }
        list += leads.sorted { $0.lead > $1.lead }.map { $0.strength }

        // An opening that keeps scoring.
        if let opening = bestOpening(in: Array(recent), index: index) {
            list.append(opening)
        }

        // Areas where the player sits ahead of most players. Not one already said as a pattern.
        let weak = Set(report.weakSpots.map(\.area))
        let order = CoachReport.Area.allCases
        let ahead = report.scores
            .filter { $0.standing?.isAhead == true && !weak.contains($0.area) }
            .sorted { a, b in
                let pa = a.standing?.below ?? 0, pb = b.standing?.below ?? 0
                if pa != pb { return pa > pb }
                return (order.firstIndex(of: a.area) ?? 0) < (order.firstIndex(of: b.area) ?? 0)
            }
        for score in ahead {
            let theme = areaTheme(score.area)
            guard let standing = score.standing, !list.contains(where: { $0.theme == theme }) else { continue }
            if score.area == .tactics, list.contains(where: { $0.theme == "hangingPiece" }) { continue }
            list.append(Strength(title: areaStrength(score.area), detail: "\(standing.words) players.",
                                 symbol: score.area.symbol, theme: theme))
        }

        // A puzzle theme well above the player's own average: the last word, since it is
        // measured against the player and not against anyone else. Only themes that name a skill:
        // where a puzzle came from isn't one, and a tag the picker doesn't know has no name to show.
        let allAttempts = puzzleStats.values.reduce(0) { $0 + $1.attempts }
        let allClean = puzzleStats.values.reduce(0) { $0 + $1.clean }
        let overall = allAttempts == 0 ? 0 : Double(allClean) / Double(allAttempts)
        let top = puzzleStats
            .filter { $0.value.attempts >= puzzlesToCount && $0.value.accuracy >= max(0.7, overall + 0.12)
                && !PuzzleTheme.named($0.key).id.isEmpty && !notSkills.contains($0.key) }
            .max { a, b in a.value.accuracy != b.value.accuracy ? a.value.accuracy < b.value.accuracy : a.key > b.key }
        if let top, !list.contains(where: { $0.theme == top.key }) {
            let name = PuzzleTheme.named(top.key)
            let percent = Int((top.value.accuracy * 100).rounded())
            // A pattern keeps its own title: "Forks", not the picker's "Fork".
            let pattern = patterns.first { $0.theme == top.key }
            list.append(Strength(title: pattern?.title ?? name.name,
                                 detail: "You solve \(percent)% of \(name.name.lowercased()) puzzles clean, well above your average.",
                                 symbol: pattern?.symbol ?? name.symbol, theme: name.id))
        }
        return list
    }

    /// The opening that has gone best in these games, with one color: three games or more,
    /// and most of the points.
    static func bestOpening(in games: [SavedGame], index: OpeningIndex) -> Strength? {
        struct Tally { var wins = 0, draws = 0, losses = 0, games: [UUID] = [] }
        var tallies: [String: Tally] = [:]
        for game in games where game.result != .unfinished {
            guard let line = index.opening(of: game.positions) else { continue }
            let key = "\(line.family) as \(game.playerIsWhite ? "White" : "Black")"
            var tally = tallies[key] ?? Tally()
            switch game.result {
            case .win: tally.wins += 1
            case .draw: tally.draws += 1
            case .loss: tally.losses += 1
            case .unfinished: break
            }
            tally.games.append(game.id)
            tallies[key] = tally
        }
        func score(_ tally: Tally) -> Double {
            (Double(tally.wins) + Double(tally.draws) / 2) / Double(max(1, tally.games.count))
        }
        let best = tallies
            .filter { $0.value.games.count >= 3 && score($0.value) >= 0.6 }
            .max { a, b in
                if score(a.value) != score(b.value) { return score(a.value) < score(b.value) }
                if a.value.games.count != b.value.games.count { return a.value.games.count < b.value.games.count }
                return a.key > b.key
            }
        guard let best else { return nil }
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        var parts = [count(best.value.wins, "win", "wins")]
        if best.value.draws > 0 { parts.append(count(best.value.draws, "draw", "draws")) }
        parts.append(best.value.losses == 0 ? "no losses" : count(best.value.losses, "loss", "losses"))
        return Strength(title: best.key, detail: parts.joined(separator: ", ") + ".", symbol: "book.closed.fill",
                        sightings: best.value.games.map { Sighting(game: $0, ply: 0) })
    }

    /// Puzzle tags that say where a puzzle came from, not what it trains.
    static let notSkills: Set<String> = ["masterVsMaster"]

    static func areaTheme(_ area: CoachReport.Area) -> String {
        switch area {
        case .safety: return "defensiveMove"
        case .tactics: return "fork"
        case .checkmates: return "mateIn2"
        case .openings: return "opening"
        case .endgames: return "endgame"
        case .calculation: return "veryLong"
        }
    }

    static func areaStrength(_ area: CoachReport.Area) -> String {
        switch area {
        case .safety: return "Keeping pieces safe"
        case .tactics: return "Tactics"
        case .checkmates: return "Checkmates"
        case .openings: return "Openings"
        case .endgames: return "Endgames"
        case .calculation: return "Middlegame decisions"
        }
    }

    // MARK: Openings

    static func openings(games: [SavedGame], index: OpeningIndex) -> [OpeningRecord] {
        struct Tally { var wins = 0, draws = 0, losses = 0, accuracy: [Int] = [], lines: [OpeningLine: Int] = [:] }
        var tallies: [String: Tally] = [:]
        for game in games where game.result != .unfinished {
            guard let line = index.opening(of: game.positions) else { continue }
            let key = line.family + (game.playerIsWhite ? "|w" : "|b")
            var tally = tallies[key] ?? Tally()
            switch game.result {
            case .win: tally.wins += 1
            case .draw: tally.draws += 1
            case .loss: tally.losses += 1
            case .unfinished: break
            }
            if let accuracy = game.accuracy { tally.accuracy.append(accuracy) }
            tally.lines[line, default: 0] += 1
            tallies[key] = tally
        }
        let records = tallies.compactMap { key, tally -> OpeningRecord? in
            let common = tally.lines.max { a, b in
                a.value != b.value ? a.value < b.value : a.key.moves.count > b.key.moves.count
            }
            guard let line = common?.key else { return nil }
            return OpeningRecord(
                family: line.family, playerIsWhite: key.hasSuffix("|w"), line: line,
                wins: tally.wins, draws: tally.draws, losses: tally.losses,
                accuracy: tally.accuracy.isEmpty ? nil : tally.accuracy.reduce(0, +) / tally.accuracy.count)
        }
        let sorted = records.sorted { a, b in
            if a.games != b.games { return a.games > b.games }
            if a.score != b.score { return a.score > b.score }
            return a.family < b.family
        }
        return Array(sorted.filter(\.playerIsWhite).prefix(3)) + Array(sorted.filter { !$0.playerIsWhite }.prefix(3))
    }

    /// One opening for each color: the player's own when it scores well, otherwise one that
    /// fits their style (unless that's one going badly for them).
    static func picks(style: Style?, openings: [OpeningRecord], index: OpeningIndex) -> [OpeningPick] {
        guard let style else { return [] }
        var picks: [OpeningPick] = []
        for white in [true, false] {
            let mine = openings.filter { $0.playerIsWhite == white }
            if let strong = mine.first(where: { $0.games >= 3 && $0.score >= 0.6 }) {
                let percent = Int((strong.score * 100).rounded())
                picks.append(OpeningPick(line: strong.line, playerIsWhite: white,
                                         reason: "It's yours: \(percent)% of the points in \(strong.games) games. Learn its main lines so it keeps working.",
                                         isTheirs: true))
                continue
            }
            let name = white ? style.openings.white : style.openings.black
            guard let line = index.line(named: name) else { continue }
            if let record = mine.first(where: { $0.family == line.family }), record.games >= 3, record.score < 0.4 {
                continue
            }
            picks.append(OpeningPick(line: line, playerIsWhite: white,
                                     reason: "Made for \(style.title.lowercased())s: \(style.openingReason).",
                                     isTheirs: false))
        }
        return picks
    }

    // MARK: Growth

    static func trends(games: [SavedGame]) -> [Trend] {
        let graded = games.filter { $0.playerMoments.count >= movesToCount }
        let window = min(trendWindow, graded.count / 2)
        guard window >= minimumTrendWindow else { return [] }
        let now = Array(graded.prefix(window))
        let before = Array(graded.dropFirst(window).prefix(window))
        func perGame(_ games: [SavedGame]) -> [CoachReport.Area: Double] {
            var counts: [CoachReport.Area: Int] = [:]
            for game in games {
                for moment in game.playerMoments where CoachReport.weight(of: moment.moveGrade) != nil {
                    let kind = MomentFinder.find(in: moment.review)?.kind
                    let area = CoachReport.area(for: kind?.isPraise == true ? nil : kind, phase: .of(moment))
                    counts[area, default: 0] += 1
                }
            }
            return counts.mapValues { Double($0) / Double(games.count) }
        }
        let a = perGame(before), b = perGame(now)
        return CoachReport.Area.allCases.compactMap { area in
            let then = a[area] ?? 0, now = b[area] ?? 0
            guard then > 0 || now > 0 else { return nil }
            return Trend(area: area, before: then, now: now)
        }
    }

    static func accuracyTrend(games: [SavedGame]) -> AccuracyTrend? {
        let graded = games.compactMap(\.accuracy)
        let window = min(trendWindow, graded.count / 2)
        guard window >= minimumTrendWindow else { return nil }
        let now = graded.prefix(window), before = graded.dropFirst(window).prefix(window)
        return AccuracyTrend(before: before.reduce(0, +) / before.count, now: now.reduce(0, +) / now.count)
    }
}

// MARK: What the coach learned from a game

extension ChessDNA {
    /// One line for the end of a game: the newest thing this game taught the coach about
    /// the player. Nil when the game changed nothing worth a word.
    static func learned(before: ChessDNA, after: ChessDNA, game: SavedGame,
                        index: OpeningIndex = .shared) -> String? {
        if let style = after.style, before.style == nil {
            return "I've seen enough to read your style: you play like \(article(style.title)) \(style.title). Your Chess DNA is in Learn."
        }
        if let style = after.style, let old = before.style, style != old {
            return "Your style is shifting: from \(old.title) to \(style.title)."
        }
        if let old = before.leak, after.gamesRead > before.gamesRead {
            if after.leak == nil {
                return "\(old.headline) isn't costing you games anymore. Nice work."
            }
            if let new = after.leak, new.headline != old.headline {
                return "\(old.headline) is under control. Next to work on: \(new.headline.lowercased())."
            }
        }
        if before.leak == nil, let new = after.leak, after.gamesRead > before.gamesRead {
            return "Something to work on: \(new.headline.lowercased()). Today's training aims at it."
        }
        if let improved = after.biggestImprovement, before.biggestImprovement?.area != improved.area {
            return "\(improved.area.title) is getting better: \(format(improved.before)) costly moves a game before, \(format(improved.now)) now."
        }
        if game.result != .unfinished, let line = index.opening(of: game.positions) {
            let record = after.openings.first { $0.family == line.family && $0.playerIsWhite == game.playerIsWhite }
            let color = game.playerIsWhite ? "White" : "Black"
            if let record, record.games >= 2 {
                return "You're \(record.tally) with the \(line.family) as \(color) now."
            }
            if record?.games == 1 || record == nil {
                return "First time I've seen you in the \(line.family) as \(color). I'll keep count."
            }
        }
        return nil
    }

    static func article(_ word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    /// "1.8", or "0" for nothing.
    static func format(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.1f", value)
    }
}
