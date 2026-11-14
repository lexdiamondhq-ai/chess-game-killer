import Foundation

/// The army's champion and its job for today, for the Your army card on Home (Alex's pick,
/// 2026-11-12: "A and C together"). Worked out here so it can be tested without drawing.
///
/// - The champion: the most experienced piece no rival is holding, standing big on the card.
/// - The quest: free a piece a rival holds, or else help the piece nearest its next rank get there.
struct ArmyQuest: Equatable {
    enum Kind: Equatable {
        /// A rival holds this piece: beat that rival to win it back.
        case rescue(captor: MatchController.Level)
        /// This piece is `xpLeft` experience from `next`: a win with it still standing gets it closer.
        case rankUp(next: ArmyRank, xpLeft: Int, rival: MatchController.Level)
    }

    let slot: ArmySlot
    let kind: Kind

    /// The rival the quest's button plays.
    var rival: MatchController.Level {
        switch kind {
        case .rescue(let captor): return captor
        case .rankUp(_, _, let rival): return rival
        }
    }

    /// Today's job, or nil before the army's first game. A held piece comes first; otherwise
    /// the piece closest to its next rank, against the rival up next.
    @MainActor
    static func of(_ army: ArmyStore, next rival: MatchController.Level) -> ArmyQuest? {
        guard army.gamesPlayed > 0 else { return nil }
        if let held = ArmySlot.allCases.first(where: { army.captor(of: $0) != nil }),
           let captor = army.captor(of: held) {
            return ArmyQuest(slot: held, kind: .rescue(captor: captor))
        }
        let climbing: [(slot: ArmySlot, next: ArmyRank, left: Int, xp: Int)] = ArmySlot.allCases.compactMap { slot in
            let record = army.record(for: slot)
            guard record.games > 0, let next = record.rank.next else { return nil }
            return (slot, next, next.threshold - record.xp, record.xp)
        }
        // The fewest points to go; on a tie, the piece further along, then the order of the slots.
        guard let best = climbing.min(by: { ($0.left, -$0.xp) < ($1.left, -$1.xp) }) else { return nil }
        return ArmyQuest(slot: best.slot, kind: .rankUp(next: best.next, xpLeft: max(1, best.left), rival: rival))
    }

    /// What the card says, in one sentence.
    @MainActor
    func line(_ army: ArmyStore) -> String {
        let name: String = army.displayName(of: slot)
        switch kind {
        case .rescue(let captor):
            let who: String = army.record(for: slot).name == nil ? "" : ", your \(slot.title.lowercased())"
            return "\(captor.rival.name) holds \(army.displayName(of: slot, capitalized: false))\(who)."
        case .rankUp(let next, let left, _):
            return "\(name) is \(left) XP from \(next.title). Win with \(army.record(for: slot).name ?? "it") standing."
        }
    }

    /// The button's words.
    @MainActor
    func button(_ army: ArmyStore) -> String {
        switch kind {
        case .rescue:
            return "Win to free \(army.record(for: slot).name ?? "it")"
        case .rankUp(_, _, let rival):
            return "Play \(rival.rival.shortName)"
        }
    }
}

/// The army screen's own quest button: the army closes and Home plays the quest's rival, just as
/// the button on Home's Your army strip does (the rival's film first).
enum ArmyQuestLink {
    /// Posted with the rival's level (its raw value) as the object.
    static let play = Notification.Name("ChessGameKiller.playArmyQuest")
}

extension ArmyStore {
    /// The piece that stands big on the Home card: the most experienced one no rival is
    /// holding. Nil before any game.
    var champion: ArmySlot? {
        let free = ArmySlot.allCases.filter { captor(of: $0) == nil && record(for: $0).xp > 0 }
        return free.max { record(for: $0).xp < record(for: $1).xp }
    }

    /// A few things the piece has done, the proudest first, for under its name.
    func deeds(of slot: ArmySlot, limit: Int = 2) -> [String] {
        let record = record(for: slot)
        var deeds: [String] = []
        if record.mates > 0 { deeds.append(record.mates == 1 ? "Gave checkmate once" : "\(record.mates) checkmates") }
        if record.captures > 0 { deeds.append(record.captures == 1 ? "Took 1 piece" : "Took \(record.captures) pieces") }
        if record.survivedWins > 0 {
            deeds.append(record.survivedWins == 1 ? "1 win standing" : "\(record.survivedWins) wins standing")
        }
        if record.promotions > 0 { deeds.append(record.promotions == 1 ? "Promoted once" : "Promoted \(record.promotions) times") }
        if record.escapes > 0 { deeds.append(record.escapes == 1 ? "Won back from a rival" : "Won back \(record.escapes) times") }
        if record.honors > 0 {
            deeds.append(record.honors == 1 ? "Piece of the Match once" : "Piece of the Match \(record.honors) times")
        }
        if deeds.isEmpty { deeds.append(record.games == 1 ? "1 game played" : "\(record.games) games played") }
        return Array(deeds.prefix(limit))
    }

    /// How far the piece is from its last rank to its next, 0 to 1 (1 for a Legend).
    func rankProgress(of slot: ArmySlot) -> Double {
        let record = record(for: slot)
        guard let next = record.rank.next else { return 1 }
        let from = record.rank.threshold
        return min(1, max(0, Double(record.xp - from) / Double(next.threshold - from)))
    }
}
