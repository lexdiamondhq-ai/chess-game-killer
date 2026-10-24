import AVFoundation
import CryptoKit
import Foundation

/// The coach's voice. Plays the line the picked coach recorded for a piece of text (made with
/// ElevenLabs by scripts/training/make_narration.py, named by the coach and a hash of the
/// text) and falls back to the device's own voice for anything not recorded.
@MainActor
final class CoachVoice: NSObject {
    static let shared = CoachVoice()

    /// The speaker button in lessons. Captions always show.
    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "coachVoiceMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "coachVoiceMuted") }
    }

    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var waiting: CheckedContinuation<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        // A call, Siri or an alarm pauses the player and the synthesizer without a
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

    /// Talking right now: a recording or the device's voice.
    var isSpeaking: Bool { player?.isPlaying == true || synthesizer.isSpeaking }

    /// Says a line and returns when it's finished, stopped or cancelled.
    /// Muted, it waits about as long as reading the line takes.
    func say(_ text: String) async {
        stop()
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !Task.isCancelled else { return }
        if isMuted {
            try? await Task.sleep(for: Self.readingTime(line))
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting = continuation
                if !play(recordingFor: line) {
                    speak(line)
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
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        utterance = nil
        finish()
    }

    /// Lessons play like videos: out loud even with the ring switch on silent,
    /// with other audio turned down while the coach talks.
    func beginLesson() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Back to the game's quiet sound effects, which respect the silent switch.
    func endLesson() {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient, options: [.mixWithOthers])
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

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let coach = Coach.current
        utterance.voice = Self.deviceVoice(for: coach)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.pitchMultiplier = coach == .leo ? 0.95 : 1.02
        utterance.postUtteranceDelay = 0.1
        self.utterance = utterance
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    private func finish() {
        let continuation = waiting
        waiting = nil
        continuation?.resume()
    }

    /// The nicest English voice on the device for the coach: a man's for Leo (American first),
    /// a woman's for Vera (American first).
    private static func deviceVoice(for coach: Coach) -> AVSpeechSynthesisVoice? {
        if let voice = deviceVoices[coach] { return voice }
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let gender: AVSpeechSynthesisVoiceGender = coach == .leo ? .male : .female
        let first = "en-US"
        let matching = english.filter { $0.gender == gender }
        let ranked = matching.filter { $0.language == first } + matching.filter { $0.language != first }
        let voice = ranked.first { $0.quality == .premium }
            ?? ranked.first { $0.quality == .enhanced }
            ?? ranked.first
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: first)
        deviceVoices[coach] = voice
        return voice
    }

    private static var deviceVoices: [Coach: AVSpeechSynthesisVoice] = [:]

    fileprivate func playerFinished(_ finished: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == finished else { return }
        self.player = nil
        finish()
    }

    fileprivate func speechFinished(_ finished: ObjectIdentifier) {
        guard let utterance, ObjectIdentifier(utterance) == finished else { return }
        self.utterance = nil
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

extension CoachVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.speechFinished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.speechFinished(id) }
    }
}
