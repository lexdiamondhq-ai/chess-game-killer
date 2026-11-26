import AVFoundation
import Foundation

/// Every sound the game can make. File names match ChessGameKiller/Sounds/*.mp3,
/// which are generated with ElevenLabs by scripts/make_sounds.py.
enum GameSound: String, CaseIterable {
    /// A piece set down: the same soft wooden tock as a rival's move (move-soft.mp3, ...), in
    /// every piece set and on every screen, so no move ever squeaks or clanks (Alex, 2026-11-26).
    case move
    /// A timed game's move: the piece set down, then the chess clock pressed.
    case clockMove = "move-clock"
    /// A rival's move: a clean, soft wooden "tock" like other chess apps use, the same in every
    /// piece set and with no clock press, so the computer's moves never clank (Alex, 2026-11-23).
    /// It has takes like a move (move-soft.mp3, move-soft-2.mp3, ...). The tocks are made in
    /// code (a few fading wood tones under 3 kHz), not recorded.
    case rivalMove = "move-soft"
    /// A rival's capture, as quiet and soft as its move.
    case rivalCapture = "capture-soft"
    /// Training's soft click: a piece picked up, a square found. In a game, picking up a
    /// piece is felt (a haptic), not heard.
    case select
    /// A capture: the soft tock of a rival's capture (capture-soft.mp3), for everyone.
    case capture
    case check
    /// Castling: two soft tocks, king then rook (castle.mp3, made from the move-soft takes).
    case castle
    case win
    /// A game that ends with nobody winning: a draw.
    case gameOver = "game-over"
    /// A low, ominous toll when the person loses: mated, resigned or out of time.
    case defeat
    /// A short video-game "level clear" theme, when a person wins.
    case victory
    /// The chime as the app opens.
    case welcome

    /// Sets how the sounds sit against each other. The soft tocks of a move, capture or castle
    /// sit well under full volume, and check (its file raised 3 dB) above them. The longer cues' files are all made the same loudness
    /// (-16 LUFS, scripts/make_sounds.py), so these alone place them: the endings only a
    /// little above the knocks, so the end of a game is never a jolt, and the welcome softest.
    var volume: Float {
        switch self {
        case .clockMove: return 0.75
        case .move, .capture, .castle, .rivalMove, .rivalCapture: return 0.6
        case .select: return 0.3
        case .check: return 1.0
        case .win: return 0.7
        case .gameOver: return 0.6
        case .defeat: return 0.6
        case .victory: return 0.7
        case .welcome: return 0.4
        }
    }

    /// The longer cues: the endings and the welcome. They fade out when something new begins.
    var isLong: Bool {
        switch self {
        case .win, .gameOver, .defeat, .victory, .welcome: return true
        case .move, .clockMove, .rivalMove, .rivalCapture, .select, .capture, .check, .castle: return false
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

    /// Each sound's takes (a knock may have several: move.mp3, move-2.mp3, ...), and for each
    /// take two players for a knock, used in turn, so a piece landing never cuts off the one
    /// before it; one for each longer cue.
    private var players: [GameSound: [[AVAudioPlayer]]] = [:]
    private var nextPlayer: [GameSound: Int] = [:]
    /// The take each knock played last, so the next one is a different take.
    private var lastTake: [GameSound: Int] = [:]
    /// Longer cues fading out, to be stopped once they are silent.
    private var fading: Set<GameSound> = []

    private init() {
        // Ambient: respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        // A move and a capture play the soft tocks (`takes(of:)`), so their own older takes
        // are never heard: leaving them out spares two dozen players at launch.
        for sound in GameSound.allCases where sound != .move && sound != .capture {
            if let takes = Self.load(sound, named: sound.rawValue) { players[sound] = takes }
        }
    }

    /// The takes of `sound` in the bundle as `name`.mp3, then `name`-2.mp3 to `name`-6.mp3 for
    /// a knock: two players each for a knock, one for a longer cue.
    private static func load(_ sound: GameSound, named base: String) -> [[AVAudioPlayer]]? {
        let names = [base] + (sound.isLong ? [] : (2...6).map { "\(base)-\($0)" })
        let takes: [[AVAudioPlayer]] = names.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
            let pool = (0..<(sound.isLong ? 1 : 2)).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            for player in pool {
                player.volume = sound.volume
                player.prepareToPlay()
            }
            return pool.isEmpty ? nil : pool
        }
        return takes.isEmpty ? nil : takes
    }

    /// The takes to play for `sound`. A move and a capture share the rival's soft tocks, so
    /// every piece set sounds the same, quiet way (the per-set takes squeaked and rang).
    private func takes(of sound: GameSound) -> [[AVAudioPlayer]]? {
        switch sound {
        case .move: return players[.rivalMove]
        case .capture: return players[.rivalCapture]
        default: return players[sound]
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
        guard isEnabled, let takes = takes(of: sound), !takes.isEmpty else { return }
        var take = Int.random(in: 0..<takes.count)
        if takes.count > 1, take == lastTake[sound] { take = (take + 1) % takes.count }
        lastTake[sound] = take
        let pool = takes[take]
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
            for player in (players[sound] ?? []).joined() where player.isPlaying {
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
                for player in (self.players[sound] ?? []).joined() {
                    player.stop()
                    player.currentTime = 0
                    player.volume = sound.volume
                }
                self.fading.remove(sound)
            }
        }
    }
}
