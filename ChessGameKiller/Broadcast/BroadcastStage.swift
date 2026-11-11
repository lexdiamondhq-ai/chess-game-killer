import ChessKit
import Observation
import QuartzCore
import SwiftUI
import UIKit

/// Runs the King's hall while it is on screen: plays each figure's films one after another,
/// and follows the game. Your move sends the challenger's hand out; the King's move waits for
/// his own hand to reach the piece before it lands on the board; a capture of his brings the
/// storm; the end of the game plays the two endings. The script says which film; this plays it.
@MainActor
@Observable
final class BroadcastStage {
    /// One figure and the film it is playing.
    @MainActor
    final class Track {
        let figure: BroadcastClip.Figure
        let view: BroadcastFilmView
        private(set) var clip: BroadcastClip?
        private(set) var startedAt: CFTimeInterval = 0
        /// Plays when the current film ends, in place of an idle one.
        var upNext: BroadcastClip?

        init(figure: BroadcastClip.Figure, view: BroadcastFilmView) {
            self.figure = figure
            self.view = view
        }

        /// Seconds until the film on show hands over to the next: nothing for an idle film,
        /// which can be cut.
        var busyFor: Double {
            guard let clip, clip.isReach else { return 0 }
            return max(0, BroadcastScript.handover - (CACurrentMediaTime() - startedAt))
        }

        /// Whether the film played. A film missing from the bundle leaves the last one on show.
        @discardableResult
        func play(_ clip: BroadcastClip) -> Bool {
            guard let url = Bundle.main.url(forResource: clip.resource, withExtension: "mp4") else { return false }
            self.clip = clip
            startedAt = CACurrentMediaTime()
            view.show(url, fade: BroadcastScript.fade, handover: clip.holds ? nil : BroadcastScript.handover)
            return true
        }
    }

    /// The figures' film views, once the scene is running. Nil before, and in the tests'
    /// pictures, where the still plate stands in.
    private(set) var king: Track?
    private(set) var knight: Track?
    /// The dragons' wing beats, laid over the top of the King's films. Nil before the scene
    /// runs, and if its film or mask is missing: the dragons then hold still, as painted.
    private(set) var sky: BroadcastFilmView?

    @ObservationIgnored private var script = BroadcastScript()
    @ObservationIgnored private weak var match: MatchController?
    /// Bumps whenever the scene starts, stops or a new game begins, so timers from before stop.
    @ObservationIgnored private var run = 0
    /// When the King may next put his hand out: after the challenger's move is down, and
    /// after the storm has had its moment.
    @ObservationIgnored private var kingFreeAt: CFTimeInterval = 0
    /// The endings are playing, or waiting on the last move's film.
    @ObservationIgnored private var ended = false
    /// The dragons' film is on show: not during a storm or an ending, where the sky is the King's.
    @ObservationIgnored private var skyShown = false

    /// The still both figures start from, shown until the films are playing.
    static let plate: UIImage? = image("broadcast-plate", "jpg")

    private static func image(_ name: String, _ type: String) -> UIImage? {
        Bundle.main.path(forResource: name, ofType: type).flatMap(UIImage.init(contentsOfFile:))
    }

    /// The challenger's shape, the strip of table on his side, and the wider strip.
    private static func masks() -> [UIImage] {
        ["broadcast-knight-mask", "broadcast-knight-strip", "broadcast-knight-strip-wide"].compactMap { image($0, "png") }
    }

    private static let skyURL = Bundle.main.url(forResource: BroadcastScript.skyFilm, withExtension: "mp4")

    // MARK: On and off the screen

    /// The scene came on screen for this game.
    func begin(_ match: MatchController) {
        guard king == nil, !Welcome.isUnderTest else { return }
        let masks = Self.masks()
        // Without his mask the challenger's film would cover the King: better the King alone.
        guard masks.count == 3 else { return }
        self.match = match
        run += 1
        ended = false
        kingFreeAt = 0
        let king = Track(figure: .king, view: BroadcastFilmView())
        let knight = Track(figure: .knight, view: BroadcastFilmView(masks: masks))
        king.view.onEnd = { [weak self, weak king] in
            guard let self, let king else { return }
            self.filmEnded(king)
        }
        knight.view.onEnd = { [weak self, weak knight] in
            guard let self, let knight else { return }
            self.filmEnded(knight)
        }
        self.king = king
        self.knight = knight
        if let mask = Self.image("broadcast-sky-mask", "png"), Self.skyURL != nil {
            let sky = BroadcastFilmView(masks: [mask])
            sky.onEnd = { [weak self] in self?.skyLoops() }
            self.sky = sky
        }
        skyShown = false
        // The King's move waits for his hand.
        match.rivalStage = { [weak self] uci in
            await self?.kingActs(uci)
        }
        // The challenger first: the King's film has an empty chair where he sits, so his own
        // film is up, over the still plate, before the King's fades in under it.
        if match.isOver {
            playEnding(after: 0, kingAfter: Self.kingFollows)
            return
        }
        knight.play(BroadcastScript.opening(.knight))
        let run = self.run
        Task { @MainActor [weak self] in
            await BroadcastStage.pause(BroadcastStage.kingFollows)
            // Unless his hand is already out: a move he had chosen as the phone turned.
            guard let self, self.run == run, let king = self.king, king.clip == nil else { return }
            self.play(BroadcastScript.opening(.king), onKing: king)
        }
    }

    /// How long after the challenger's first film the King's starts.
    private static let kingFollows: Double = 0.4

    /// The scene left the screen: the phone turned upright, or the game went away.
    func end() {
        run += 1
        match?.rivalStage = nil
        match = nil
        king?.view.stop()
        knight?.view.stop()
        sky?.stop()
        king = nil
        knight = nil
        sky = nil
        skyShown = false
    }

    /// The app left the screen or came back: the films wait with it.
    func setPaused(_ paused: Bool) {
        king?.view.setPaused(paused)
        knight?.view.setPaused(paused)
        sky?.setPaused(paused)
    }

    // MARK: Following the game

    /// What of the game the scene follows.
    struct Beat: Equatable {
        var game: Int
        var ply: Int
        var over: Bool

        @MainActor
        init(_ match: MatchController) {
            game = match.gameNumber
            ply = match.game.plyCount
            over = match.isOver
        }
    }

    /// The game moved on from `old` to `new`.
    func follow(from old: Beat, to new: Beat) {
        guard let match, king != nil else { return }
        if new.game != old.game {
            newGame()
        } else if new.ply > old.ply, let played = match.game.lastPlayed {
            moveLanded(played, in: match)
        }
        if new.over, !old.over || new.game != old.game { gameEnded() }
    }

    private func newGame() {
        run += 1
        ended = false
        kingFreeAt = 0
        knight?.view.clearStrips()
        king?.upNext = nil
        knight?.upNext = nil
        if let king { play(BroadcastScript.opening(.king), onKing: king) }
        knight?.play(BroadcastScript.opening(.knight))
    }

    private func moveLanded(_ played: PlayedMove, in match: MatchController) {
        guard !ended else { return }
        if match.game.humanColors.contains(played.color) {
            let taken = played.isCapture ? match.game.captureEvents.last?.piece.kind : nil
            let cue = BroadcastScript.playerMoved(uci: played.uci, color: played.color, captured: taken,
                                                  endsGame: match.isOver)
            perform(cue)
        } else if played.isCapture {
            // His hand is already on the piece (`kingActs`); what follows is his satisfaction.
            king?.upNext = .king("pleased")
            // The challenger feels it, unless that move ended the game: then the endings follow.
            guard !match.isOver, let knight else { return }
            if knight.busyFor > 0 {
                knight.upNext = BroadcastScript.wince
            } else {
                play(BroadcastScript.wince, on: knight)
            }
        }
    }

    /// The challenger makes the player's move, and the storm answers a capture.
    private func perform(_ cue: BroadcastCue) {
        guard let knight else { return }
        let now = CACurrentMediaTime()
        knight.upNext = cue.then
        play(cue.reach, on: knight)
        kingFreeAt = now + cue.kingWaits
        guard let storm = cue.storm else { return }
        let run = self.run
        Task { @MainActor [weak self] in
            await BroadcastStage.pause(BroadcastScript.stormDelay)
            guard let self, self.run == run, !self.ended, let king = self.king else { return }
            king.upNext = nil
            self.play(storm, onKing: king)
        }
    }

    /// The King has chosen his move. His hand goes out, once the challenger's is back and the
    /// sky has settled; this returns as his hand reaches the piece, and the move lands.
    private func kingActs(_ uci: String) async {
        guard let match, king != nil else { return }
        let run = self.run
        let wait = kingFreeAt - CACurrentMediaTime()
        if wait > 0 { await BroadcastStage.pause(wait, while: { [weak self] in self?.run == run }) }
        guard self.run == run, !Task.isCancelled, !ended, let king else { return }
        let color = match.game.sideToMove
        let cue = BroadcastScript.kingMoves(uci: uci, color: color,
                                            captures: BroadcastScript.captures(uci: uci, in: match.game))
        king.upNext = nil
        guard play(cue.reach, onKing: king), let touch = cue.reach.touch else { return }
        await BroadcastStage.pause(touch, while: { [weak self] in self?.run == run })
    }

    private func gameEnded() {
        guard !ended else { return }
        ended = true
        // The last move's film plays out first: the hand comes back, then the ending.
        playEnding(after: max(king?.busyFor ?? 0, knight?.busyFor ?? 0))
    }

    private func playEnding(after delay: Double, kingAfter: Double = 0) {
        ended = true
        guard let match else { return }
        let playerWon = match.winner.map { match.game.humanColors.contains($0) }
        guard let ending = BroadcastScript.ending(playerWon: playerWon) else {
            // A draw: both sit on.
            ended = false
            if king?.clip == nil, let knight {
                knight.play(BroadcastScript.opening(.knight))
                let run = self.run
                Task { @MainActor [weak self] in
                    await BroadcastStage.pause(kingAfter)
                    guard let self, self.run == run, let king = self.king, king.clip == nil else { return }
                    self.play(BroadcastScript.opening(.king), onKing: king)
                }
            }
            return
        }
        king?.upNext = nil
        knight?.upNext = nil
        let run = self.run
        Task { @MainActor [weak self] in
            if delay > 0 { await BroadcastStage.pause(delay) }
            guard let self, self.run == run, let king = self.king, let knight = self.knight else { return }
            self.play(ending.knight, on: knight)
            if kingAfter > 0 { await BroadcastStage.pause(kingAfter) }
            guard self.run == run else { return }
            self.play(ending.king, onKing: king)
        }
    }

    // MARK: Playing

    private func filmEnded(_ track: Track) {
        guard let clip = track.clip, !clip.holds else { return }
        let next = track.upNext ?? script.idle(track.figure)
        track.upNext = nil
        if track.figure == .knight {
            play(next, on: track)
        } else {
            play(next, onKing: track)
        }
    }

    /// Plays one of the King's films. The dragons beat their wings over all of them but the
    /// ones where the sky is his own (the storms, the endings): for those they stand aside,
    /// and they come back with the film after, which starts as theirs does, on the still pose.
    @discardableResult
    private func play(_ clip: BroadcastClip, onKing king: Track) -> Bool {
        guard king.play(clip) else { return false }
        setSky(shown: !clip.ownsSky)
        return true
    }

    private func setSky(shown: Bool) {
        guard let sky, shown != skyShown else { return }
        skyShown = shown
        sky.setAside(!shown, over: 0.3)
        if shown { skyLoops() }
    }

    /// The dragons' film from its start: now, and again each time it comes round.
    private func skyLoops() {
        guard skyShown, let sky, let url = Self.skyURL else { return }
        sky.show(url, fade: BroadcastScript.fade, handover: BroadcastScript.handover)
    }

    /// Plays one of the challenger's films, widening his mask over the table while his arm
    /// is out.
    private func play(_ clip: BroadcastClip, on knight: Track) {
        knight.view.clearStrips()
        guard knight.play(clip), let strip = clip.strip else { return }
        let run = self.run
        let index = strip.wide ? 1 : 0
        let started = knight.startedAt
        Task { @MainActor [weak self, weak knight] in
            if strip.from > 0 { await BroadcastStage.pause(strip.from) }
            // Still this showing of this film: a newer one cleared the strips and set its own.
            guard let self, self.run == run, let knight, knight.startedAt == started else { return }
            knight.view.setStrip(index, on: true)
            guard let to = strip.to else { return }
            await BroadcastStage.pause(to - strip.from)
            guard self.run == run, knight.startedAt == started else { return }
            knight.view.setStrip(index, on: false)
        }
    }

    /// Waits, in short steps, for as long as `going` holds.
    private static func pause(_ seconds: Double, while going: @MainActor () -> Bool = { true }) async {
        let until = CACurrentMediaTime() + seconds
        while going(), !Task.isCancelled {
            let left = until - CACurrentMediaTime()
            guard left > 0 else { return }
            try? await Task.sleep(for: .seconds(min(left, 0.1)))
        }
    }
}
