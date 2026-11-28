import AVFoundation
import SwiftUI

/// "The Maze That Remembers": Learn's 42-second film (Alex, 2026-11-28). Leo tells it: the Wolf
/// Knight is lost in a maze of rings, loses to the Berserker, goes back to study the game he
/// lost, and wins the same board the second time. It plays once, the first time Learn opens on
/// its own page, and Learn's menu plays it again (Watch the film).
enum LearnFilm {
    static let key = "learnFilmSeen"

    static var url: URL? { Bundle.main.url(forResource: "learn-film", withExtension: "mp4") }

    /// Once, the first time Learn opens. Never in tests or CI's pictures, and not without the file.
    static func shouldShow(_ defaults: UserDefaults = .standard, underTest: Bool = Welcome.isUnderTest) -> Bool {
        guard !underTest, defaults.string(forKey: "showcase") == nil,
              defaults.string(forKey: "showcaseOpen") == nil else { return false }
        return !defaults.bool(forKey: key) && url != nil
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}

/// Learn's film, full screen and with sound, over Learn. Skip sits small in the corner; at its
/// end the film gives way to Learn.
struct LearnFilmView: View {
    let done: () -> Void
    @State private var player: AVPlayer?
    @State private var finished = false

    var body: some View {
        Color.black
            .overlay {
                if let player { RivalFilmLayer(player: player) }
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                FilmSkipButton(action: finish)
                    .padding(.top, 3)
                    .padding(.trailing, 20)
                    .accessibilityLabel("Skip the film")
            }
            .statusBarHidden()
            .onAppear(perform: start)
            .onDisappear(perform: stop)
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
                .receive(on: DispatchQueue.main)) { note in
                if let item = note.object as? AVPlayerItem, item === player?.currentItem { finish() }
            }
            // Leaving the app pauses a film; coming back picks it up where it stopped.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if !finished { player?.play() }
            }
    }

    private func start() {
        guard let url = LearnFilm.url else {
            finish()
            return
        }
        // Learn already rests Home's strings. The film has Leo's voice, so it plays with the ring
        // switch off, like the intro and the rival films.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let made = AVPlayer(url: url)
        made.actionAtItemEnd = .pause
        made.preventsDisplaySleepDuringVideoPlayback = true
        player = made
        made.play()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stop()
        done()
    }

    private func stop() {
        player?.pause()
        // Everything after the film is quiet on silent again.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
}

/// Skip, small in a film's corner: the intro film's and Learn's. The whole pill takes the tap,
/// and a little air around it, so a thumb doesn't have to find the word.
struct FilmSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LearnFilmView(done: {})
}
