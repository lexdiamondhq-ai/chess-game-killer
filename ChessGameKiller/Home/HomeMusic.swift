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
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// For the tap tests only (`-musicProbe YES`): whether the strings are really going, read
    /// from the track moving on, since a player whose sound was taken away can still say it plays.
    static let probes = UserDefaults.standard.bool(forKey: "musicProbe")
    private(set) var heard = false
    @ObservationIgnored private var lastTime: TimeInterval = -1

    private init() {
        on = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
        available = Bundle.main.url(forResource: Self.track, withExtension: "mp3") != nil
        watchTheSound()
        if Self.probes { probe() }
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

    /// The sound was handed back after Leo spoke or listened, which can stop the music while
    /// Home is showing: it picks up again.
    ///
    /// Handing the sound back silences the strings, but the player can go on saying it plays,
    /// so it is started again rather than asked. That was the quiet Home after Today's training
    /// (Alex, 2026-11-28): the lesson gave the sound back just after Home had come back and
    /// started its music, and the old check believed the player.
    func pickUp() {
        guard playing else { return }
        player?.pause()
        start()
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
        // Ambient: mixes with other audio and stays quiet on silent. The sound may have been
        // handed back by Leo or a film, so it is taken again.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
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

    /// A call, Siri or an alarm stops the music without a word: it comes back when they end.
    /// Should the phone's sound restart under the app, the player is made again.
    private func watchTheSound() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            MainActor.assumeIsolated { HomeMusic.shared.pickUp() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { _ in
            MainActor.assumeIsolated {
                HomeMusic.shared.player = nil
                HomeMusic.shared.pickUp()
            }
        })
    }

    /// Twice a second, whether the track has moved on since the last look.
    private func probe() {
        Task { @MainActor [weak self] in
            while let self {
                let now = self.player?.currentTime ?? -1
                let moving = self.player?.isPlaying == true && now >= 0 && now != self.lastTime
                if moving != self.heard { self.heard = moving }
                self.lastTime = now
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
