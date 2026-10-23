import AVFoundation
import Foundation
import Speech

/// Why listening couldn't start. The session offers typing instead.
enum SpeechListenerError: Error, Equatable {
    /// The player said no to the microphone or to speech recognition.
    case notAllowed
    /// No recognizer for English on this device right now.
    case noRecognizer
    /// No microphone, or one that gives no sound.
    case noMicrophone
    /// The audio system wouldn't let the app record (a call, another app).
    case audioBusy
}

/// Hears the player on the device with Apple's speech recognizer, primed with chess words, and
/// reports how loud they are for the listening ring. Every failure is a thrown error or
/// `isAvailable == false`, never a crash.
@MainActor
final class SpeechListener: TalkListener {
    private struct SavedAudio {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// The audio setup before listening, put back afterwards (the game's quiet effects, or a lesson's).
    private var savedAudio: SavedAudio?
    private var onText: (@MainActor (String) -> Void)?
    private var onLevel: (@MainActor (Double) -> Void)?
    /// After the button comes up, the recognizer gets a moment for the last words.
    private var finishing: Task<Void, Never>?
    /// Counts listens, so a late result from an earlier one is never mistaken for this one.
    private var generation = 0
    /// Words from stretches of speech the recognizer has closed, and everything heard so far.
    private var committed = ""
    private var heard = ""
    private var smoothedLevel: Double = 0
    /// A listen found no working microphone: speech isn't offered again on this device for now.
    private var microphoneMissing = false

    /// How long the recognizer may take to finish the last words once the button is up.
    static let lastWordsTime: Duration = .milliseconds(1500)

    init() {}

    // MARK: TalkListener

    var isAvailable: Bool {
        guard Self.hasUsageDescriptions, !microphoneMissing, !permissionRefused else { return false }
        guard AVAudioSession.sharedInstance().isInputAvailable else { return false }
        guard let recognizer = currentRecognizer() else { return false }
        return recognizer.isAvailable
    }

    func requestPermission() async -> Bool {
        // Without the reasons in Info.plist the system would end the app rather than ask.
        guard Self.hasUsageDescriptions else { return false }
        guard await Self.askForSpeechRecognition() else { return false }
        return await Self.askForMicrophone()
    }

    func start(onText: @escaping @MainActor (String) -> Void, onLevel: @escaping @MainActor (Double) -> Void) throws {
        // Whatever ran before ends first, its last words included.
        cancel()
        guard Self.hasUsageDescriptions, !permissionRefused else { throw SpeechListenerError.notAllowed }
        guard let recognizer = currentRecognizer(), recognizer.isAvailable else { throw SpeechListenerError.noRecognizer }
        let audio = AVAudioSession.sharedInstance()
        guard audio.isInputAvailable else {
            microphoneMissing = true
            throw SpeechListenerError.noMicrophone
        }

        savedAudio = SavedAudio(category: audio.category, mode: audio.mode, options: audio.categoryOptions)
        do {
            try Self.setUpForListening(audio)
        } catch {
            restoreAudio()
            throw SpeechListenerError.audioBusy
        }

        // The microphone's own format, read once the session records. A format with no sound
        // (no microphone, a route that is changing) would make the tap throw and end the app.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            restoreAudio()
            microphoneMissing = true
            throw SpeechListenerError.noMicrophone
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Self.chessWords
        // On the device when it can: faster, private, and no limit on how long the player talks.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        generation += 1
        let current = generation
        let report: @Sendable (Float) -> Void = { [weak self] rms in
            let level = SpeechListener.level(rms: rms)
            Task { @MainActor in self?.heardLevel(level, generation: current) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: SpeechListener.tap(feeding: request, report: report))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            restoreAudio()
            throw SpeechListenerError.audioBusy
        }

        committed = ""
        heard = ""
        smoothedLevel = 0
        self.onText = onText
        self.onLevel = onLevel
        audioEngine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request,
                                          resultHandler: SpeechListener.resultHandler(for: self, generation: current))
    }

    func stop() -> String {
        let words = heard
        guard audioEngine != nil else { return words }
        stopAudio()
        request?.endAudio()
        onLevel = nil
        if task == nil {
            endRecognition()
        } else {
            // The final words arrive through onText; past the wait, give up on them.
            let current = generation
            finishing?.cancel()
            finishing = Task { [weak self] in
                try? await Task.sleep(for: SpeechListener.lastWordsTime)
                guard !Task.isCancelled else { return }
                self?.endRecognition(ifStill: current)
            }
        }
        return words
    }

    func cancel() {
        stopAudio()
        endRecognition()
    }

    // MARK: Results

    private func recognized(_ text: String?, endsStretch: Bool, isFinal: Bool, failed: Bool, generation current: Int) {
        guard current == generation else { return }
        if let text, !text.isEmpty {
            let merged = Self.merge(committed: committed, latest: text)
            if endsStretch { committed = merged }
            if merged != heard {
                heard = merged
                onText?(merged)
            }
        }
        if isFinal || failed {
            // Nothing more comes from this task. While the button is still down the microphone
            // stays on (the ring keeps moving, and what was heard is kept); once it is up, it ends.
            task = nil
            if audioEngine == nil { endRecognition() }
        }
    }

    private func heardLevel(_ value: Double, generation current: Int) {
        guard current == generation, let onLevel else { return }
        // Quick to rise, slower to fall, so the ring breathes with the voice instead of flickering.
        let rate = value > smoothedLevel ? 0.6 : 0.2
        smoothedLevel += (value - smoothedLevel) * rate
        onLevel(smoothedLevel)
    }

    /// The words so far, when the recognizer may start afresh after a pause (it does on some
    /// systems): what it already closed, then what it hears now, unless the new words begin
    /// like the old ones, which means it kept everything.
    nonisolated static func merge(committed: String, latest: String) -> String {
        let old = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty else { return new }
        guard !new.isEmpty else { return old }
        let oldWords = words(old)
        let newWords = words(new)
        let lead = min(2, oldWords.count)
        if newWords.count >= lead, Array(newWords.prefix(lead)) == Array(oldWords.prefix(lead)) {
            return new
        }
        return old + " " + new
    }

    private nonisolated static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Loudness from 0 to 1: a quiet room near 0, a voice close to the phone near the top.
    nonisolated static func level(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(1, max(0, (decibels + 55) / 40))
    }

    /// The root-mean-square of the first channel.
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        return (sum / Float(count)).squareRoot()
    }

    // Built outside the main actor: the tap runs on the audio thread, and the recognizer calls back
    // on its own queue. Both only hand values to the main actor.

    private nonisolated static func tap(feeding request: SFSpeechAudioBufferRecognitionRequest,
                                        report: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            request.append(buffer)
            report(SpeechListener.rms(of: buffer))
        }
    }

    private nonisolated static func resultHandler(for listener: SpeechListener, generation: Int)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        return { [weak listener] result, error in
            let text = result?.bestTranscription.formattedString
            let endsStretch = result?.speechRecognitionMetadata != nil
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                listener?.recognized(text, endsStretch: endsStretch, isFinal: isFinal, failed: failed,
                                     generation: generation)
            }
        }
    }

    // MARK: Tearing down

    private func stopAudio() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }
        smoothedLevel = 0
        restoreAudio()
    }

    /// Ends the recognition: no more callbacks after this.
    private func endRecognition() {
        generation += 1
        finishing?.cancel()
        finishing = nil
        task?.cancel()
        task = nil
        request = nil
        onText = nil
        onLevel = nil
    }

    private func endRecognition(ifStill current: Int) {
        guard current == generation else { return }
        endRecognition()
    }

    // MARK: Audio

    /// Recording, with other audio turned down, and anything played meanwhile on the speaker
    /// (or the headphones) rather than the earpiece.
    private static func setUpForListening(_ audio: AVAudioSession) throws {
        let options: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        do {
            try audio.setCategory(.playAndRecord, mode: .measurement, options: options)
        } catch {
            try audio.setCategory(.playAndRecord, mode: .default, options: options)
        }
        try audio.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func restoreAudio() {
        guard let saved = savedAudio else { return }
        savedAudio = nil
        let audio = AVAudioSession.sharedInstance()
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
        try? audio.setCategory(saved.category, mode: saved.mode, options: saved.options)
    }

    // MARK: Permission

    /// Denied or restricted, in Settings or by the device's owner. Not yet asked counts as allowed.
    private var permissionRefused: Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return true
        default:
            break
        }
        return AVAudioApplication.shared.recordPermission == .denied
    }

    private static var hasUsageDescriptions: Bool {
        let info = Bundle.main
        return info.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
            && info.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
    }

    private nonisolated static func askForSpeechRecognition() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            break
        default:
            return false
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func askForMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            break
        default:
            return false
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: Recognizer

    private func currentRecognizer() -> SFSpeechRecognizer? {
        if let recognizer { return recognizer }
        let made = Self.makeRecognizer()
        recognizer = made
        return made
    }

    /// The device's own English when it is set to English (British, Indian…), American English otherwise.
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        if Locale.current.language.languageCode?.identifier == "en", let recognizer = SFSpeechRecognizer() {
            return recognizer
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Words a player uses about a position, so "knight" isn't heard as "night" and "h6" as "age six".
    private static let chessWords: [String] = {
        var words = ["knight", "bishop", "rook", "queen", "king", "pawn", "castle", "castles", "castling",
                     "kingside", "queenside", "check", "checkmate", "mate", "takes", "captures", "fork",
                     "pin", "pinned", "skewer", "en passant", "threat", "threatens", "hanging", "defend",
                     "defends", "attack", "attacks", "trade", "promote", "discovered check", "back rank"]
        for file in "abcdefgh" {
            for rank in 1...8 {
                words.append("\(file)\(rank)")
            }
        }
        return words
    }()
}
