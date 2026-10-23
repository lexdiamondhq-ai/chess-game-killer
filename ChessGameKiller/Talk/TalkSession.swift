import ChessKit
import Foundation
import Observation

// Talk It Through, for one position: Stockfish works out its numbers while the player talks (or
// types); the words and the numbers go to Leo's server, whose verdicts and answer stream back and
// are shown and spoken. The panel is built against this surface.

/// Sends the player's words and Stockfish's numbers to Leo's server and streams the answer.
protocol TalkTransport: Sendable {
    func talk(_ request: TalkRequest) -> AsyncThrowingStream<TalkEvent, Error>
}

/// Turns the player's speech into text, on the device.
@MainActor
protocol TalkListener: AnyObject {
    /// A recognizer exists for the player's language and the device can run it.
    var isAvailable: Bool { get }
    /// Asks for the microphone and speech recognition the first time; true when both are allowed.
    func requestPermission() async -> Bool
    /// Starts hearing. `onText` gets the words so far, `onLevel` the loudness from 0 to 1.
    func start(onText: @escaping @MainActor (String) -> Void, onLevel: @escaping @MainActor (Double) -> Void) throws
    /// Stops and returns everything heard.
    func stop() -> String
    /// Stops and throws away what was heard.
    func cancel()
}

/// Plays Leo's voice, or speaks with the device's voice when there's no recording.
@MainActor
protocol TalkSpeaker: AnyObject {
    /// Plays an MP3 and returns when it ends or is stopped.
    func play(mp3: Data) async
    /// Speaks with the device's voice and returns when done or stopped.
    func say(_ text: String) async
    func stop()
}

/// What Leo says aloud: his recording, or the words for the device's voice.
private enum TalkUtterance {
    case recording(Data)
    case words(String)
}

/// One "talk it through" for one position: listen (or type), send it to Leo, show and speak his answer.
@MainActor
@Observable
final class TalkSession: Identifiable {
    enum Phase: Equatable, Sendable {
        /// Waiting for the player: hold to talk, or type.
        case ready
        /// Hearing the player; `transcript` grows as they speak.
        case listening
        /// The keyboard is up.
        case typing
        /// Sent, waiting for Leo. `check` arrives first, then `answer`.
        case checking
        /// Leo has answered. He may still be speaking (`isSpeaking`).
        case answered
        /// It didn't work; `problem` says why in plain words.
        case failed
    }

    let id = UUID()
    /// The position. The player is the side to move.
    let fen: String
    let player: Piece.Color
    let context: TalkContext
    /// Leo may name the best move.
    let reveal: Bool
    /// The opponent's last move in engine notation, for "he just…" claims.
    let lastMove: String?

    private(set) var phase: Phase = .ready
    /// What the player said (growing while they speak) or typed and sent.
    private(set) var transcript = ""
    /// The text field while typing.
    var draft = ""
    /// The microphone's loudness from 0 to 1, for the listening ring.
    private(set) var level: Double = 0
    /// Leo's verdicts, once they arrive.
    private(set) var check: TalkCheck?
    /// Leo's words, once they arrive.
    private(set) var answer: String?
    private(set) var isSpeaking = false
    /// Stockfish's numbers are worked out (or the engine had none to give), so sending won't wait
    /// for them. They're worked out while the player talks.
    private(set) var factsReady = false
    /// Why it failed, in plain words, like "Leo needs the internet to check your plan."
    private(set) var problem: String?
    /// False when speech can't be used (no permission, no recognizer): the panel offers typing only.
    private(set) var canListen = true
    /// The verdict whose squares the board shows. Nil shows the move.
    var focus: TalkFocus?

    /// How long a send waits for Stockfish's numbers that aren't ready yet before going without them.
    @ObservationIgnored var factsWait: Duration = .seconds(4)
    /// How long a spoken send waits for the recognizer's last words once the button is up.
    @ObservationIgnored var lastWordsGrace: Duration = .milliseconds(500)

    private let engine: ChessEngine
    private let api: TalkTransport
    private let listener: TalkListener
    private let speaker: TalkSpeaker

    @ObservationIgnored private var facts: TalkFacts?
    @ObservationIgnored private var factsDone = false
    @ObservationIgnored private var factsTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    /// The player allowed the microphone and speech recognition (asked on the first hold).
    @ObservationIgnored private var hasPermission = false
    /// The talk button is held: when permission comes while it still is, listening starts.
    @ObservationIgnored private var buttonDown = false
    @ObservationIgnored private var isListening = false
    /// Count listens and sends, so a late callback from an earlier one changes nothing.
    @ObservationIgnored private var listenID = 0
    @ObservationIgnored private var requestID = 0
    /// Between the button coming up and the request going out, the recognizer's last words still count.
    @ObservationIgnored private var acceptsLateWords = false
    /// Leo's voice was asked for (the coach isn't muted).
    @ObservationIgnored private var speaksAloud = true
    /// This go's answer was spoken, or the player quieted Leo: nothing more is said.
    @ObservationIgnored private var hasSpoken = false
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private var isClosed = false

    init(fen: String, player: Piece.Color, context: TalkContext = .game, reveal: Bool = false,
         lastMove: String? = nil, engine: ChessEngine = StockfishEngine.shared, api: TalkTransport? = nil,
         listener: TalkListener? = nil, speaker: TalkSpeaker? = nil) {
        self.fen = fen
        self.player = player
        self.context = context
        self.reveal = reveal
        self.lastMove = lastMove
        self.engine = engine
        // The live pieces start nothing until asked, so a preview can make them freely.
        if let api {
            self.api = api
        } else {
            self.api = TalkAPI.live
        }
        if let listener {
            self.listener = listener
        } else {
            self.listener = SpeechListener()
        }
        if let speaker {
            self.speaker = speaker
        } else {
            self.speaker = LeoSpeaker()
        }
    }

    /// The panel opened: start Stockfish's numbers, and see whether speech can be used.
    func open() {
        guard !isOpen, !isClosed else { return }
        isOpen = true
        // Only what is already known: the permission prompt waits for the first hold.
        canListen = listener.isAvailable
        startFacts()
    }

    /// The talk button went down: ask for permission the first time, then listen.
    func beginListening() {
        guard !isClosed else { return }
        switch phase {
        case .listening, .checking:
            return
        case .answered, .failed:
            resetGo()
        case .ready, .typing:
            break
        }
        guard canListen else {
            phase = .typing
            return
        }
        buttonDown = true
        if hasPermission {
            startListener()
            return
        }
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            guard let self else { return }
            let allowed = await self.listener.requestPermission()
            self.permissionAnswered(allowed)
        }
    }

    /// The talk button came up: stop listening and send what was heard (nothing heard: back to ready).
    func endListening() {
        buttonDown = false
        guard !isClosed, phase == .listening else { return }
        let spoken = Self.tidy(listener.stop())
        isListening = false
        level = 0
        let words = spoken.isEmpty ? Self.tidy(transcript) : spoken
        guard !words.isEmpty else {
            listener.cancel()
            listenID += 1
            transcript = ""
            phase = .ready
            return
        }
        transcript = words
        send(typed: false)
    }

    /// Stop listening without sending.
    func cancelListening() {
        buttonDown = false
        guard !isClosed, phase == .listening else { return }
        stopListeningQuietly()
        transcript = ""
        phase = .ready
    }

    /// Show the text field instead of listening.
    func beginTyping() {
        guard !isClosed else { return }
        // What was heard, or what didn't go through, is there to fix rather than type again.
        var carried = ""
        switch phase {
        case .checking:
            return
        case .ready, .typing:
            break
        case .listening:
            carried = transcript
            stopListeningQuietly()
            transcript = ""
        case .failed:
            carried = transcript
            resetGo()
        case .answered:
            resetGo()
        }
        buttonDown = false
        if draft.isEmpty { draft = carried }
        phase = .typing
    }

    /// Send what was typed.
    func sendDraft() {
        guard !isClosed else { return }
        let words = Self.tidy(draft)
        guard !words.isEmpty else { return }
        switch phase {
        case .checking:
            return
        case .listening:
            stopListeningQuietly()
        case .answered, .failed:
            resetGo()
        case .ready, .typing:
            break
        }
        draft = ""
        transcript = words
        send(typed: true)
    }

    /// Back to ready for another go. Stockfish's numbers are kept.
    func talkAgain() {
        guard !isClosed else { return }
        resetGo()
    }

    /// Quiet Leo now.
    func stopSpeaking() {
        hasSpoken = true
        speechTask?.cancel()
        speechTask = nil
        speaker.stop()
        isSpeaking = false
    }

    /// The panel closed: stop listening, speaking, the engine and the request.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        buttonDown = false
        acceptsLateWords = false
        listenID += 1
        requestID += 1
        factsTask?.cancel()
        factsTask = nil
        permissionTask?.cancel()
        permissionTask = nil
        requestTask?.cancel()
        requestTask = nil
        speechTask?.cancel()
        speechTask = nil
        listener.cancel()
        isListening = false
        speaker.stop()
        isSpeaking = false
        level = 0
    }

    /// A session frozen in one state for previews and snapshot tests: no engine, network or microphone.
    static func preview(fen: String, player: Piece.Color, phase: Phase, transcript: String = "",
                        check: TalkCheck? = nil, answer: String? = nil, level: Double = 0.4,
                        canListen: Bool = true, problem: String? = nil) -> TalkSession {
        let session = TalkSession(fen: fen, player: player)
        session.phase = phase
        session.transcript = transcript
        session.check = check
        session.answer = answer
        session.level = level
        session.factsReady = true
        session.canListen = canListen
        session.problem = problem
        // Already open with its numbers in: the panel's open() starts no engine and asks nothing.
        session.isOpen = true
        session.factsDone = true
        return session
    }

    // MARK: Stockfish's numbers

    private func startFacts() {
        guard factsTask == nil, !factsDone, !isClosed else { return }
        let fen = self.fen
        let engine = self.engine
        factsTask = Task { [weak self] in
            let sheet = await TalkFactSheet.compute(fen: fen, engine: engine)
            guard let self, !Task.isCancelled, !self.isClosed else { return }
            self.facts = sheet
            self.factsDone = true
            self.factsReady = true
            self.factsTask = nil
        }
    }

    // MARK: Listening

    private func permissionAnswered(_ allowed: Bool) {
        permissionTask = nil
        guard !isClosed else { return }
        hasPermission = allowed
        guard allowed else {
            // No fuss: the keyboard is the way in now.
            canListen = false
            buttonDown = false
            if phase == .ready { phase = .typing }
            return
        }
        // The prompt took the press; listen only if the button is still held.
        if buttonDown, phase == .ready || phase == .typing {
            startListener()
        }
    }

    private func startListener() {
        listenID += 1
        let current = listenID
        transcript = ""
        level = 0
        do {
            try listener.start(onText: { [weak self] text in
                self?.heard(text, listen: current)
            }, onLevel: { [weak self] value in
                self?.heardLevel(value, listen: current)
            })
        } catch {
            // No microphone, a busy audio system, no recognizer: typing works anyway.
            isListening = false
            buttonDown = false
            canListen = listener.isAvailable
            phase = .typing
            return
        }
        isListening = true
        phase = .listening
    }

    private func heard(_ text: String, listen: Int) {
        guard !isClosed, listen == listenID else { return }
        switch phase {
        case .listening:
            transcript = text
        case .checking where acceptsLateWords:
            let words = Self.tidy(text)
            if !words.isEmpty { transcript = words }
        default:
            break
        }
    }

    private func heardLevel(_ value: Double, listen: Int) {
        guard !isClosed, listen == listenID, phase == .listening else { return }
        level = min(1, max(0, value))
    }

    private func stopListeningQuietly() {
        listener.cancel()
        isListening = false
        listenID += 1
        level = 0
    }

    /// Ends whatever this go was doing and clears it, for another go.
    private func resetGo() {
        requestID += 1
        requestTask?.cancel()
        requestTask = nil
        if isListening || acceptsLateWords {
            listener.cancel()
        }
        isListening = false
        acceptsLateWords = false
        listenID += 1
        speechTask?.cancel()
        speechTask = nil
        speaker.stop()
        isSpeaking = false
        hasSpoken = false
        phase = .ready
        transcript = ""
        check = nil
        answer = nil
        problem = nil
        focus = nil
        level = 0
    }

    // MARK: Asking Leo

    private func send(typed: Bool) {
        requestTask?.cancel()
        requestID += 1
        let id = requestID
        acceptsLateWords = !typed
        hasSpoken = false
        speaksAloud = true
        check = nil
        answer = nil
        problem = nil
        focus = nil
        level = 0
        phase = .checking
        requestTask = Task { [weak self] in
            await self?.run(typed: typed, id: id)
        }
    }

    private func isCurrent(_ id: Int) -> Bool {
        !Task.isCancelled && !isClosed && id == requestID
    }

    private func run(typed: Bool, id: Int) async {
        await waitBeforeSending(typed: typed)
        guard isCurrent(id) else { return }
        acceptsLateWords = false
        // The recognizer's last words are in, or too late to count: let it go.
        if !typed { listener.cancel() }
        let said = Self.clipped(transcript)
        guard !said.isEmpty else {
            phase = .ready
            return
        }
        let wantsVoice = !CoachVoice.shared.isMuted
        speaksAloud = wantsVoice
        let request = TalkRequest(fen: fen, said: said, typed: typed, reveal: reveal, context: context,
                                  lastMove: lastMove, voice: wantsVoice, facts: facts)

        var serverError: String?
        var failure: Error?
        do {
            // Done, or an error line, ends the answer, whether or not the stream stays open.
            streaming: for try await event in api.talk(request) {
                guard isCurrent(id) else { return }
                switch event {
                case .checked(let value):
                    check = value
                    focus = nil
                case .answer(let value):
                    let words = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !words.isEmpty { answer = words }
                case .voice(let value):
                    voiceArrived(value)
                case .done:
                    break streaming
                case .failed(let code):
                    serverError = code
                    break streaming
                }
            }
        } catch {
            failure = error
        }
        guard isCurrent(id) else { return }
        conclude(serverError: serverError, failure: failure)
    }

    /// Stockfish's numbers, when they aren't ready yet, get a few seconds more (then the request
    /// goes without them); a spoken plan also waits a moment for the recognizer's last words.
    private func waitBeforeSending(typed: Bool) async {
        if !factsDone { startFacts() }
        let start = ContinuousClock.now
        let wordsUntil = start + (typed ? Duration.zero : lastWordsGrace)
        let factsUntil = start + factsWait
        while !Task.isCancelled {
            let now = ContinuousClock.now
            let waitingForWords = now < wordsUntil
            let waitingForFacts = !factsDone && now < factsUntil
            guard waitingForWords || waitingForFacts else { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func voiceArrived(_ voice: TalkVoice) {
        if let audio = voice.audio, !audio.isEmpty {
            speak(.recording(audio))
        } else if let answer {
            speak(.words(answer))
        }
    }

    /// The stream ended. Leo's verdicts stand once they're in, even when the rest didn't come.
    private func conclude(serverError: String?, failure: Error?) {
        requestTask = nil
        if let check {
            if answer == nil { answer = Self.fallbackAnswer(for: check) }
            phase = .answered
            // No voice line came: the device's voice says it.
            if let answer { speak(.words(answer)) }
            return
        }
        // No verdicts: nothing to show, so nothing of Leo's either.
        if isSpeaking { stopSpeaking() }
        answer = nil
        if let serverError {
            problem = Self.problem(forCode: serverError)
        } else if let failure {
            problem = Self.problem(for: failure)
        } else {
            problem = Self.problem(forCode: "internal")
        }
        phase = .failed
    }

    private func speak(_ utterance: TalkUtterance) {
        guard speaksAloud, !hasSpoken, !isClosed else { return }
        hasSpoken = true
        isSpeaking = true
        let id = requestID
        speechTask = Task { [weak self] in
            guard let self else { return }
            switch utterance {
            case .recording(let data):
                await self.speaker.play(mp3: data)
            case .words(let text):
                await self.speaker.say(text)
            }
            guard !Task.isCancelled, !self.isClosed, self.requestID == id else { return }
            self.isSpeaking = false
            self.speechTask = nil
        }
    }

    // MARK: Words

    /// Plain words for a server error code.
    static func problem(forCode code: String) -> String {
        switch code {
        case "rate_limited":
            return "Leo needs a moment. Try again in a minute."
        case "daily_limit":
            return "Leo has checked a lot of plans today. Try again tomorrow."
        case "bad_request":
            return "Leo didn't catch that. Try again."
        default:
            return "Leo couldn't check that one. Try again."
        }
    }

    /// Plain words for an error on the way: anything that isn't the server's own is the network.
    static func problem(for error: Error) -> String {
        if let failure = error as? TalkFailure {
            switch failure {
            case .offline:
                return "Leo needs the internet to check your plan."
            case .server(let code):
                return problem(forCode: code)
            case .badResponse:
                return problem(forCode: "internal")
            }
        }
        if error is CancellationError { return problem(forCode: "internal") }
        return "Leo needs the internet to check your plan."
    }

    /// Something short to say when the verdicts came but Leo's own words didn't.
    static func fallbackAnswer(for check: TalkCheck) -> String {
        guard check.understood else { return "Tell me what you see on the board, and the move you want to play." }
        let judged = check.judgedCount
        let right = check.rightCount
        guard judged > 0 else { return "Here's what I checked." }
        if right == judged {
            switch judged {
            case 1: return "You're right about that."
            case 2: return "You're right about both."
            default: return "You're right about all \(judged)."
            }
        }
        if right == 0 {
            return judged == 1 ? "Not quite. Have a look at the board." : "Those don't hold up. Have a look at the board."
        }
        return "You got \(right) of \(judged) right. Have a look at the board."
    }

    static func tidy(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// At most 800 characters, as the server counts them (UTF-16), cut between characters.
    static func clipped(_ text: String) -> String {
        let words = tidy(text)
        guard words.utf16.count > 800 else { return words }
        var kept = ""
        var units = 0
        for character in words {
            let size = character.utf16.count
            if units + size > 800 { break }
            kept.append(character)
            units += size
        }
        return tidy(kept)
    }
}
