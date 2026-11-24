import AVFoundation
import SwiftUI

/// "Road to the Throne": the 60-second film that plays once, right after the welcome (Alex,
/// 2026-11-24). Leo narrates: the Wolf Knight (you) rides past Cub, Hunter, Berserker and
/// Lionheart, sees Analyze, the rooms and Today's Move, and climbs to the Ashen King. It ends on
/// the Gilded knight under "Beauty of Chess", and Begin rises once Leo has said so.
/// Settings › How it works › Watch the intro plays it again.
enum IntroFilm {
    static let key = "introFilmSeen"
    /// When Begin rises: just after Leo's "This is the Beauty of Chess."
    static let beginAt: Double = 55.4

    static var url: URL? { Bundle.main.url(forResource: "intro-film", withExtension: "mp4") }

    /// Once, after the first welcome. Never in tests or CI's pictures, and not without the file.
    static func shouldShow(_ defaults: UserDefaults = .standard) -> Bool {
        guard !Welcome.isUnderTest, defaults.string(forKey: "showcase") == nil else { return false }
        return !defaults.bool(forKey: key) && url != nil
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}

/// The intro film, full screen and with sound. Skip sits small in the corner; Begin rises at
/// the end over the film's last frame, which holds.
struct IntroFilmView: View {
    let done: () -> Void
    @State private var player: AVPlayer?
    @State private var showsBegin = false
    @State private var finished = false
    @State private var timeWatch: Any?

    private static let gold = Color(hex: 0xE8C27A)
    private static let paleGold = Color(hex: 0xF6E3B4)

    var body: some View {
        Color.black
            .overlay {
                if let player { RivalFilmLayer(player: player) }
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                if !showsBegin {
                    Button("Skip", action: finish)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        .padding(.top, 8)
                        .padding(.trailing, 20)
                        .transition(.opacity)
                        .accessibilityHint("Skips the intro film")
                }
            }
            .overlay(alignment: .bottom) {
                if showsBegin {
                    begin
                        .padding(.horizontal, 48)
                        .padding(.bottom, 56)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden()
            .onAppear(perform: start)
            .onDisappear(perform: stop)
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
                .receive(on: DispatchQueue.main)) { note in
                // The last frame holds; Begin is there in case the time watch missed its moment.
                if let item = note.object as? AVPlayerItem, item === player?.currentItem { raiseBegin() }
            }
    }

    private var begin: some View {
        Button(action: finish) {
            Text("BEGIN")
                .font(.custom(HomeCarvingFont.plain, size: 18, relativeTo: .body))
                .tracking(4)
                .foregroundStyle(LinearGradient(colors: [Self.paleGold, Self.gold],
                                                startPoint: .top, endPoint: .bottom))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Capsule().fill(Color(hex: 0x14110D).opacity(0.92)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Self.gold.opacity(0.7), Self.gold.opacity(0.3)],
                                                               startPoint: .top, endPoint: .bottom),
                                                lineWidth: 1))
                .shadow(color: Self.gold.opacity(0.18), radius: 14, y: 4)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel("Begin")
    }

    private func start() {
        guard let url = IntroFilm.url else {
            finish()
            return
        }
        // A film with Leo's voice: it plays with the ring switch off, like the rival films.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let made = AVPlayer(url: url)
        made.actionAtItemEnd = .pause
        made.preventsDisplaySleepDuringVideoPlayback = true
        timeWatch = made.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: IntroFilm.beginAt,
                                                                                preferredTimescale: 600))],
                                                 queue: .main) { MainActor.assumeIsolated { raiseBegin() } }
        player = made
        made.play()
    }

    private func raiseBegin() {
        guard !showsBegin else { return }
        withAnimation(.easeOut(duration: 0.8)) { showsBegin = true }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stop()
        done()
    }

    private func stop() {
        if let timeWatch { player?.removeTimeObserver(timeWatch) }
        timeWatch = nil
        player?.pause()
        // Everything after the film is quiet on silent again.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
}

#Preview {
    IntroFilmView(done: {})
}
