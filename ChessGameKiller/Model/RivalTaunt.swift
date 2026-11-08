import Foundation

/// What a rival says under its name on the game screen while it waits, in place of its rank and
/// rating (Alex, 2026-11-07: "more condescending the better, and cocky as you climb the ranks";
/// 2026-11-08: dark and gloomy, rotating through the game). The Cub is a small thing in the
/// dark, the Hunter the woods at night, the Berserker the battlefield after, the Lionheart a
/// throne of graves, and the Ashen King the end of every kingdom. Each fits two rows.
enum RivalTaunt {
    static func lines(for level: MatchController.Level) -> [String] {
        switch level {
        case .beginner: return [
            "The dark is hungry. So am I.",
            "Little steps. Long shadows.",
            "Something is following you. Me.",
            "You smell like a lost game.",
            "Small teeth still draw blood.",
            "Mother says I can keep you.",
        ]
        case .casual: return [
            "I've watched you since the forest.",
            "No one hears you out here.",
            "Your tracks end at my door.",
            "The woods remember every scream.",
            "Night falls. So will you.",
            "Every hunt ends the same way.",
        ]
        case .club: return [
            "Your pieces will feed the crows.",
            "I don't think. I break things.",
            "The field is red. It wants more.",
            "I'll wear your king as a trophy.",
            "Your bones will make good dice.",
            "Pray. Nobody is listening.",
        ]
        case .expert: return [
            "My crown is made of men like you.",
            "Kneel now and keep your head.",
            "The throne room smells of graves.",
            "Kings have begged me for less.",
            "Your banner falls at dusk.",
            "History forgets the defeated.",
        ]
        case .grandmaster: return [
            "Kneel, little king. Then burn.",
            "I've burned greater kings than you.",
            "You're not my rival. You're kindling.",
            "Ash keeps no names. Nor will I.",
            "Every kingdom ends in ash.",
            "Your whole line ends tonight.",
        ]
        }
    }

    /// Moves (both sides') before the rival turns to its next line: every second move of yours.
    static let pliesPerLine = 4

    /// The line now: each game starts somewhere new in the rival's lines and moves on through
    /// them as the game goes.
    static func line(for level: MatchController.Level, game: UUID, ply: Int = 0) -> String {
        let options = lines(for: level)
        return options[(Int(game.uuid.0) + ply / pliesPerLine) % options.count]
    }
}
