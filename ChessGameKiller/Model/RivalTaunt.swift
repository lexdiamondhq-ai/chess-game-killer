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

    /// What the rival says as the fight turns (Alex picked "the card feels the fight",
    /// 2026-11-14): it brags when it is ahead, gets rattled when you are, and near the end it
    /// says its last words. An even game keeps its usual lines.
    static func lines(for level: MatchController.Level, mood: RivalMood) -> [String] {
        switch mood {
        case .even: return lines(for: level)
        case .ahead:
            switch level {
            case .beginner: return [
                "Mine now. Mother will be proud.",
                "I bit you. Did it hurt?",
                "Little teeth, big meal.",
                "You dropped something. I kept it.",
            ]
            case .casual: return [
                "One down. The hunt goes on.",
                "I can smell you bleeding.",
                "Your tracks are getting slower.",
                "Run. It makes it more fun.",
            ]
            case .club: return [
                "Your piece fed the crows.",
                "More! Bring me more!",
                "I'm wearing your army now.",
                "The field is drinking well.",
            ]
            case .expert: return [
                "Another head for the wall.",
                "Your court is emptying, little king.",
                "Bow. It's almost over.",
                "My throne thanks you.",
            ]
            case .grandmaster: return [
                "Burn. All of it burns.",
                "Your kingdom is smoke already.",
                "I warm my hands on your army.",
                "Ash, ash, and more ash.",
            ]
            }
        case .behind:
            switch level {
            case .beginner: return [
                "That... that wasn't fair.",
                "I'm not scared. I'm not.",
                "Mother? Mother?",
                "Lucky. Just lucky.",
            ]
            case .casual: return [
                "That was luck. Nothing more.",
                "The woods are too quiet.",
                "Who is hunting who?",
                "I lost your scent...",
            ]
            case .club: return [
                "No... no, I'll break you yet.",
                "That was luck.",
                "Blood in my eyes. Can't see.",
                "Stand still and fight me!",
            ]
            case .expert: return [
                "A lucky blow. Nothing more.",
                "Guards! Where are my guards?",
                "My crown... feels heavy.",
                "You dare? In my own hall?",
            ]
            case .grandmaster: return [
                "Impossible. I am the end.",
                "The fire flickers. Why?",
                "You will pay for that.",
                "No one cuts the Ashen King.",
            ]
            }
        case .doomed:
            switch level {
            case .beginner: return [
                "I want to go home.",
                "Please... not like this.",
                "Mother, I tried.",
            ]
            case .casual: return [
                "The hunter... is the hunted.",
                "Tell the woods I fought.",
                "Snow is so cold tonight.",
            ]
            case .club: return [
                "No. Not like this.",
                "The crows... are watching me.",
                "One more swing. Just one.",
            ]
            case .expert: return [
                "Long live... the king.",
                "My throne... is empty.",
                "History will forget me.",
            ]
            case .grandmaster: return [
                "Even ash... must fall.",
                "The fire goes out. At last.",
                "Kneel? No. I will not.",
            ]
            }
        }
    }

    /// Moves (both sides') before the rival turns to its next line: every second move of yours.
    static let pliesPerLine = 4

    /// The line now: each game starts somewhere new in the rival's lines and moves on through
    /// them as the game goes.
    static func line(for level: MatchController.Level, game: UUID, ply: Int = 0, mood: RivalMood = .even) -> String {
        let options = lines(for: level, mood: mood)
        return options[(Int(game.uuid.0) + ply / pliesPerLine) % options.count]
    }
}

/// How the fight is going for the rival, which its card and its words follow.
enum RivalMood: Equatable {
    case even
    /// Three or more ahead in material, or clearly winning.
    case ahead
    /// Three or more behind, or clearly losing.
    case behind
    /// Mated soon, or hopelessly behind: its last words.
    case doomed

    /// `lead` is the rival's material lead in pawns; `chances` its winning chances (-1...1)
    /// when the coach has judged the position.
    init(lead: Int, chances: Double?) {
        if lead <= -9 || (chances ?? 0) <= -0.95 {
            self = .doomed
        } else if lead <= -3 || (chances ?? 0) <= -0.6 {
            self = .behind
        } else if lead >= 3 || (chances ?? 0) >= 0.6 {
            self = .ahead
        } else {
            self = .even
        }
    }
}
