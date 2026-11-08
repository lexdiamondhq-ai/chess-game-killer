import Foundation

/// The line a rival says under its name on the game screen while it waits, in place of its rank
/// and rating (Alex, 2026-11-07: "more condescending the better, and cocky as you climb the
/// ranks"). The Cub is cheeky, the Hunter patient, the Berserker brutal, the Lionheart royal
/// and the Dragonlord barely aware you exist. One line per game, short enough for one row.
enum RivalTaunt {
    static func lines(for level: MatchController.Level) -> [String] {
        switch level {
        case .beginner: return [
            "I'm small. My teeth aren't.",
            "Go on. I won't bite. Much.",
            "Cute. You think you can win.",
        ]
        case .casual: return [
            "I've watched you since the forest.",
            "Run if you like. I know these woods.",
            "Every hunt ends the same way.",
        ]
        case .club: return [
            "Pray your pieces are braver than you.",
            "I don't think. I break things.",
            "I'll wear your king as a trophy.",
            "Bring them all. I'll break them all.",
        ]
        case .expert: return [
            "Kneel now and keep your head.",
            "Kings have begged me for less.",
            "Bow, and I may spare a pawn.",
            "You're a footnote in my legend.",
        ]
        case .grandmaster: return [
            "Kneel, little king. Then burn.",
            "I've burned greater kings than you.",
            "You're not my rival. You're kindling.",
            "Ash keeps no names. Nor will I.",
            "Your whole line ends tonight.",
        ]
        }
    }

    /// This game's line: the same one all game long, a new one next game.
    static func line(for level: MatchController.Level, game: UUID) -> String {
        let options = lines(for: level)
        return options[Int(game.uuid.0) % options.count]
    }
}
