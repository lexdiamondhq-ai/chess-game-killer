import AVFoundation
import Foundation

/// Every sound the game can make. File names match ChessGameKiller/Sounds/*.mp3,
/// which are generated with ElevenLabs by scripts/make_sounds.py.
enum GameSound: String, CaseIterable {
    case move
    /// Training's soft click: a piece picked up, a square found. In a game, picking up a
    /// piece is felt (a haptic), not heard.
    case select
    case capture
    case check
    case castle
    case win
    case gameOver = "game-over"
    /// A short video-game "level clear" theme, when a person wins.
    case victory
    /// The chime as the app opens.
    case welcome

    /// Evens out the generated files, which come out at different loudness. The wooden
    /// knocks sit a little under full volume; a capture lands slightly harder than a move,
    /// and check (its file raised 3 dB) a touch above a move. The endings sit only a little
    /// above the knocks, so the end of a game is never a jolt.
    var volume: Float {
        switch self {
        case .move: return 0.75
        case .select: return 0.3
        case .capture: return 0.9
        case .check: return 1.0
        case .castle: return 0.75
        case .win: return 0.3
        case .gameOver: return 0.25
        case .victory: return 0.4
        case .welcome: return 0.4
        }
    }

    /// The longer cues: the endings and the welcome. They fade out when something new begins.
    var isLong: Bool {
        switch self {
        case .win, .gameOver, .victory, .welcome: return true
        case .move, .select, .capture, .check, .castle: return false
        }
    }
}

@MainActor
protocol SoundPlaying: AnyObject {
    func play(_ sound: GameSound)
    /// Plays `sound` `delay` seconds from now, such as when a piece touches down on the 3D board.
    func play(_ sound: GameSound, after delay: TimeInterval)
    /// Fades out and stops the longer cues still playing, like a victory theme running into a new game.
    func stopAll(fade: TimeInterval)
}

@MainActor
extension SoundPlaying {
    func play(_ sound: GameSound, after delay: TimeInterval) {
        play(sound)
    }

    func stopAll(fade: TimeInterval) {}
}

/// Plays the bundled sound effects. Missing files are skipped quietly.
@MainActor
final class SoundPlayer: SoundPlaying {
    static let shared = SoundPlayer()

    /// Mirrors the "Sound effects" switch in the menu.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEffects") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEffects") }
    }

    /// Two players for each knock, used in turn, so a piece landing never cuts off the
    /// one before it; one for each longer cue.
    private var players: [GameSound: [AVAudioPlayer]] = [:]
    private var nextPlayer: [GameSound: Int] = [:]
    /// Longer cues fading out, to be stopped once they are silent.
    private var fading: Set<GameSound> = []

    private init() {
        // Ambient: respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for sound in GameSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3") else { continue }
            let pool = (0..<(sound.isLong ? 1 : 2)).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            for player in pool {
                player.volume = sound.volume
                player.prepareToPlay()
            }
            if !pool.isEmpty { players[sound] = pool }
        }
    }

    /// The welcome chime, once per launch.
    private var welcomed = false

    func playWelcome() {
        guard !welcomed else { return }
        welcomed = true
        play(.welcome)
    }

    func play(_ sound: GameSound) {
        play(sound, after: 0)
    }

    func play(_ sound: GameSound, after delay: TimeInterval) {
        // The victory theme stands in for the short win chime until its file is in the app.
        if sound == .victory, players[.victory] == nil {
            return play(.win, after: delay)
        }
        guard isEnabled, let pool = players[sound], !pool.isEmpty else { return }
        let index = (nextPlayer[sound] ?? 0) % pool.count
        nextPlayer[sound] = index + 1
        let player = pool[index]
        fading.remove(sound)
        if player.isPlaying { player.stop() }
        player.volume = sound.volume
        player.currentTime = 0
        if delay > 0 {
            // Timed by the audio clock, so it lands with the animation it follows.
            player.play(atTime: player.deviceCurrentTime + delay)
        } else {
            player.play()
        }
    }

    func stopAll(fade: TimeInterval) {
        var faded: Set<GameSound> = []
        for sound in GameSound.allCases where sound.isLong {
            for player in players[sound] ?? [] where player.isPlaying {
                player.setVolume(0, fadeDuration: fade)
                faded.insert(sound)
            }
        }
        guard !faded.isEmpty else { return }
        fading.formUnion(faded)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fade))
            guard let self else { return }
            // A cue played again meanwhile has left `fading` and keeps playing.
            for sound in faded where self.fading.contains(sound) {
                for player in self.players[sound] ?? [] {
                    player.stop()
                    player.currentTime = 0
                    player.volume = sound.volume
                }
                self.fading.remove(sound)
            }
        }
    }
}
