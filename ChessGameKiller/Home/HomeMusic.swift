import AVFoundation
import Observation

/// Soft strings under the stage home (Alex picked "The Long Winter", 2026-11-07). Plays only
/// while Home shows, fades in and out, loops, and follows the ring switch (it never plays on
/// silent). The music button on Home turns it off for good, until it's turned back on.
/// Nothing shows until a track is bundled: Sounds/music-home.mp3.
@MainActor
@Observable
final class HomeMusic {
    static let shared = HomeMusic()
    static let key = "homeMusic"
    static let track = "music-home"
    /// Quiet: it sits under everything.
    static let volume: Float = 0.32

    private(set) var on: Bool
    let available: Bool
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var showing = false
    /// Another screen covers Home (training, lessons, Leo, puzzles, Analyze): the music rests.
    @ObservationIgnored private var covered = false

    private init() {
        on = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
        available = Bundle.main.url(forResource: Self.track, withExtension: "mp3") != nil
    }

    private var playing: Bool { showing && on && !covered }

    func homeAppeared() {
        showing = true
        if playing { start() }
    }

    /// A screen opened over Home, or closed again. Screens where Leo talks are quiet.
    func setCovered(_ covered: Bool) {
        guard covered != self.covered else { return }
        self.covered = covered
        if playing { start() } else { stop() }
    }

    func homeDisappeared() {
        showing = false
        stop()
    }

    func toggle() {
        on.toggle()
        UserDefaults.standard.set(on, forKey: Self.key)
        if playing { start() } else { stop() }
    }

    private func start() {
        guard available, !Welcome.isUnderTest else { return }
        if player == nil, let url = Bundle.main.url(forResource: Self.track, withExtension: "mp3") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.prepareToPlay()
        }
        guard let player else { return }
        // Ambient: mixes with other audio and stays quiet on silent.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(Self.volume, fadeDuration: 2.5)
    }

    private func stop() {
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.8)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard let self, !self.playing else { return }
            self.player?.pause()
        }
    }
}
