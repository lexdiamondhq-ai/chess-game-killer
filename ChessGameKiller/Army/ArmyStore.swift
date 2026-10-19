import ChessKit
import Foundation
import Observation

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

    /// Experience: a little for every game, more for winning, taking material,
    /// promoting and delivering mate.
    var xp: Int {
        games + wins * 3 + survivedWins * 2 + captureValue * 2 + promotions * 10 + mates * 20
    }

    var rank: ArmyRank { .forXP(xp) }
}

/// Something worth telling the player after a game.
struct ArmyNews: Identifiable, Equatable {
    let slot: ArmySlot
    let rank: ArmyRank
    let name: String

    var id: String { slot.rawValue }

    var headline: String {
        switch rank {
        case .veteran: return "Your \(slot.title.lowercased()) earned a name: \(name)"
        case .elite: return "\(name) earned a battle scar"
        case .legend: return "\(name) became a Legend"
        case .recruit: return name
        }
    }
}

/// The player's army: every piece's record, saved on this device.
/// Only games against the computer that start from the usual position count.
@MainActor
@Observable
final class ArmyStore {
    private(set) var army: Army

    struct Army: Codable, Equatable {
        var records: [ArmySlot: PieceRecord] = [:]
        var lastGameID: UUID?
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

    var gamesPlayed: Int {
        army.records.values.map(\.games).max() ?? 0
    }

    var hasVeterans: Bool {
        army.records.values.contains { $0.rank >= .veteran }
    }

    // MARK: Changing

    /// Adds a finished game to every piece's record. `won` is nil for a draw.
    /// Returns what changed that is worth telling the player. A game is only counted once.
    @discardableResult
    func record(_ ledger: PieceLedger, playerColor: Piece.Color, won: Bool?) -> [ArmyNews] {
        guard army.lastGameID != ledger.gameID else { return [] }
        army.lastGameID = ledger.gameID
        let standing = Set(ledger.origins.values)
        var news: [ArmyNews] = []

        for slot in ArmySlot.allCases {
            let start = slot.square(for: playerColor)
            let game = ledger.stats(forPieceStartingOn: start)
            var record = record(for: slot)
            let rankBefore = record.rank

            record.games += 1
            if won == true {
                record.wins += 1
                if standing.contains(start) { record.survivedWins += 1 }
            }
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
        }
        save()
        return news.sorted { $0.rank > $1.rank }
    }

    func rename(_ slot: ArmySlot, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var record = record(for: slot)
        record.name = String(trimmed.prefix(20))
        army.records[slot] = record
        save()
    }

    func reset() {
        army = Army()
        save()
    }

    // MARK: Private

    static let names = [
        "Vesper", "Orion", "Halcyon", "Cipher", "Lumen", "Onyx", "Talon", "Zephyr",
        "Atlas", "Ember", "Kestrel", "Sable", "Tempest", "Umbra", "Volt", "Zenith",
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
            print("Couldn't save the army: \(error)")
        }
    }
}
