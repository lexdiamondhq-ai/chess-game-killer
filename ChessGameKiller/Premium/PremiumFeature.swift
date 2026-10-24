import Foundation

/// What Premium adds, as agreed in the Premium plan (Oct 24, 2026). The free app keeps the
/// whole game; Premium is getting better faster, plus the features that cost money each time.
///
/// Two kinds of feature:
/// - counted ones, which free players can use a few times a day or week (`free` is set);
/// - locked ones, which only Premium opens (`free` is nil and `isLocked` is true).
enum PremiumFeature: String, CaseIterable, Identifiable, Codable {
    // Counted
    case ghostVision
    case talk
    case scan
    case ratedPuzzle
    case puzzleRush
    case fullRewind
    case openingDrill
    case endgameDrill
    case calculationDrill
    // Locked
    case lessons
    case puzzleCycles
    case puzzleReview
    case trainingRooms
    case allOpenings
    case masterGames
    case boardLooks
    case coachProfile

    var id: String { rawValue }

    /// How many uses, and over how long.
    struct Allowance: Equatable {
        enum Period: String, Equatable {
            case day, week
        }

        let uses: Int
        let period: Period

        static func perDay(_ uses: Int) -> Allowance { Allowance(uses: uses, period: .day) }
        static func perWeek(_ uses: Int) -> Allowance { Allowance(uses: uses, period: .week) }

        /// "3 a day", "1 a week".
        var phrase: String { "\(uses) a \(period.rawValue)" }
    }

    /// The free allowance. Nil: only Premium opens it.
    var free: Allowance? {
        switch self {
        case .ghostVision: return .perDay(3)
        case .talk: return .perWeek(3)
        case .scan: return .perWeek(3)
        case .ratedPuzzle: return .perDay(15)
        case .puzzleRush: return .perDay(1)
        case .fullRewind: return .perDay(1)
        case .openingDrill, .endgameDrill, .calculationDrill: return .perDay(1)
        case .lessons, .puzzleCycles, .puzzleReview, .trainingRooms, .allOpenings, .masterGames, .boardLooks, .coachProfile:
            return nil
        }
    }

    /// Premium's allowance. Nil: unlimited. Only the features that cost money per use have one,
    /// so one person can't run up the bill.
    var premium: Allowance? {
        switch self {
        case .talk: return .perDay(10)
        case .scan: return .perDay(3)
        default: return nil
        }
    }

    var isLocked: Bool { free == nil }

    /// The feature's name, as the offer screen says it.
    var title: String {
        switch self {
        case .ghostVision: return "Ghost Vision"
        case .talk: return "Talk It Through"
        case .scan: return "Photo scans"
        case .ratedPuzzle: return "Rated puzzles"
        case .puzzleRush: return "Puzzle Rush"
        case .fullRewind: return "Full Rewind"
        case .openingDrill: return "Opening drills"
        case .endgameDrill: return "Endgame drills"
        case .calculationDrill: return "Calculation drills"
        case .lessons: return "Every lesson"
        case .puzzleCycles: return "Puzzle Cycles"
        case .puzzleReview: return "Puzzle Review"
        case .trainingRooms: return "Every training room"
        case .allOpenings: return "Every opening"
        case .masterGames: return "Master games"
        case .boardLooks: return "Every board look"
        case .coachProfile: return "Your style profile"
        }
    }

    /// One line on where the free part stops, for the offer screen and limit cards.
    var limitLine: String {
        switch self {
        case .ghostVision: return "That's today's 3 free Ghost Visions. Premium sees ahead whenever you like."
        case .talk: return "That's your 3 free talks this week. Premium talks it through 10 times a day."
        case .scan: return "That's your 3 free photo scans this week. Premium scans 3 boards a day. Setting up by hand is always free."
        case .ratedPuzzle: return "That's today's 15 free puzzles. More tomorrow, or unlimited with Premium."
        case .puzzleRush: return "That's today's free Puzzle Rush. Premium rushes as often as you like."
        case .fullRewind: return "Today's free full Rewind is used. The line and key moments stay free for every game."
        case .openingDrill: return "That's today's free opening drill. Premium drills all 3,865 openings."
        case .endgameDrill: return "That's today's free endgame. Premium opens all 22."
        case .calculationDrill: return "That's today's free calculation drill. Premium has no limit."
        case .lessons: return "The first 5 lessons are free. Premium opens all 15, and every new pack."
        case .puzzleCycles: return "Cycles, the Woodpecker method, comes with Premium."
        case .puzzleReview: return "Your review queue of missed puzzles comes with Premium."
        case .trainingRooms: return "Candidate moves and Guess the Move come with Premium."
        case .allOpenings: return "The popular openings are free. Premium opens all 3,865 named lines and search."
        case .masterGames: return "Browsing master games, and how players at your level answer, come with Premium."
        case .boardLooks: return "Gilded, Noir and Midnight are free, and each rival's board once you beat that rival. Premium opens every look."
        case .coachProfile: return "Your top weakness is free. Premium shows your whole style and a plan rebuilt after every game."
        }
    }
}

/// The plans on sale. The ids must match App Store Connect and Support/Premium.storekit.
enum PremiumPlan: String, CaseIterable, Identifiable {
    case yearly = "com.chessgamekiller.app.premium.yearly"
    case monthly = "com.chessgamekiller.app.premium.monthly"

    var id: String { rawValue }

    /// Shown before the App Store's own price arrives (and in screenshots).
    var fallbackPrice: String {
        switch self {
        case .yearly: return "$59.99"
        case .monthly: return "$9.99"
        }
    }

    var name: String {
        switch self {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        }
    }

    var per: String {
        switch self {
        case .yearly: return "a year"
        case .monthly: return "a month"
        }
    }
}
