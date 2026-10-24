import ChessKit
import Foundation
import Observation

extension Piece.Kind {
    /// The piece's name in a sentence, like "queen".
    var word: String {
        switch self {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }
}

/// One of the sixteen pieces in the player's army, named by where it starts.
/// The same piece whether the player takes Gold/White or Violet/Black.
enum ArmySlot: String, CaseIterable, Codable, Identifiable {
    case queensRook, queensKnight, queensBishop, queen, king, kingsBishop, kingsKnight, kingsRook
    case aPawn, bPawn, cPawn, dPawn, ePawn, fPawn, gPawn, hPawn

    var id: Self { self }

    /// Column from a (0) to h (7).
    var file: Int {
        let all = Self.allCases
        return all.firstIndex(of: self)! % 8
    }

    var isPawn: Bool { Self.allCases.firstIndex(of: self)! >= 8 }

    var kind: Piece.Kind {
        if isPawn { return .pawn }
        switch self {
        case .queensRook, .kingsRook: return .rook
        case .queensKnight, .kingsKnight: return .knight
        case .queensBishop, .kingsBishop: return .bishop
        case .queen: return .queen
        default: return .king
        }
    }

    /// The square this piece starts on for `color`.
    func square(for color: Piece.Color) -> Square {
        let rank: Int
        switch (color, isPawn) {
        case (.white, false): rank = 0
        case (.white, true): rank = 1
        case (.black, true): rank = 6
        case (.black, false): rank = 7
        }
        return Square(file: file, rank: rank)
    }

    /// The slot of the `color` piece that starts on `square`, if one does.
    init?(start square: Square, color: Piece.Color) {
        guard let slot = Self.allCases.first(where: { $0.square(for: color) == square }) else { return nil }
        self = slot
    }

    var title: String {
        switch self {
        case .queensRook: return "Queenside Rook"
        case .queensKnight: return "Queenside Knight"
        case .queensBishop: return "Queenside Bishop"
        case .queen: return "Queen"
        case .king: return "King"
        case .kingsBishop: return "Kingside Bishop"
        case .kingsKnight: return "Kingside Knight"
        case .kingsRook: return "Kingside Rook"
        default: return "\(["a", "b", "c", "d", "e", "f", "g", "h"][file])-Pawn"
        }
    }
}

/// How far a piece has come. Each rank adds to how it looks on the board.
enum ArmyRank: Int, CaseIterable, Comparable, Codable {
    /// Plain.
    case recruit
    /// Earns a name and a soft glow.
    case veteran
    /// Earns a scar.
    case elite
    /// A golden glow that breathes.
    case legend

    var title: String {
        switch self {
        case .recruit: return "Recruit"
        case .veteran: return "Veteran"
        case .elite: return "Elite"
        case .legend: return "Legend"
        }
    }

    /// Experience needed to reach this rank.
    var threshold: Int {
        switch self {
        case .recruit: return 0
        case .veteran: return 25
        case .elite: return 100
        case .legend: return 300
        }
    }

    var reward: String {
        switch self {
        case .recruit: return "Every piece starts here."
        case .veteran: return "Earns a name and a soft glow."
        case .elite: return "Earns a battle scar."
        case .legend: return "Glows gold."
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func forXP(_ xp: Int) -> ArmyRank {
        allCases.last { xp >= $0.threshold } ?? .recruit
    }

    var next: ArmyRank? { ArmyRank(rawValue: rawValue + 1) }
}

/// One piece's record across every game.
struct PieceRecord: Codable, Equatable {
    var name: String?
    var games = 0
    var wins = 0
    /// Wins where this piece was still standing at the end.
    var survivedWins = 0
    var captures = 0
    var captureValue = 0
    var mates = 0
    var promotions = 0
    var falls = 0
    /// Experience earned so far. Each game adds its own share, scaled by how
    /// strong the rival was and cut in half when Undo or a played hint helped.
    var xp = 0
    /// Games where this piece was named Piece of the Match.
    var honors = 0
    /// How many times each rival has taken this piece, by level.
    var takenBy: [Int: Int] = [:]
    /// Rivals this piece has had its revenge on, by level.
    var revenge: Set<Int> = []
    /// Rivals it beat while it was on the line, by level: a trophy from each.
    var trophies: Set<Int> = []
    /// Times it was taken prisoner while on the line and won back.
    var escapes = 0

    var rank: ArmyRank { .forXP(xp) }

    init() {}

    /// The rival that has taken this piece most often (at least `ArmyStore.grudgeAt` times), and how often.
    var nemesis: (level: MatchController.Level, times: Int)? {
        guard let top = takenBy.filter({ $0.value >= ArmyStore.grudgeAt })
            .max(by: { ($0.value, $0.key) < ($1.value, $1.key) }),
              let level = MatchController.Level(rawValue: top.key) else { return nil }
        return (level, top.value)
    }

    /// Experience for one game: a little for playing, more for winning, taking
    /// material, promoting and delivering mate.
    static func baseXP(for game: PieceGameStats, won: Bool?, survived: Bool) -> Int {
        var xp = 1
        if won == true { xp += 3 + (survived ? 2 : 0) }
        xp += game.captureValue * 2
        if game.promoted { xp += 10 }
        if game.gaveMate { xp += 20 }
        return xp
    }

    private enum CodingKeys: String, CodingKey {
        case name, games, wins, survivedWins, captures, captureValue, mates, promotions, falls, xp
        case honors, takenBy, revenge, trophies, escapes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        survivedWins = try c.decodeIfPresent(Int.self, forKey: .survivedWins) ?? 0
        captures = try c.decodeIfPresent(Int.self, forKey: .captures) ?? 0
        captureValue = try c.decodeIfPresent(Int.self, forKey: .captureValue) ?? 0
        mates = try c.decodeIfPresent(Int.self, forKey: .mates) ?? 0
        promotions = try c.decodeIfPresent(Int.self, forKey: .promotions) ?? 0
        falls = try c.decodeIfPresent(Int.self, forKey: .falls) ?? 0
        // Armies saved before experience was stored keep what they had earned.
        xp = try c.decodeIfPresent(Int.self, forKey: .xp)
            ?? games + wins * 3 + survivedWins * 2 + captureValue * 2 + promotions * 10 + mates * 20
        honors = try c.decodeIfPresent(Int.self, forKey: .honors) ?? 0
        takenBy = try c.decodeIfPresent([Int: Int].self, forKey: .takenBy) ?? [:]
        revenge = try c.decodeIfPresent(Set<Int>.self, forKey: .revenge) ?? []
        trophies = try c.decodeIfPresent(Set<Int>.self, forKey: .trophies) ?? []
        escapes = try c.decodeIfPresent(Int.self, forKey: .escapes) ?? 0
    }
}

/// How much a finished game is worth to the army, and who it was against.
struct GameStakes: Equatable {
    /// Stronger rivals are worth more.
    var multiplier: Double = 1
    /// Undo or a played hint helped this game, so it is worth half.
    var assisted = false
    /// The rival played, for grudges and revenge. Nil in tests that don't care.
    var level: MatchController.Level?
    /// The piece the player put on the line for this game, if any.
    var staked: ArmySlot?

    static let standard = GameStakes()

    init(multiplier: Double = 1, assisted: Bool = false) {
        self.multiplier = multiplier
        self.assisted = assisted
    }

    init(level: MatchController.Level, assisted: Bool, staked: ArmySlot? = nil) {
        self.init(multiplier: level.armyMultiplier, assisted: assisted)
        self.level = level
        self.staked = staked
    }

    func scale(_ xp: Int) -> Int {
        let scaled = Double(xp) * multiplier * (assisted ? 0.5 : 1)
        return max(1, Int(scaled.rounded()))
    }
}

extension MatchController.Level {
    /// How much a game against this rival is worth to the army.
    var armyMultiplier: Double {
        switch self {
        case .beginner: return 1
        case .casual: return 1.25
        case .club: return 1.5
        case .expert: return 2
        case .grandmaster: return 3
        }
    }
}

/// Something worth telling the player about a piece.
struct ArmyNews: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Reached a new rank.
        case promoted
        /// Beat a rival that kept taking it.
        case revenge(rival: String)
        /// Before a game: this rival has taken the piece this many times.
        case grudge(rival: String, times: Int)
        /// Before a game: the piece is on the line.
        case staked(rival: String)
        /// Won a game it was on the line for: double experience and a trophy.
        case wonStake(rival: String)
        /// Lost a game it was on the line for: the rival holds it.
        case captured(rival: String)
        /// A win against the rival holding it set it free.
        case rescued(rival: String)
    }

    let slot: ArmySlot
    let rank: ArmyRank
    /// The piece's name, or its title when it hasn't earned one.
    let name: String
    var kind: Kind = .promoted

    var id: String { "\(slot.rawValue)-\(label)" }

    /// The small line above the headline.
    var label: String {
        switch kind {
        case .promoted: return rank.title.uppercased()
        case .revenge: return "REVENGE"
        case .grudge: return "GRUDGE MATCH"
        case .staked: return "ON THE LINE"
        case .wonStake: return "TROPHY"
        case .captured: return "TAKEN PRISONER"
        case .rescued: return "RESCUED"
        }
    }

    var headline: String {
        switch kind {
        case .revenge(let rival):
            return "\(name) got its revenge on \(rival)"
        case .grudge(let rival, let times):
            return "\(rival) has taken \(name) \(Self.times(times))."
        case .staked(let rival):
            return "\(name) is on the line against \(rival)."
        case .wonStake(let rival):
            return "\(name) took \(rival)'s crown. Double XP."
        case .captured(let rival):
            return "\(rival) is holding \(name). Beat \(rival) to get it back."
        case .rescued(let rival):
            return "\(name) escaped from \(rival)."
        case .promoted:
            switch rank {
            case .veteran: return "Your \(slot.title.lowercased()) earned a name: \(name)"
            case .elite: return "\(name) earned a battle scar"
            case .legend: return "\(name) became a Legend"
            case .recruit: return name
            }
        }
    }

    /// Bigger news first: a Legend, then revenge, then the other ranks.
    fileprivate var priority: Int {
        switch kind {
        case .captured: return 40
        case .rescued: return 35
        case .wonStake: return 30
        case .revenge: return 25
        case .grudge, .staked: return 0
        case .promoted: return rank.rawValue * 10
        }
    }

    /// How many times, in words up to ten: "once", "twice", "three times", then "11 times".
    static func times(_ count: Int) -> String {
        let words = ["three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        switch count {
        case 1: return "once"
        case 2: return "twice"
        case 3...10: return "\(words[count - 3]) times"
        default: return "\(count) times"
        }
    }
}

/// The piece that did the most in one game, and what it did.
struct MatchHero: Equatable {
    let gameID: UUID
    let slot: ArmySlot
    /// Its name, or "Your kingside knight" when it hasn't earned one yet.
    let name: String
    /// What it did, like "Kestrel took Vector's queen."
    let line: String
    /// The bonus it earned for it, as this game counted: more against a stronger
    /// rival, half when the game had help.
    let xp: Int
}

/// The player's army: every piece's record, saved on this device.
/// Only games against the computer that start from the usual position count.
@MainActor
@Observable
final class ArmyStore {
    private(set) var army: Army
    /// The Piece of the Match of the last game recorded.
    private(set) var lastHero: MatchHero?

    /// A rival has a grudge with a piece once it has taken it this many times.
    nonisolated static let grudgeAt = 3
    /// Extra experience for the Piece of the Match, and for revenge.
    static let heroXP = 5
    static let revengeXP = 15

    struct Army: Codable, Equatable {
        var records: [ArmySlot: PieceRecord] = [:]
        var lastGameID: UUID?
        /// Pieces lost while on the line, and the rival (by level) holding each one.
        var captives: [ArmySlot: Int] = [:]

        init(records: [ArmySlot: PieceRecord] = [:], lastGameID: UUID? = nil, captives: [ArmySlot: Int] = [:]) {
            self.records = records
            self.lastGameID = lastGameID
            self.captives = captives
        }

        private enum CodingKeys: String, CodingKey { case records, lastGameID, captives }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            records = try c.decodeIfPresent([ArmySlot: PieceRecord].self, forKey: .records) ?? [:]
            lastGameID = try c.decodeIfPresent(UUID.self, forKey: .lastGameID)
            // Armies saved before pieces could be put on the line hold no prisoners.
            captives = try c.decodeIfPresent([ArmySlot: Int].self, forKey: .captives) ?? [:]
        }
    }

    private let fileURL: URL?

    init(army: Army = Army(), fileURL: URL? = nil) {
        self.army = army
        self.fileURL = fileURL
    }

    static func live() -> ArmyStore {
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("army.json")
        var army = Army()
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Army.self, from: data) {
            army = saved
        }
        return ArmyStore(army: army, fileURL: url)
    }

    // MARK: Reading

    func record(for slot: ArmySlot) -> PieceRecord {
        army.records[slot] ?? PieceRecord()
    }

    /// The piece's name, or "Your kingside knight" when it hasn't earned one
    /// ("your kingside knight" in the middle of a sentence).
    func displayName(of slot: ArmySlot, capitalized: Bool = true) -> String {
        record(for: slot).name ?? "\(capitalized ? "Your" : "your") \(slot.title.lowercased())"
    }

    /// The name of the player's piece that started on `start`, if it has earned one.
    func name(ofPieceFrom start: Square?, color: Piece.Color) -> String? {
        guard let start, let slot = ArmySlot(start: start, color: color) else { return nil }
        return record(for: slot).name
    }

    /// Every named piece by the square it starts on for `color`.
    func names(for color: Piece.Color) -> [Square: String] {
        var names: [Square: String] = [:]
        for slot in ArmySlot.allCases {
            if let name = record(for: slot).name { names[slot.square(for: color)] = name }
        }
        return names
    }

    var gamesPlayed: Int {
        army.records.values.map(\.games).max() ?? 0
    }

    /// The piece this rival has taken most often, for a "grudge match" banner as a game starts.
    func grudge(against level: MatchController.Level) -> ArmyNews? {
        let rival = level.rival.name
        let best = ArmySlot.allCases
            .map { ($0, record(for: $0).takenBy[level.rawValue] ?? 0) }
            .filter { $0.1 >= Self.grudgeAt && !record(for: $0.0).revenge.contains(level.rawValue) }
            .max { $0.1 < $1.1 }
        guard let best else { return nil }
        let (slot, times) = best
        // The name sits mid-sentence: "Spark has taken your queen three times."
        return ArmyNews(slot: slot, rank: record(for: slot).rank, name: displayName(of: slot, capitalized: false),
                        kind: .grudge(rival: rival, times: times))
    }

    // MARK: Changing

    /// Adds a finished game to every piece's record. `won` is nil for a draw.
    /// Returns what changed that is worth telling the player. A game is only counted once.
    @discardableResult
    func record(_ ledger: PieceLedger, playerColor: Piece.Color, won: Bool?,
                stakes: GameStakes = .standard) -> [ArmyNews] {
        guard army.lastGameID != ledger.gameID else { return [] }
        army.lastGameID = ledger.gameID
        let standing = Set(ledger.origins.values)
        let rival = stakes.level?.rival.name ?? "the computer"
        let heroSlot = Self.heroSlot(in: ledger, playerColor: playerColor)
        var news: [ArmyNews] = []

        // The stake as the game began: checked before a win can free a prisoner.
        let staked = stakes.level.flatMap { canStake(stakes.staked, against: $0) ? stakes.staked : nil }
        // A win against a rival frees the piece it holds, in time to earn from this game.
        if let level = stakes.level, won == true,
           let freed = army.captives.first(where: { $0.value == level.rawValue })?.key {
            army.captives[freed] = nil
            var record = record(for: freed)
            record.escapes += 1
            army.records[freed] = record
            news.append(ArmyNews(slot: freed, rank: record.rank, name: displayName(of: freed),
                                 kind: .rescued(rival: rival)))
        }

        for slot in ArmySlot.allCases {
            // A prisoner sits out: it earns nothing until it is won back.
            if army.captives[slot] != nil { continue }
            let start = slot.square(for: playerColor)
            let game = ledger.stats(forPieceStartingOn: start)
            var record = record(for: slot)
            let rankBefore = record.rank

            let survived = standing.contains(start)
            var earned = PieceRecord.baseXP(for: game, won: won, survived: survived)
            if slot == heroSlot {
                record.honors += 1
                earned += Self.heroXP
            }

            // Revenge: the piece a rival keeps taking wins a game against it and does damage.
            var tookRevenge = false
            if let level = stakes.level, won == true,
               (record.takenBy[level.rawValue] ?? 0) >= Self.grudgeAt,
               !record.revenge.contains(level.rawValue),
               game.captures > 0 || game.gaveMate {
                record.revenge.insert(level.rawValue)
                earned += Self.revengeXP
                tookRevenge = true
            }
            if let level = stakes.level, game.fell {
                record.takenBy[level.rawValue, default: 0] += 1
            }

            record.games += 1
            if won == true {
                record.wins += 1
                if survived { record.survivedWins += 1 }
            }
            let onTheLine = slot == staked
            record.xp += stakes.scale(earned) * (onTheLine && won == true ? 2 : 1)
            record.captures += game.captures
            record.captureValue += game.captureValue
            if game.gaveMate { record.mates += 1 }
            if game.promoted { record.promotions += 1 }
            if game.fell { record.falls += 1 }

            if record.rank >= .veteran, record.name == nil {
                record.name = freshName(for: slot)
            }
            army.records[slot] = record
            if record.rank > rankBefore, let name = record.name {
                news.append(ArmyNews(slot: slot, rank: record.rank, name: name))
            }
            if tookRevenge {
                news.append(ArmyNews(slot: slot, rank: record.rank, name: displayName(of: slot),
                                     kind: .revenge(rival: rival)))
            }
            if onTheLine, let level = stakes.level {
                if won == true {
                    record.trophies.insert(level.rawValue)
                    army.records[slot] = record
                    news.append(ArmyNews(slot: slot, rank: record.rank, name: displayName(of: slot),
                                         kind: .wonStake(rival: rival)))
                } else if won == false {
                    army.captives[slot] = level.rawValue
                    news.append(ArmyNews(slot: slot, rank: record.rank, name: displayName(of: slot),
                                         kind: .captured(rival: rival)))
                }
            }
        }

        lastHero = heroSlot.map { slot in
            let stats = ledger.stats(forPieceStartingOn: slot.square(for: playerColor))
            let name = displayName(of: slot)
            return MatchHero(gameID: ledger.gameID, slot: slot, name: name,
                             line: Self.heroLine(name: name, stats: stats, rival: rival),
                             xp: stakes.scale(Self.heroXP))
        }
        save()
        return news.sorted { $0.priority > $1.priority }
    }

    func rename(_ slot: ArmySlot, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var record = record(for: slot)
        record.name = String(trimmed.prefix(20))
        army.records[slot] = record
        if lastHero?.slot == slot, let hero = lastHero {
            lastHero = MatchHero(gameID: hero.gameID, slot: slot, name: record.name ?? hero.name,
                                 line: hero.line.replacingOccurrences(of: hero.name, with: record.name ?? hero.name),
                                 xp: hero.xp)
        }
        save()
    }

    func reset() {
        army = Army()
        lastHero = nil
        save()
    }

    // MARK: Piece of the Match

    /// The player's piece that did the most this game: mate, promotion and material
    /// taken count, the busiest piece breaks a tie. Nil when no piece did anything.
    nonisolated static func heroSlot(in ledger: PieceLedger, playerColor: Piece.Color) -> ArmySlot? {
        let scored = ArmySlot.allCases.map { slot -> (ArmySlot, Int, Int) in
            let game = ledger.stats(forPieceStartingOn: slot.square(for: playerColor))
            let score = game.captureValue * 2 + (game.promoted ? 10 : 0) + (game.gaveMate ? 20 : 0)
            return (slot, score, game.moves)
        }
        guard let best = scored.max(by: { ($0.1, $0.2) < ($1.1, $1.2) }), best.1 > 0 else { return nil }
        return best.0
    }

    /// What the Piece of the Match did, in one short line.
    nonisolated static func heroLine(name: String, stats: PieceGameStats, rival: String) -> String {
        if stats.gaveMate { return "\(name) delivered checkmate." }
        if stats.promoted { return "\(name) marched all the way and promoted." }
        let biggest = stats.taken.max { (PieceLedger.values[$0] ?? 0) < (PieceLedger.values[$1] ?? 0) } ?? .pawn
        let others = stats.taken.count - 1
        let more = others > 0 ? " and \(others) more" : ""
        return "\(name) took \(rival)'s \(biggest.word)\(more)."
    }

    // MARK: Private

    /// None of them is also a side's name on some look ("Onyx wins" must never be a knight).
    /// Never a multiple of five long: `freshName` steps through the list five at a time
    /// and has to reach every name.
    static let names = [
        "Vesper", "Orion", "Halcyon", "Cipher", "Lumen", "Merlin", "Talon", "Zephyr",
        "Atlas", "Bastion", "Kestrel", "Sable", "Tempest", "Umbra", "Volt", "Zenith",
        "Aegis", "Cobalt", "Drake", "Eclipse", "Gambit", "Helix", "Iris", "Nova",
        "Raven", "Saber", "Comet", "Lyric", "Mako", "Quill", "Echo", "Flint",
    ]

    /// A name no other piece in the army has, picked the same way every time for this slot.
    private func freshName(for slot: ArmySlot) -> String {
        let taken = Set(army.records.values.compactMap(\.name))
        let start = (ArmySlot.allCases.firstIndex(of: slot) ?? 0) * 2
        for step in 0..<Self.names.count {
            let name = Self.names[(start + step * 5) % Self.names.count]
            if !taken.contains(name) { return name }
        }
        return slot.title
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(army).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Couldn't save the army: %@", "\(error)")
        }
    }
}
