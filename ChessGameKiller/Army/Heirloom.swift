import ChessKit
import Foundation

/// The Heirloom Set: what a piece's record leaves on the piece itself, the way a real set wears
/// its years. Read from the army record, so it grows with every game and needs nothing saved.
///
/// - Gold seams (kintsugi): one for each time the piece came back, escaping a rival that held it
///   or taking revenge on one that kept taking it.
/// - A gold collar: a pawn that has made it to the last rank.
/// - Notches on the base: one for every five pieces it has taken.
/// - Patina: a warm age that deepens over its first 120 games.
struct Heirloom: Equatable {
    /// Gold seams, at most three.
    var seams = 0
    /// A pawn that has promoted.
    var collar = false
    /// Notches on the base, at most five.
    var notches = 0
    /// How aged the piece looks, 0 (new) to 1.
    var patina = 0.0
    /// Fixes where the seams run, so each piece keeps its own.
    var seed = 0

    /// Settings: "Piece history", on unless the player turns it off.
    static let settingKey = "heirloomMarks"

    static let maxSeams = 3
    static let maxNotches = 5
    static let capturesPerNotch = 5
    static let gamesForFullPatina = 120

    init(seams: Int = 0, collar: Bool = false, notches: Int = 0, patina: Double = 0, seed: Int = 0) {
        self.seams = seams
        self.collar = collar
        self.notches = notches
        self.patina = patina
        self.seed = seed
    }

    init(record: PieceRecord, slot: ArmySlot) {
        seams = min(Self.maxSeams, record.escapes + record.revenge.count)
        collar = slot.isPawn && record.promotions > 0
        notches = min(Self.maxNotches, record.captures / Self.capturesPerNotch)
        patina = min(1, Double(record.games) / Double(Self.gamesForFullPatina))
        seed = ArmySlot.allCases.firstIndex(of: slot) ?? 0
    }

    /// Nothing to show yet.
    var isEmpty: Bool { seams == 0 && !collar && notches == 0 && patina < 0.05 }

    /// What each mark means, for the piece's page, one line each.
    func story(for record: PieceRecord) -> [String] {
        var lines: [String] = []
        if seams > 0 {
            var why: [String] = []
            if record.escapes > 0 { why.append(record.escapes == 1 ? "won back once" : "won back \(record.escapes) times") }
            if !record.revenge.isEmpty {
                let rivals = record.revenge.sorted().compactMap { MatchController.Level(rawValue: $0)?.rival.name }
                why.append("revenge on \(rivals.joined(separator: ", "))")
            }
            lines.append("\(seams == 1 ? "A gold seam" : "\(seams) gold seams"): \(why.joined(separator: "; ")).")
        }
        if collar {
            lines.append(record.promotions == 1 ? "A gold collar: it reached the last rank."
                                                : "A gold collar: it reached the last rank \(record.promotions) times.")
        }
        if notches > 0 {
            lines.append("\(notches == 1 ? "A notch" : "\(notches) notches") on the base: \(record.captures) pieces taken.")
        }
        if patina >= 0.05 {
            lines.append(patina >= 1 ? "Full patina: \(record.games) games." : "Patina from \(record.games) games.")
        }
        return lines
    }
}

extension ArmyStore {
    /// How a piece of the army looks after everything it has been through.
    func heirloom(for slot: ArmySlot) -> Heirloom {
        Heirloom(record: record(for: slot), slot: slot)
    }
}
