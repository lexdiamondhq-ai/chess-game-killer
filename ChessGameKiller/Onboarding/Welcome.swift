import Foundation

/// The first run: a short welcome that asks how much chess the player has played, lets them
/// pick a board, tells them the three rules that cost something, and starts their first game.
/// It shows once. Settings can bring it back.
enum Welcome {
    static let key = "welcomeSeen"

    /// Whether the welcome should open now. Never for CI's game pictures, which pass `-showcase`.
    static func shouldShow(_ defaults: UserDefaults = .standard) -> Bool {
        if defaults.string(forKey: "showcaseWelcome") != nil { return true }
        if defaults.string(forKey: "showcase") != nil { return false }
        return !defaults.bool(forKey: key)
    }

    /// The unit tests run inside the app: their pictures of the game and the home never show the welcome or tips.
    static let isUnderTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    /// Settings › How it works › Replay the welcome: it opens again straight away.
    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The looks offered on the welcome: the ones every player has. Gilded, the default, first.
    static let looks: [BoardTheme.ID] = [.gilded, .noir, .midnight]

    /// The page CI asks for with `-showcaseWelcome 2`, counted from 0.
    static func showcasePage(_ defaults: UserDefaults = .standard) -> Int {
        Int(defaults.string(forKey: "showcaseWelcome") ?? "") ?? 0
    }
}

/// How much chess the player has played, asked on the welcome. It picks the first rival
/// and whether the coach shows its best move.
enum Experience: String, CaseIterable, Identifiable {
    case new, casual, regular, club

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: return "I'm learning the moves"
        case .casual: return "I play now and then"
        case .regular: return "I play most weeks"
        case .club: return "I play in a club or online"
        }
    }

    /// The rival the first game is against.
    var level: MatchController.Level {
        switch self {
        case .new: return .beginner
        case .casual: return .casual
        case .regular: return .club
        case .club: return .expert
        }
    }

    /// New players see the coach's best move lit on the board; everyone else plays on their own.
    var showsHints: Bool { self == .new }

    /// The line under the title: who they'll meet first.
    var detail: String {
        let rival = level.rival
        return showsHints
            ? "First rival: \(rival.name). Hints on to show you good moves."
            : "First rival: \(rival.name), \(rival.elo)."
    }
}

/// What the player picked on the welcome, saved as the settings the rest of the app reads.
struct WelcomeChoice: Equatable {
    var experience: Experience = .new
    var look: BoardTheme.ID = .gilded

    func apply(_ defaults: UserDefaults = .standard) {
        defaults.set(experience.level.rawValue, forKey: "setup.level")
        defaults.set(look.rawValue, forKey: "boardTheme")
        defaults.set(experience.showsHints, forKey: "showBestMoves")
    }

    /// The first game: against the rival picked, on last time's side and clock.
    @MainActor
    func setup(_ defaults: UserDefaults = .standard) -> MatchController.Setup {
        var setup = NewGameSheet.savedSetup(defaults)
        setup.level = experience.level
        return setup
    }
}

/// The rules worth knowing before they cost something, said the same way on the welcome
/// and in Settings' "How it works".
enum HouseRule: String, CaseIterable, Identifiable {
    case help, leaving, grudges, stakes

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .help: return "hand.raised"
        case .leaving: return "flag"
        case .grudges: return "flame"
        case .stakes: return "lock"
        }
    }

    var title: String {
        switch self {
        case .help: return "Help halves the reward"
        case .leaving: return "Leaving a game is a loss"
        case .grudges: return "Rivals hold grudges"
        case .stakes: return "A piece on the line can be taken"
        }
    }

    var text: String {
        switch self {
        case .help:
            return "Undo, played hints, seeing ahead and talking it through are always there. A game with any of them earns your pieces half the XP."
        case .leaving:
            return "Starting a new game mid-game counts as a loss for your pieces. Going home only pauses it."
        case .grudges:
            return "A rival that takes the same piece three times holds a grudge. Win with that piece making a capture for bonus XP."
        case .stakes:
            return "Before a game you can stake a named piece. Win for double XP and a trophy; lose and the rival keeps it until you beat them."
        }
    }

    /// The welcome tells the first three; staking only matters once a piece has a name.
    static let onWelcome: [HouseRule] = [.help, .leaving, .grudges]
}
