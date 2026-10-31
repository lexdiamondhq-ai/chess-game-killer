import ActivityKit
import ChessKit
import Foundation
import SwiftUI

/// Keeps the game under way on the Lock Screen, in the Dynamic Island and in StandBy: a Live
/// Activity that starts on a game's first move, follows every move and ends with the game (or
/// as soon as another one is set up). Only games against a rival. iOS's own switch turns it off
/// (Settings, Chess Game Killer, Live Activities).
///
/// The clock waits while the app is away, so the Lock Screen shows the time you come back to,
/// standing still rather than counting down.
@MainActor
final class LiveGameKeeper {
    static let shared = LiveGameKeeper()

    private var activity: Activity<LiveGameAttributes>?
    /// The game on the Lock Screen now.
    private var gameID: UUID?
    private var shown: LiveGameAttributes.ContentState?
    /// The game has ended and says so; it leaves the Lock Screen on its own a little later.
    private var finished = false
    /// The opening the game reached, kept once it leaves the book.
    private var opening: String?
    /// The named openings load once, away from the main thread, the first time a game starts.
    private var openingsReady = false
    private var loadingOpenings = false

    /// How long a finished game stays on the Lock Screen.
    static let afterTheGame: TimeInterval = 10 * 60

    /// Ends whatever an earlier run of the app left on the Lock Screen: that game went with it.
    func clearLeftovers() {
        for leftover in Activity<LiveGameAttributes>.activities where leftover.id != activity?.id {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Brings the Lock Screen up to date with the match: call it after a move, when a game
    /// starts or ends, and when the app goes away.
    func follow(_ match: MatchController) {
        guard match.hasStarted, match.setup.opponent == .computer, match.game.plyCount > 0 else {
            // Nothing under way, or a new game still being set up: the last one leaves at once.
            clear()
            return
        }
        if gameID != match.gameID {
            clear()
            gameID = match.gameID
        }
        guard !finished else { return }
        loadOpenings()
        let state = state(of: match)
        guard state != shown else { return }
        shown = state
        if match.isOver {
            finished = true
            guard let activity else { return }
            let content = ActivityContent(state: state, staleDate: nil)
            let leave = Date.now.addingTimeInterval(Self.afterTheGame)
            Task { await activity.end(content, dismissalPolicy: .after(leave)) }
            return
        }
        if let activity {
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) }
        } else {
            start(match, state)
        }
    }

    /// Takes the game off the Lock Screen at once.
    func clear() {
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        gameID = nil
        shown = nil
        finished = false
        opening = nil
    }

    private func start(_ match: MatchController, _ state: LiveGameAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: Self.attributes(of: match),
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
        } catch {
            NSLog("The game's Live Activity did not start: %@", error.localizedDescription)
        }
    }

    // MARK: What it shows

    static func attributes(of match: MatchController) -> LiveGameAttributes {
        let rival = match.setup.level.rival
        return LiveGameAttributes(rival: rival.name, lightHex: rival.lightHex, glow: rival.glowName,
                                  youAreWhite: match.setup.playerColor == .white,
                                  clock: match.setup.timeControl.name)
    }

    func state(of match: MatchController) -> LiveGameAttributes.ContentState {
        let game = match.game
        if openingsReady, game.plyCount <= OpeningIndex.maxPlies,
           let line = OpeningIndex.shared.opening(of: game.positionFENs) {
            opening = line.family
        }
        return Self.state(of: match, opening: opening)
    }

    static func state(of match: MatchController, opening: String?) -> LiveGameAttributes.ContentState {
        let game = match.game
        let you = match.setup.playerColor
        let last = game.lastPlayed
        let seconds: Int? = match.clock.map { Int($0.remaining(for: you).components.seconds) }
        return LiveGameAttributes.ContentState(
            fen: game.fen,
            lastMove: last?.san,
            lastMoveByRival: last.map { $0.color != you } ?? false,
            yourMove: !match.isOver && game.sideToMove == you,
            moveNumber: TrainingChess.moveNumber(game.fen),
            yourSeconds: seconds,
            opening: opening,
            result: match.isOver ? result(of: match) : nil
        )
    }

    /// "You won", "Pulse won", "Draw".
    static func result(of match: MatchController) -> String {
        guard let winner = match.winner else { return "Draw" }
        return winner == match.setup.playerColor ? "You won" : "\(match.setup.level.rival.name) won"
    }

    private func loadOpenings() {
        guard !openingsReady, !loadingOpenings else { return }
        loadingOpenings = true
        Task.detached(priority: .utility) {
            _ = OpeningIndex.shared.lines.count
            await MainActor.run { LiveGameKeeper.shared.openingsReady = true }
        }
    }
}

extension LiveGameLink {
    /// Posted when the Lock Screen's game is tapped, for the game screen to come forward.
    static let notification = Notification.Name("ChessGameKiller.openLiveGame")

    @MainActor
    static func open() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

/// Follows the match for the Lock Screen: each move, a new game, its end, and the app going
/// away (so the clock there reads as the player left it).
struct LiveGameFollow: ViewModifier {
    let match: MatchController
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Whatever an earlier run left on the Lock Screen goes, and a game already under
                // way (CI's pictures open on one) goes up.
                LiveGameKeeper.shared.clearLeftovers()
                LiveGameKeeper.shared.follow(match)
            }
            .onChange(of: match.game.plyCount) { _, _ in LiveGameKeeper.shared.follow(match) }
            .onChange(of: match.gameNumber) { _, _ in LiveGameKeeper.shared.follow(match) }
            .onChange(of: match.isOver) { _, _ in LiveGameKeeper.shared.follow(match) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { LiveGameKeeper.shared.follow(match) }
            }
    }
}
