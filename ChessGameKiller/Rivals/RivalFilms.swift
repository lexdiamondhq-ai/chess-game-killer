import AVFoundation
import Observation
import SwiftUI

/// Each rival's welcome film, its last frame as the card, and the theme that plays under the
/// game (Alex, 2026-11-07: "These are good, let's place in app"). Films and themes are bundled
/// in Rivals/Films: `rival-<slug>-film.mp4` (9:16, about ten seconds, sound mixed in),
/// `rival-<slug>-card.jpg` (the film's last frame) and `rival-<slug>-theme.mp3` (a one minute loop
/// of the same score, quieter, for the game).
struct RivalFilm {
    let rival: Rival
    /// Seconds into the film where the rival meets your eyes and the score hits: the title card
    /// rises just after.
    let beat: Double
    /// The film's name: "Out of the birches".
    let title: String
    /// One line on how the rival plays.
    let lore: String

    var level: MatchController.Level { rival.level }

    /// "I" to "V".
    var numeral: String { ["I", "II", "III", "IV", "V"][min(level.rawValue, 4)] }

    var filmURL: URL? { Bundle.main.url(forResource: "rival-\(rival.slug)-film", withExtension: "mp4") }
    var themeURL: URL? { Bundle.main.url(forResource: "rival-\(rival.slug)-theme", withExtension: "mp3") }
    var cardImage: UIImage? {
        Bundle.main.path(forResource: "rival-\(rival.slug)-card", ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
    }

    /// The rival before this one on the ladder, nil for the Cub.
    var previous: Rival? {
        MatchController.Level(rawValue: level.rawValue - 1)?.rival
    }

    static func of(_ level: MatchController.Level) -> RivalFilm {
        let rival = level.rival
        switch level {
        case .beginner:
            return RivalFilm(rival: rival, beat: 3.9, title: "Out of the birches",
                             lore: "Wears the fox. Still learning the hunt.")
        case .casual:
            return RivalFilm(rival: rival, beat: 3.5, title: "Out of the snow",
                             lore: "Wears the wolf. Knows the trail, then loses the scent.")
        case .club:
            return RivalFilm(rival: rival, beat: 4.3, title: "Through the storm",
                             lore: "Wears the bear. Charges in, then slips when it counts.")
        case .expert:
            return RivalFilm(rival: rival, beat: 4.0, title: "Down from the throne",
                             lore: "Wears the lion. Rules by the hammer, and never yields a square.")
        case .grandmaster:
            return RivalFilm(rival: rival, beat: 4.6, title: "The storm throne",
                             lore: "Crowned in bone and ash. Plays the masters' moves, then the machine's.")
        }
    }

    static let all: [RivalFilm] = MatchController.Level.allCases.map(of)
}

/// Who you may face. The Cub, the Hunter and the Berserker are always open; the Lionheart
/// opens once you beat the Berserker, and the Ashen King once you beat the Lionheart (Alex,
/// 2026-11-07). A win is read from the rivals you have beaten (`RivalBoardsEarned`), which keeps
/// wins saved under a rival's former name ("The 1600s").
/// The rivals whose welcome film you've seen. Home's Play shows the film every time now
/// (Alex, 2026-11-09); this only keeps the record.
enum RivalIntros {
    static let key = "rivals.introsSeen"

    static func seen(_ level: MatchController.Level, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(level.rival.slug)
    }

    static func mark(_ level: MatchController.Level, defaults: UserDefaults = .standard) {
        var all = defaults.stringArray(forKey: key) ?? []
        guard !all.contains(level.rival.slug) else { return }
        all.append(level.rival.slug)
        defaults.set(all, forKey: key)
    }
}

struct RivalLadder {
    /// Lowercased names of every opponent beaten.
    let beatenNames: Set<String>
    /// Every rival open, no climb: Premium players, and the app's own test builds (Alex,
    /// 2026-11-08: "should we open it all to premium users?").
    var allOpen = false

    init(beatenNames: Set<String>, allOpen: Bool = false) {
        self.beatenNames = beatenNames
        self.allOpen = allOpen
    }

    init(defaults: UserDefaults = .standard) {
        self.init(beatenNames: RivalBoardsEarned.names(defaults), allOpen: Self.opensEverything(defaults))
    }

    /// Premium (remembered at launch, as Premium itself reads it) opens every rival. Debug
    /// builds put on the phone from the Mac do too, so every rival can be tried; tests don't.
    static func opensEverything(_ defaults: UserDefaults) -> Bool {
        if defaults.bool(forKey: Premium.activeKey) { return true }
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #else
        return false
        #endif
    }

    /// The first rival that must be beaten before the next one opens: the Cub, so every rival
    /// waits until the one before it is beaten (Alex, 2026-11-08: "must beat the previous rival
    /// before moving on to the next").
    static let gate: MatchController.Level = .beginner

    func beaten(_ rival: Rival) -> Bool {
        beatenNames.contains(rival.name.lowercased())
            || rival.pastNames.contains { beatenNames.contains($0.lowercased()) }
    }

    func isOpen(_ level: MatchController.Level) -> Bool {
        guard !allOpen, level.rawValue > Self.gate.rawValue,
              let previous = MatchController.Level(rawValue: level.rawValue - 1) else { return true }
        return beaten(previous.rival)
    }

    /// The rival the hall opens on: the first open one not yet beaten, or the strongest open one.
    var current: MatchController.Level {
        let open = MatchController.Level.allCases.filter(isOpen)
        return open.first { !beaten($0.rival) } ?? open.last ?? .beginner
    }
}

/// The rival's theme under the game: it starts whenever a game against a rival begins (its
/// film first or not, a rematch too) and when you come back to one under way, loops quietly,
/// and fades when the game ends or you go home (Alex, 2026-11-08: the music must play when you
/// return to the rivals). Your Grudge stays quiet. Ambient, so it mixes with other audio and
/// stays quiet on silent. Settings > Sound & feel turns it off.
@MainActor
@Observable
final class RivalTheme {
    static let shared = RivalTheme()
    static let key = "rivalThemes"
    static let volume: Float = 0.26

    private(set) var on: Bool
    @ObservationIgnored private var player: AVAudioPlayer?
    /// The rival whose theme the player holds.
    @ObservationIgnored private var loaded: MatchController.Level?
    @ObservationIgnored private var playing: MatchController.Level?

    private init() {
        on = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    func toggle() {
        on.toggle()
        UserDefaults.standard.set(on, forKey: Self.key)
        if !on { stop() }
    }

    /// Whether a game has a rival's theme: every game against the computer but Your Grudge.
    static func hasTheme(_ setup: MatchController.Setup) -> Bool {
        setup.opponent == .computer && !setup.grudge
    }

    /// A new game started: a rival game plays its rival's theme, any other game is quiet.
    func gameStarted(_ setup: MatchController.Setup) {
        if Self.hasTheme(setup) { play(setup.level) } else { stop() }
    }

    /// The game screen came back over a game under way (from Home): its theme picks up again.
    func resume(_ setup: MatchController.Setup) {
        guard Self.hasTheme(setup) else { return }
        play(setup.level)
    }

    private func play(_ level: MatchController.Level) {
        guard on, !Welcome.isUnderTest, let url = RivalFilm.of(level).themeURL else { return }
        if loaded != level || player == nil {
            player?.stop()
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.prepareToPlay()
            loaded = level
        }
        guard let player else { return }
        playing = level
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        // Already playing (or fading out): it only rises again, with no restart.
        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(Self.volume, fadeDuration: 3)
    }

    /// Fades the theme out, as the game ends or leaves the screen.
    func stop(fade: TimeInterval = 1.2) {
        playing = nil
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: fade)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fade + 0.05))
            guard let self, self.playing == nil else { return }
            self.player?.stop()
            // The next game hears it from the top.
            self.player?.currentTime = 0
        }
    }
}
