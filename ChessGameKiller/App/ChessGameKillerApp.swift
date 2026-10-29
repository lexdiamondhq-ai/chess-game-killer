import SwiftUI
import UserNotifications

@main
struct ChessGameKillerApp: App {
    /// Set only when CI launches the app for screenshots; see `Showcase`.
    private let showcase: Showcase?
    /// Challenge a friend: the links, the live games and the screens they open.
    @State private var challenges = Showcase.challenges() ?? ChallengeCenter.live()

    init() {
        LookIntroduction.applyOnce()
        HintsIntroduction.applyOnce()
        showcase = Showcase.fromLaunchArguments()
        // A tapped daily reminder opens Today's Move.
        UNUserNotificationCenter.current().delegate = DailyNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let showcase {
                    ContentView(startsWithNewGame: false, startsAtHome: showcase.atHome,
                                match: showcase.match, coachOpen: showcase.coachOpen, vision: showcase.vision)
                } else {
                    ContentView()
                }
            }
            .challengeHost()
            .environment(challenges)
            // Loads the Premium plans and the player's subscription, and listens for renewals.
            .task { Premium.shared.start() }
        }
    }
}

/// Gilded, the black-and-gold set, replaced Noir as the default look. The first launch with it
/// switches to it once; the other looks stay in Settings, and anything picked after this is kept.
/// (An install that never had Sculpted also turns "Match rival" off, as Sculpted's introduction did.)
enum LookIntroduction {
    static let key = "gildedIntroduced"
    /// Set by the Sculpted introduction, which also turned "Match rival" off.
    static let sculptedKey = "sculptedIntroduced"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(BoardTheme.ID.gilded.rawValue, forKey: "boardTheme")
        if !defaults.bool(forKey: sculptedKey) {
            defaults.set(true, forKey: sculptedKey)
            defaults.set(false, forKey: "matchRival")
        }
    }
}

/// Move hints (the best-move arrows) are off unless the player turns them on: seeing your
/// best moves before you play spoils the game. This turns them off once for players who
/// had them on from before; switching them back on afterwards sticks.
enum HintsIntroduction {
    static let key = "hintsOffByDefault"

    static func applyOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        defaults.set(false, forKey: "showBestMoves")
    }
}

/// A game already under way, for the screenshots CI takes on the simulator, where the system's
/// glass is drawn as on a phone. Launched with `-showcase game`, the app skips the home screen
/// and the New Game sheet and opens on a game against a rival, a few moves in, with captures on
/// both sides and you to move. A normal launch never passes it, and then nothing here runs.
///
/// Other arguments: `-showcaseLook midnight` (any look's id), `-showcase3D NO`,
/// `-showcaseRival spark` (a rival's name), `-showcaseClock 15+10` (or `none`), `-showcaseCoach open`,
/// `-showcaseGhost all` (Ghost Vision held, the whole line) or `-showcaseGhost 1` (held, slid back to its second move),
/// `-showcaseBigBoard YES` (Big Board on), `-showcaseHome YES` (the home, with that game under way).
/// `-showcaseGames YES`, with or without `-showcase game`, lists a few friend and online games
/// on the home's Current games.
/// The look and the 3D switch are saved as settings, so the screen draws exactly as it would for a player.
struct Showcase {
    let match: MatchController
    let coachOpen: Bool
    /// Ghost Vision, already held, when asked for.
    var vision: GhostVision?
    /// Opens on the home, with the game under way.
    var atHome = false

    /// 1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Ng5 d5 5. exd5 Nxd5 6. Nxf7 Kxf7 7. Qf3+ Ke6.
    static let moves = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5", "d7d5",
                        "e4d5", "f6d5", "g5f7", "e8f7", "d1f3", "f7e6"]

    @MainActor
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Showcase? {
        guard defaults.string(forKey: "showcase") == "game" else { return nil }
        let look = defaults.string(forKey: "showcaseLook").flatMap(BoardTheme.ID.init(rawValue:)) ?? .gilded
        defaults.set(look.rawValue, forKey: "boardTheme")
        defaults.set(flag("showcase3D", in: defaults) ?? true, forKey: "sculpted3D")
        defaults.set(false, forKey: "matchRival")
        defaults.set(flag("showcaseBigBoard", in: defaults) ?? false, forKey: "bigBoard")

        var setup = MatchController.Setup()
        let rival = defaults.string(forKey: "showcaseRival")?.lowercased()
        setup.level = Rival.all.first { $0.name.lowercased() == rival }?.level ?? .club
        setup.timeControl = defaults.string(forKey: "showcaseClock").flatMap(TimeControl.init(rawValue:)) ?? .rapid10
        let match = MatchController(engine: StockfishEngine.shared, sounds: nil)
        match.start(setup)
        for move in moves {
            _ = match.game.playEngineMove(move)
        }
        var vision: GhostVision?
        if let ghost = defaults.string(forKey: "showcaseGhost") {
            defaults.set(true, forKey: GhostVision.storageKey)
            vision = GhostVision(holding: true, focus: Int(ghost))
        }
        return Showcase(match: match, coachOpen: defaults.string(forKey: "showcaseCoach") == "open", vision: vision,
                        atHome: flag("showcaseHome", in: defaults) ?? false)
    }

    /// Friend and online games for Current games, kept in memory and never checked with the server.
    @MainActor
    static func challenges(_ defaults: UserDefaults = .standard) -> ChallengeCenter? {
        guard flag("showcaseGames", in: defaults) == true else { return nil }
        let now = Date.now
        let games = [
            FriendGame(code: "7KQ2XM", token: "showcase", seat: .white, isCreator: true, opponentName: "Sam",
                       clock: FriendClock(initial: 600, increment: 0), status: .active, turn: .white, moveCount: 4,
                       fen: "rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3",
                       updatedAt: now.addingTimeInterval(-120)),
            FriendGame(code: "R3ATED", token: "showcase", seat: .black, isCreator: false, opponentName: "Maya",
                       clock: FriendClock(initial: 180, increment: 2), status: .active, turn: .black, moveCount: 5,
                       fen: "rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR b KQkq - 1 3",
                       rated: true, opponentRating: "1342", updatedAt: now.addingTimeInterval(-30)),
            FriendGame(code: "P4HRWN", token: "showcase", seat: .white, isCreator: true, opponentName: "Jordan",
                       clock: nil, status: .active, turn: .black, moveCount: 5,
                       fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
                       updatedAt: now.addingTimeInterval(-3_600)),
            FriendGame(code: "M8TQ3D", token: "showcase", seat: .white, isCreator: true,
                       clock: FriendClock(initial: 180, increment: 2), status: .waiting,
                       updatedAt: now.addingTimeInterval(-7_200)),
        ]
        let center = ChallengeCenter(api: LiveChallengeAPI(), store: ChallengeStore(games: games), sounds: nil)
        center.holdsStill = true
        return center
    }

    /// A YES/NO launch argument. Arguments arrive as text, which a Bool setting won't read.
    private static func flag(_ key: String, in defaults: UserDefaults) -> Bool? {
        guard let text = defaults.string(forKey: key)?.lowercased() else { return nil }
        return ["yes", "true", "1"].contains(text)
    }
}
