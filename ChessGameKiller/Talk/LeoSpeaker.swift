import AVFoundation
import Foundation

/// Plays Leo's recorded answer from the server, or has CoachVoice speak it with the device's voice
/// when there is no recording. While Leo talks the audio is set up as in lessons (out loud even on
/// silent, other audio turned down); afterwards the game's quiet sound effects come back.
@MainActor
final class LeoSpeaker: NSObject, TalkSpeaker {
    private var player: AVAudioPlayer?
    private var waiting: CheckedContinuation<Void, Never>?
    private var isSaying = false
    /// This speaker switched the audio to the lesson setup and owes the switch back.
    private var holdsLessonAudio = false
    /// Counts lines, so a line that was stopped never tidies up after the one that replaced it.
    private var turn = 0
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
    }

    func play(mp3: Data) async {
        stop()
        turn += 1
        let mine = turn
        // Muted, Leo stays quiet: his words are on the screen.
        guard !mp3.isEmpty, !Task.isCancelled, !CoachVoice.shared.isMuted,
              let player = try? AVAudioPlayer(data: mp3, fileTypeHint: AVFileType.mp3.rawValue)
        else { return }
        beginLessonAudio()
        watchInterruptions()
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if player.play() {
                    self.waiting = continuation
                } else {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
        // Stopped, or a newer line took over: that already tidied up.
        guard turn == mine else { return }
        self.player = nil
        endTurn()
    }

    func say(_ text: String) async {
        stop()
        turn += 1
        let mine = turn
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !Task.isCancelled, !CoachVoice.shared.isMuted else { return }
        beginLessonAudio()
        isSaying = true
        await CoachVoice.shared.say(line)
        guard turn == mine else { return }
        isSaying = false
        endTurn()
    }

    func stop() {
        turn += 1
        if let player {
            player.stop()
            self.player = nil
        }
        if isSaying {
            isSaying = false
            CoachVoice.shared.stop()
        }
        resumeWaiting()
        endTurn()
    }

    // MARK: Private

    private func endTurn() {
        stopWatchingInterruptions()
        endLessonAudio()
    }

    private func resumeWaiting() {
        let continuation = waiting
        waiting = nil
        continuation?.resume()
    }

    private func beginLessonAudio() {
        guard !holdsLessonAudio else { return }
        // A lesson already has the coach's audio set up, and keeps it after Leo is done.
        guard AVAudioSession.sharedInstance().category != .playback else { return }
        CoachVoice.shared.beginLesson()
        holdsLessonAudio = true
    }

    private func endLessonAudio() {
        guard holdsLessonAudio else { return }
        holdsLessonAudio = false
        CoachVoice.shared.endLesson()
    }

    /// A call, Siri or an alarm pauses the player without a finish callback. Stop instead, so the
    /// session doesn't wait on a line that will never end.
    private func watchInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    private func stopWatchingInterruptions() {
        guard let observer = interruptionObserver else { return }
        interruptionObserver = nil
        NotificationCenter.default.removeObserver(observer)
    }

    fileprivate func playerEnded(_ ended: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == ended else { return }
        self.player = nil
        resumeWaiting()
    }
}

extension LeoSpeaker: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerEnded(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerEnded(id) }
    }
}
