import AVFoundation
import Foundation

/// Every sound the game can make. File names match ChessGameKiller/Sounds/*.mp3,
/// which are generated with ElevenLabs by scripts/make_sounds.py.
enum GameSound: String, CaseIterable {
    case move
    case select
    case capture
    case check
    case castle
    case gameStart = "game-start"
    case win
    case gameOver = "game-over"

    /// Evens out the generated files, which come out at different loudness.
    var volume: Float {
        switch self {
        case .move: return 1.0
        case .select: return 0.35
        case .capture: return 0.6
        case .check: return 0.85
        case .castle: return 0.9
        case .gameStart: return 0.5
        case .win: return 0.6
        case .gameOver: return 0.5
        }
    }
}

@MainActor
protocol SoundPlaying: AnyObject {
    func play(_ sound: GameSound)
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

    private var players: [GameSound: AVAudioPlayer] = [:]

    private init() {
        // Ambient: respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for sound in GameSound.allCases {
            guard
                let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3"),
                let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.volume = sound.volume
            player.prepareToPlay()
            players[sound] = player
        }
    }

    func play(_ sound: GameSound) {
        guard isEnabled, let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
