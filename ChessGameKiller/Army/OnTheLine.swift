import Foundation

/// On the line: before a game against a rival the player may stake one named piece.
/// Win and it earns double experience and a trophy from that rival; lose and the rival
/// holds it, out of the army's games, until the player beats that rival again.
///
/// A rival holds one prisoner at most, so while it holds one nothing can be staked
/// against it: the next game there is the rescue. The king is never staked, nor a
/// piece another rival is holding. Hints on the board rule a stake out (New Game asks
/// for Grades or Just play).
extension ArmyStore {
    /// The rival holding this piece, if one is.
    func captor(of slot: ArmySlot) -> MatchController.Level? {
        army.captives[slot].flatMap { MatchController.Level(rawValue: $0) }
    }

    /// The piece this rival is holding, if any.
    func prisoner(of level: MatchController.Level) -> ArmySlot? {
        ArmySlot.allCases.first { army.captives[$0] == level.rawValue }
    }

    /// Pieces that can go on the line: named ones (Veteran and up), never the king,
    /// none held by a rival. The most experienced first.
    var stakeable: [ArmySlot] {
        ArmySlot.allCases
            .filter { $0 != .king && record(for: $0).name != nil && army.captives[$0] == nil }
            .sorted { record(for: $0).xp > record(for: $1).xp }
    }

    /// Whether `slot` can be put on the line against `level` right now. Nil is "nothing staked", always fine.
    func canStake(_ slot: ArmySlot?, against level: MatchController.Level) -> Bool {
        guard let slot else { return true }
        return prisoner(of: level) == nil && stakeable.contains(slot)
    }

    /// The banner as a staked game starts.
    func stakeNews(_ slot: ArmySlot, against level: MatchController.Level) -> ArmyNews {
        ArmyNews(slot: slot, rank: record(for: slot).rank, name: displayName(of: slot),
                 kind: .staked(rival: level.rival.name))
    }

    /// The banner as a rescue game starts: the piece this rival is holding.
    func rescueNews(against level: MatchController.Level) -> ArmyNews? {
        guard let slot = prisoner(of: level) else { return nil }
        return ArmyNews(slot: slot, rank: record(for: slot).rank, name: displayName(of: slot),
                        kind: .captured(rival: level.rival.name))
    }
}
