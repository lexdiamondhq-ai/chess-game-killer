import Foundation

/// Your Chess DNA: what the coach has learned about how this player plays, rebuilt from
/// every saved game against the computer and every rated puzzle after each one. It names a
/// style from four habits, the player's best weapon and biggest leak, what they really
/// play in the opening and how it goes, one opening that suits them, and whether each area
/// is getting better. Pure data in, so it's easy to test, and it runs off the main thread.
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

    /// One of the four habits, from 0 to 1.
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
        }

        let kind: Kind
        /// Nil until there's enough to judge.
        let value: Double?

        var id: String { kind.rawValue }

        /// The nearer end's word, or "Balanced" in the middle.
        var word: String {
            guard let value else { return "Not enough yet" }
            if value >= 0.62 { return kind.ends.high }
            if value <= 0.38 { return kind.ends.low }
            return "Balanced"
        }
    }

    // MARK: Weapon

    /// The player's best weapon, with the evidence for it.
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
    let puzzlesRead: Int
    /// Nil until enough games are read.
    let style: Style?
    let traits: [Trait]
    /// The six areas and the one leak, from the recent games.
    let report: CoachReport
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
    var hasStyle: Bool { style != nil }

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

    /// Games read for the habits and the openings: everything the vault keeps.
    static let gameLimit = 150
    /// A game counts once the player made this many moves in it.
    static let movesToCount = 10
    /// Games needed before a style is named.
    static let gamesForStyle = 3
    /// Games in each window when comparing then and now.
    static let trendWindow = 10
    static let minimumTrendWindow = 4
    /// Puzzles in a theme before its record counts as evidence.
    static let puzzlesToCount = 8

    // MARK: Building it

    static func make(games: [SavedGame], puzzleStats: [String: ThemeRecord] = [:], puzzlesPlayed: Int = 0,
                     index: OpeningIndex = .shared) -> ChessDNA {
        let computer = games.filter { $0.level != nil }.sorted { $0.date > $1.date }.prefix(gameLimit)
        let counted = computer.filter { $0.playerMoments.count >= movesToCount || $0.moves.count >= 2 * movesToCount }
        let habits = counted.map(GameHabits.init)
        let report = CoachReport.make(games: Array(computer))

        let traits = Self.traits(habits: habits, report: report)
        let style = habits.count >= gamesForStyle ? Self.style(traits: traits, habits: habits) : nil
        let openings = Self.openings(games: Array(computer), index: index)
        return ChessDNA(
            gamesRead: computer.count,
            puzzlesRead: puzzlesPlayed,
            style: style,
            traits: traits,
            report: report,
            weapon: weapon(games: Array(computer), report: report, puzzleStats: puzzleStats),
            openings: openings,
            picks: picks(style: style, openings: openings, index: index),
            trends: trends(games: Array(computer)),
            accuracyTrend: accuracyTrend(games: Array(computer))
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
        /// Material given up for at least a move, without the engine calling it a mistake.
        var sacrifices = 0
        /// The queen out before move 6.
        var earlyQueen = false
        /// Captures by either side in the first 15 moves each.
        var earlyCaptures = 0
        /// The whole game's length, in moves each.
        var length = 0
        /// The player stood clearly worse at some point...
        var wasWorse = false
        /// ...and still won or drew.
        var saved = false

        init(_ game: SavedGame) {
            length = game.moveCount
            let playerIsWhite = game.playerIsWhite
            let grades = Dictionary(game.playerMoments.map { ($0.ply, $0.moveGrade) }, uniquingKeysWith: { a, _ in a })
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
                let grade = grades[ply] ?? .good
                let sound: Set<MoveReview.Grade> = [.best, .excellent, .good]
                if sound.contains(grade), game.positions.indices.contains(offset + 3),
                   let before = Self.balance(game.positions[offset], white: playerIsWhite),
                   let reply = Self.balance(game.positions[offset + 2], white: playerIsWhite),
                   let next = Self.balance(game.positions[offset + 3], white: playerIsWhite),
                   reply <= before - 2, next <= before - 2 {
                    sacrifices += 1
                }
            }
            let line = game.lifeline
            wasWorse = line.contains { $0.value <= -0.35 }
            saved = wasWorse && (game.result == .win || game.result == .draw)
        }

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

    static func traits(habits: [GameHabits], report: CoachReport) -> [Trait] {
        guard habits.count >= gamesForStyle else {
            return Trait.Kind.allCases.map { Trait(kind: $0, value: nil) }
        }
        let games = Double(habits.count)
        let moves = Double(max(1, habits.reduce(0) { $0 + $1.moves }))
        let sharp = Double(habits.reduce(0) { $0 + $1.checks + $1.captures })
        let forward = Double(habits.reduce(0) { $0 + $1.forward })
        // Checks and captures run about a quarter of a club player's moves, moves into
        // their half about a third: both at once reads as balanced.
        let aggression = clamp(((sharp + forward * 0.5) / moves - 0.22) / 0.36)

        let late = Double(habits.filter { ($0.castledOn ?? 99) > 12 && $0.length >= 15 }.count) / games
        let sacrifices = habits.reduce(0.0) { $0 + min(Double($1.sacrifices), 2) } / games
        let queen = Double(habits.filter(\.earlyQueen).count) / games
        let risk = clamp(late * 0.5 + sacrifices * 0.45 + queen * 0.25)

        let length = habits.reduce(0.0) { $0 + Double($1.length) } / games
        let early = habits.reduce(0.0) { $0 + Double($1.earlyCaptures) } / games
        let patience = clamp(clamp((length - 22) / 40) * 0.65 + clamp(1 - early / 14) * 0.35)

        let endgame = report.scores.first { $0.area == .endgames }?.value
        return [
            Trait(kind: .aggression, value: aggression),
            Trait(kind: .risk, value: risk),
            Trait(kind: .patience, value: patience),
            Trait(kind: .endgames, value: endgame),
        ]
    }

    static func style(traits: [Trait], habits: [GameHabits]) -> Style {
        func value(_ kind: Trait.Kind) -> Double { traits.first { $0.kind == kind }?.value ?? 0.5 }
        let aggression = value(.aggression), risk = value(.risk), patience = value(.patience), endgame = value(.endgames)
        let worse = habits.filter(\.wasWorse).count
        let saved = habits.filter(\.saved).count
        if aggression >= 0.6, risk >= 0.5 { return .attacker }
        if aggression >= 0.6 { return .tactician }
        if worse >= 2, Double(saved) / Double(worse) >= 0.5 { return .counterpuncher }
        if patience >= 0.6, endgame >= 0.6 { return .grinder }
        if aggression < 0.45, risk < 0.4 { return .builder }
        return .allRounder
    }

    // MARK: The weapon

    static func weapon(games: [SavedGame], report: CoachReport, puzzleStats: [String: ThemeRecord]) -> Weapon? {
        // Patterns the player found in their games.
        var found: [CoachMoment.Kind: Int] = [:]
        for game in games.prefix(CoachReport.gameLimit * 2) {
            for moment in game.playerMoments where [.best, .excellent, .checkmate].contains(moment.moveGrade) {
                if let kind = MomentFinder.find(in: moment.review)?.kind, kind.isPraise, kind != .castled, kind != .fixedIt {
                    found[kind, default: 0] += 1
                }
            }
        }
        func puzzles(_ theme: String) -> ThemeRecord? {
            guard let record = puzzleStats[theme], record.attempts >= puzzlesToCount else { return nil }
            return record
        }
        func percent(_ record: ThemeRecord) -> Int { Int((record.accuracy * 100).rounded()) }
        let allAttempts = puzzleStats.values.reduce(0) { $0 + $1.attempts }
        let allClean = puzzleStats.values.reduce(0) { $0 + $1.clean }
        let overall = allAttempts == 0 ? 0 : Double(allClean) / Double(allAttempts)

        struct Candidate { let weight: Double; let weapon: Weapon }
        struct Pattern { let kind: CoachMoment.Kind; let title, symbol, theme, found, puzzles: String }
        var candidates: [Candidate] = []
        let patterns = [
            Pattern(kind: .foundFork, title: "Forks", symbol: "arrow.triangle.branch", theme: "fork",
                    found: "forks found", puzzles: "fork"),
            Pattern(kind: .foundFreePiece, title: "Punishing loose pieces", symbol: "gift.fill", theme: "hangingPiece",
                    found: "free pieces taken", puzzles: "free-piece"),
            Pattern(kind: .foundMate, title: "Finishing the game", symbol: "crown.fill", theme: "mateIn2",
                    found: "mates found", puzzles: "mate"),
        ]
        for pattern in patterns {
            let count = found[pattern.kind] ?? 0
            let record = puzzles(pattern.theme)
            let goodAtPuzzles = record.map { $0.accuracy >= max(0.7, overall + 0.08) } ?? false
            guard count >= 2 || goodAtPuzzles else { continue }
            var parts: [String] = []
            if count >= 2 { parts.append("\(count) \(pattern.found) in your games") }
            if let record, goodAtPuzzles { parts.append("\(percent(record))% of \(pattern.puzzles) puzzles solved clean") }
            let joined: String = parts.joined(separator: " and ")
            let detail: String = joined.prefix(1).uppercased() + String(joined.dropFirst()) + "."
            let weight: Double = Double(count) + (record?.accuracy ?? 0) * 4
            candidates.append(Candidate(weight: weight, weapon: Weapon(title: pattern.title, detail: detail,
                                                                       symbol: pattern.symbol, theme: pattern.theme)))
        }
        // An area of the games that's strong.
        if let best = report.scores.filter({ ($0.value ?? 0) >= 0.85 && $0.area != report.leak?.area })
            .max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
            let theme = areaTheme(best.area)
            let detail = best.mistakes == 0
                ? "No costly moves in \(best.area.title.lowercased()) across \(best.games == 1 ? "a game" : "\(best.games) games")."
                : "Only \(best.mistakes) costly \(best.mistakes == 1 ? "move" : "moves") in \(best.area.title.lowercased()) across \(best.games) games."
            // Patterns and puzzles are the sharper evidence: a clean area is the fallback.
            candidates.append(Candidate(weight: 1.5 + (best.value ?? 0),
                                        weapon: Weapon(title: areaStrength(best.area), detail: detail,
                                                       symbol: best.area.symbol, theme: theme)))
        }
        // A puzzle theme well above the player's own average.
        if let top = puzzleStats.filter({ $0.value.attempts >= puzzlesToCount && $0.value.accuracy >= max(0.7, overall + 0.12) })
            .max(by: { $0.value.accuracy < $1.value.accuracy }),
           !candidates.contains(where: { $0.weapon.theme == top.key }) {
            let name = PuzzleTheme.named(top.key)
            if !name.id.isEmpty {
                candidates.append(Candidate(weight: 2 + top.value.accuracy * 2,
                                            weapon: Weapon(title: name.name,
                                                           detail: "You solve \(percent(top.value))% of \(name.name.lowercased()) puzzles clean, well above your average.",
                                                           symbol: name.symbol, theme: name.id)))
            }
        }
        return candidates.max { $0.weight < $1.weight }?.weapon
    }

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
            return "I've seen enough to read your style: you play like \(article(style.title)) \(style.title). Your Chess DNA is in Train."
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
