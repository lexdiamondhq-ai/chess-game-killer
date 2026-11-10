import Foundation
import Observation

/// Plays one game's deep review: asks the coach's server for it (or takes the one kept with the
/// game), then reads it part by part while the screen moves the board to each part's move.
@MainActor
@Observable
final class DeepReviewPlayer {
    enum Phase: Equatable {
        /// Asked, waiting for the coach to write it (about fifteen seconds).
        case loading
        case playing
        case paused
        /// The last part has been heard.
        case finished
        /// It didn't work; the words say why.
        case failed(String)
    }

    let game: SavedGame
    private(set) var phase: Phase = .loading
    private(set) var review: DeepReview?
    /// The part being read.
    private(set) var index = 0

    @ObservationIgnored private let transport: DeepReviewTransport
    @ObservationIgnored private let store: DeepReviewStore
    @ObservationIgnored private let speaker: TalkSpeaker
    /// Called once when a new review arrives (never for one kept with the game): the moment a use is counted.
    @ObservationIgnored private let onNewReview: () -> Void
    /// Recordings as they arrive, and the parts the server said it has no voice for.
    @ObservationIgnored private var voices: [Int: Data] = [:]
    @ObservationIgnored private var voiceless: Set<Int> = []
    /// No more voice lines are coming.
    @ObservationIgnored private var streamEnded = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// How long a part waits for its recording before the device's voice reads it instead.
    static let longestWaitForVoice: Duration = .seconds(10)
    /// The breath between two parts.
    @ObservationIgnored var gap: Duration = .milliseconds(350)
    /// When nothing was read aloud (the coach is muted), a part's words stay up long enough to read.
    @ObservationIgnored var holdsSilentParts = true

    init(game: SavedGame, transport: DeepReviewTransport = DeepReviewAPI.live, store: DeepReviewStore = .live,
         speaker: TalkSpeaker? = nil, onNewReview: @escaping () -> Void = {}) {
        self.game = game
        self.transport = transport
        self.store = store
        self.speaker = speaker ?? LeoSpeaker()
        self.onNewReview = onNewReview
    }

    var part: DeepReviewPart? {
        guard let review, review.parts.indices.contains(index) else { return nil }
        return review.parts[index]
    }

    var partCount: Int { review?.parts.count ?? 0 }

    /// Whose review it is: the one kept with the game stays its own coach's.
    var coach: Coach { review?.speaker ?? .current }

    /// Starts: the review kept with this game when there is one, otherwise a new one from the server.
    func start() {
        stopEverything()
        index = 0
        if let kept = store.review(for: game.id) {
            review = kept
            streamEnded = true
            phase = .playing
            read(from: 0)
            return
        }
        review = nil
        voices = [:]
        voiceless = []
        streamEnded = false
        phase = .loading
        guard let request = DeepReviewRequest(game: game, voice: !CoachVoice.shared.isMuted) else {
            phase = .failed("This game is too short for \(Coach.current.name) to review.")
            return
        }
        let events = transport.review(request)
        loading = Task { [weak self] in
            do {
                for try await event in events {
                    guard let self, !Task.isCancelled else { return }
                    self.take(event)
                }
                self?.streamFinished(with: nil)
            } catch {
                guard !Task.isCancelled else { return }
                self?.streamFinished(with: error)
            }
        }
    }

    func pause() {
        guard phase == .playing else { return }
        stopReading()
        phase = .paused
    }

    func resume() {
        guard review != nil, phase == .paused || phase == .finished else { return }
        if phase == .finished { index = 0 }
        phase = .playing
        read(from: index)
    }

    /// Moves to another part; it is read if the review was playing.
    func go(to part: Int) {
        guard let review, review.parts.indices.contains(part) else { return }
        switch phase {
        case .playing:
            read(from: part)
        case .paused, .finished:
            index = part
            phase = .paused
        case .loading, .failed:
            break
        }
    }

    /// Ends it for good: the request, the voice, everything.
    func close() {
        stopEverything()
    }

    // MARK: The stream

    private func take(_ event: DeepReviewEvent) {
        switch event {
        case .review(let fresh):
            guard review == nil else { return }
            review = fresh
            store.save(fresh, for: game.id)
            onNewReview()
            index = 0
            phase = .playing
            read(from: 0)
        case .voice(let part, let mp3):
            if let mp3 {
                voices[part] = mp3
                store.saveVoice(mp3, part: part, for: game.id)
            } else {
                voiceless.insert(part)
            }
        case .done:
            streamEnded = true
        case .failed(let code):
            streamFinished(with: TalkFailure.server(code))
        }
    }

    /// The stream is over. Without a review that's a failure; with one, the parts still
    /// missing a recording are read with the device's voice.
    private func streamFinished(with error: Error?) {
        streamEnded = true
        guard review == nil, phase == .loading else { return }
        phase = .failed(Self.problem(for: error))
    }

    /// Plain words for why there is no review.
    static func problem(for error: Error?) -> String {
        let name = Coach.current.name
        guard let failure = error as? TalkFailure else {
            return error == nil ? "\(name) couldn't review this one. Try again." : "\(name) needs the internet to review your game."
        }
        switch failure {
        case .offline:
            return "\(name) needs the internet to review your game."
        case .server("rate_limited"):
            return "\(name) needs a breath. Try again in a minute."
        case .server("daily_limit"):
            return "\(name) has reviewed a lot of games today. \(Coach.current.subjectCapitalized)'s back tomorrow."
        case .server("timeout"):
            return "\(name) took too long over this one. Try again."
        case .server, .badResponse:
            return "\(name) couldn't review this one. Try again."
        }
    }

    // MARK: Reading

    private func read(from start: Int) {
        stopReading()
        index = start
        reading = Task { [weak self] in
            var at = start
            while let self, !Task.isCancelled, let review = self.review, at < review.parts.count {
                self.index = at
                let part = review.parts[at]
                let recording = await self.recording(for: at)
                guard !Task.isCancelled else { return }
                let began = ContinuousClock.now
                if let recording {
                    await self.speaker.play(mp3: recording)
                } else {
                    await self.speaker.say(part.text)
                }
                guard !Task.isCancelled else { return }
                // Muted, nothing was read: leave the words up long enough to read them.
                if self.holdsSilentParts, ContinuousClock.now - began < .seconds(1) {
                    try? await Task.sleep(for: part.readingTime)
                } else {
                    try? await Task.sleep(for: self.gap)
                }
                guard !Task.isCancelled else { return }
                at += 1
            }
            guard let self, !Task.isCancelled else { return }
            self.reading = nil
            self.phase = .finished
        }
    }

    /// A part's recording: the one that arrived or was kept, waiting a little while the server
    /// is still sending. Nil: read it with the device's voice.
    private func recording(for part: Int) async -> Data? {
        let deadline = ContinuousClock.now + Self.longestWaitForVoice
        while voices[part] == nil, !voiceless.contains(part), !streamEnded, !Task.isCancelled,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let arrived = voices[part] { return arrived }
        return store.voice(part: part, for: game.id)
    }

    private func stopReading() {
        reading?.cancel()
        reading = nil
        speaker.stop()
    }

    private func stopEverything() {
        loading?.cancel()
        loading = nil
        stopReading()
    }
}
