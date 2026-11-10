import AVFoundation
import SwiftUI
import UIKit

/// One figure's films on screen: two player layers, one over the other, so a film can fade
/// into the next. Every loop starts and ends on the same pose, so the fade is only seen when
/// a film is cut short (a move made while the figure was mid-gesture), and then as a quick
/// settle. The challenger's view is cut to his shape by a mask.
final class BroadcastFilmView: UIView {
    private let players = [AVPlayer(), AVPlayer()]
    private let screens = [AVPlayerLayer(), AVPlayerLayer()]
    /// The screen on show. The other one is loaded with the next film.
    private var front = 0
    /// Counts the films asked for, so anything that finishes late leaves a newer one alone.
    private var showing = 0
    /// The newest film is loaded but its first frame isn't on its screen yet.
    private var arriving = false
    /// Watches the newest film: its first frame, and its last moments.
    private var watch: (player: AVPlayer, token: Any)?
    private var endWatch: NSObjectProtocol?
    /// The film playing, or about to: its end is the one that counts.
    private var current: AVPlayerItem?
    private var paused = false
    /// When the fade under way is over. A film asked for during it waits those few frames:
    /// the screen it needs is still showing through.
    private var fadeEnds: CFTimeInterval = 0

    /// The mask's layers: the figure's own shape, then each strip of table.
    private let maskRoot = CALayer()
    private var strips: [CALayer] = []

    /// Called when a film is about to end (see `show`), or has ended.
    var onEnd: (() -> Void)?

    /// - Parameter masks: the figure's shape first, then any strips that can be added to it.
    ///   Empty shows the whole film.
    init(masks: [UIImage] = []) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for (player, screen) in zip(players, screens) {
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.allowsExternalPlayback = false
            // The game keeps the screen awake while a clock runs; the films don't on their own.
            player.preventsDisplaySleepDuringVideoPlayback = false
            screen.player = player
            screen.videoGravity = .resize
            screen.opacity = 0
            layer.addSublayer(screen)
        }
        if let shape = masks.first {
            maskRoot.addSublayer(Self.maskLayer(shape))
            strips = masks.dropFirst().map(Self.maskLayer)
            for strip in strips {
                strip.opacity = 0
                maskRoot.addSublayer(strip)
            }
            layer.mask = maskRoot
        }
        // Should a film ever run out with no call before its end, the next one still follows.
        endWatch = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let ended, ended === self.current else { return }
                self.onEnd?()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func maskLayer(_ image: UIImage) -> CALayer {
        let layer = CALayer()
        layer.contents = image.cgImage
        layer.contentsGravity = .resize
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for screen in screens { screen.frame = bounds }
        maskRoot.frame = bounds
        for sublayer in maskRoot.sublayers ?? [] { sublayer.frame = bounds }
        CATransaction.commit()
    }

    /// Plays a film from its start, fading it in over the one on show.
    /// - Parameter handover: seconds into the film when `onEnd` is called, a little before
    ///   its true end, so the next film is already running as this one finishes and nothing
    ///   (the rain least of all) ever stands still. Nil for a film that holds its last frame.
    func show(_ url: URL, fade: CFTimeInterval, handover: Double?) {
        showing += 1
        let number = showing
        let wait = fadeEnds - CACurrentMediaTime()
        guard wait > 0 else {
            start(url, number: number, fade: fade, handover: handover)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.02))
            guard let self, number == self.showing else { return }
            self.start(url, number: number, fade: fade, handover: handover)
        }
    }

    private func start(_ url: URL, number: Int, fade: CFTimeInterval, handover: Double?) {
        let back = 1 - front
        let player = players[back]
        forgetWatch()
        let item = AVPlayerItem(url: url)
        current = item
        arriving = true
        player.replaceCurrentItem(with: item)
        setOpacity(0, of: screens[back], over: 0)
        // The film is shown once it is truly playing, never on a frame left over from the last
        // film this screen held.
        let firstFrame = CMTime(value: 1, timescale: 24)
        var times = [NSValue(time: firstFrame)]
        if let handover { times.append(NSValue(time: CMTime(seconds: handover, preferredTimescale: 600))) }
        let token = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self, weak player] in
            MainActor.assumeIsolated {
                guard let self, let player, number == self.showing else { return }
                if player.currentTime().seconds < 1 {
                    self.reveal(back, number: number, fade: fade)
                } else {
                    self.onEnd?()
                }
            }
        }
        watch = (player, token)
        if !paused { player.play() }
    }

    private func reveal(_ index: Int, number: Int, fade: CFTimeInterval) {
        guard number == showing, arriving else { return }
        arriving = false
        let old = front
        front = index
        fadeEnds = CACurrentMediaTime() + fade
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screens[index].zPosition = 1
        screens[old].zPosition = 0
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(fade)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            // The film underneath rests once it is covered, unless a newer one has taken its screen.
            guard let self, number == self.showing, self.front == index else { return }
            self.players[old].pause()
            self.setOpacity(0, of: self.screens[old], over: 0)
        }
        screens[index].opacity = 1
        CATransaction.commit()
    }

    private func forgetWatch() {
        guard let watch else { return }
        watch.player.removeTimeObserver(watch.token)
        self.watch = nil
    }

    private func setOpacity(_ opacity: Float, of layer: CALayer, over seconds: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(seconds <= 0)
        CATransaction.setAnimationDuration(seconds)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        layer.opacity = opacity
        CATransaction.commit()
    }

    /// Adds a strip of table to the figure's shape, or takes it away.
    func setStrip(_ index: Int, on: Bool) {
        guard strips.indices.contains(index) else { return }
        setOpacity(on ? 1 : 0, of: strips[index], over: 0.18)
    }

    func clearStrips() {
        for index in strips.indices { setStrip(index, on: false) }
    }

    /// Holds the films where they are (the app left the screen), or carries on.
    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        if paused {
            players.forEach { $0.pause() }
            return
        }
        // The newest film, and the one it is fading in over.
        let newest = players[arriving ? 1 - front : front]
        if let item = newest.currentItem, !item.duration.isNumeric || item.currentTime() < item.duration {
            newest.play()
        }
    }

    /// Stops both players and lets go of their films. The view isn't used again.
    func stop() {
        showing += 1
        forgetWatch()
        if let endWatch { NotificationCenter.default.removeObserver(endWatch) }
        endWatch = nil
        current = nil
        onEnd = nil
        for player in players {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}

/// A figure's film view inside SwiftUI.
struct BroadcastFilm: UIViewRepresentable {
    let view: BroadcastFilmView

    func makeUIView(context: Context) -> BroadcastFilmView { view }
    func updateUIView(_ view: BroadcastFilmView, context: Context) {}
}
