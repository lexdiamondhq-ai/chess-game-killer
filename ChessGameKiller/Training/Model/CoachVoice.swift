import AVFoundation
import CryptoKit
import Foundation

/// The coach's voice. Plays the line the picked coach recorded for a piece of text (made with
/// ElevenLabs by scripts/training/make_narration.py, named by the coach and a hash of the
/// text). A line with no recording is not read by the iPhone's own voice, which sounds robotic
/// next to the coach's: the coach stays quiet and the words on screen get about as long as reading
/// them takes, as when muted.
@MainActor
final class CoachVoice: NSObject {
    static let shared = CoachVoice()

    /// The speaker button in lessons. Captions always show.
    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "coachVoiceMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "coachVoiceMuted") }
    }

    /// The "Speak on silent" switch in Settings. Off (the default), the coach goes quiet when the
    /// ring switch is on silent, like the game's own sounds; on, lessons play like videos, out
    /// loud whatever the switch says.
    static let speaksOnSilentKey = "coachSpeaksOnSilent"

    var speaksOnSilent: Bool {
        get { UserDefaults.standard.bool(forKey: Self.speaksOnSilentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.speaksOnSilentKey) }
    }

    /// The lesson audio is set up: a lesson, a highlight reel or Leo's reply is playing through it.
    private(set) var lessonAudioActive = false

    private var player: AVAudioPlayer?
    private var waiting: CheckedContinuation<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        // A call, Siri or an alarm pauses the player without a
        // finish callback. Stop instead, so a pending `say` returns and the lesson
        // carries on with captions rather than sitting on the same step.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    /// The recorded file for a line: the coach's prefix ("nar-" for Leo, "vera-" for Vera)
    /// and the first 12 hex digits of its SHA-1.
    static func fileName(for text: String, coach: Coach = .leo) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return coach.filePrefix + hex.prefix(12)
    }

    static func recording(for text: String, coach: Coach) -> URL? {
        Bundle.main.url(forResource: fileName(for: text, coach: coach), withExtension: "mp3")
    }

    static func hasRecording(for text: String, coach: Coach = .leo) -> Bool {
        recording(for: text, coach: coach) != nil
    }

    /// Playing a recording right now.
    var isSpeaking: Bool { player?.isPlaying == true }

    /// Says a line and returns when it's finished, stopped or cancelled.
    /// Muted, it waits about as long as reading the line takes.
    func say(_ text: String) async {
        stop()
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !Task.isCancelled else { return }
        if isMuted || !Self.hasRecording(for: line, coach: Coach.current) {
            try? await Task.sleep(for: Self.readingTime(line))
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting = continuation
                if !play(recordingFor: line) {
                    finish()
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    /// Stops talking now. A `say` in progress returns.
    func stop() {
        player?.stop()
        player = nil
        finish()
    }

    /// The audio a lesson wants: other audio turned down while the coach talks, and out loud
    /// with the ring switch on silent only when the player asked for that in Settings.
    nonisolated static func lessonAudio(speaksOnSilent: Bool) -> (category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        (speaksOnSilent ? .playback : .ambient, [.duckOthers])
    }

    /// Sets the audio up for the coach to talk: music and podcasts turn down while it does, and
    /// the ring switch is respected unless "Speak on silent" is on.
    func beginLesson() {
        let session = AVAudioSession.sharedInstance()
        let wanted = Self.lessonAudio(speaksOnSilent: speaksOnSilent)
        do {
            try session.setCategory(wanted.category, mode: .spokenAudio, options: wanted.options)
        } catch {
            // Should the system refuse that pairing, mixing with other audio is the next best.
            try? session.setCategory(wanted.category, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        lessonAudioActive = true
    }

    /// Back to the game's quiet sound effects.
    func endLesson() {
        stop()
        // Closing a lesson can call this twice (its Close, then the screen going away): only the
        // first hands the sound back, so the second can't silence the music Home has just started.
        guard lessonAudioActive else { return }
        lessonAudioActive = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        Self.pickUpMusic()
    }

    /// Handing the sound back can stop the app's own music (a rival's theme, Home's strings)
    /// though its screen is still up: a moment later, whichever should be playing starts again.
    static func pickUpMusic() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            RivalTheme.shared.pickUp()
            HomeMusic.shared.pickUp()
        }
    }

    /// Roughly how long it takes to read a line: about three words a second.
    static func readingTime(_ text: String) -> Duration {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        return .milliseconds(max(1500, 700 + words * 330))
    }

    // MARK: Private

    private func play(recordingFor text: String) -> Bool {
        guard
            let url = Self.recording(for: text, coach: Coach.current),
            let player = try? AVAudioPlayer(contentsOf: url)
        else { return false }
        player.delegate = self
        self.player = player
        return player.play()
    }

    private func finish() {
        let continuation = waiting
        waiting = nil
        continuation?.resume()
    }

    fileprivate func playerFinished(_ finished: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == finished else { return }
        self.player = nil
        finish()
    }
}

extension CoachVoice: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id) }
    }
}
