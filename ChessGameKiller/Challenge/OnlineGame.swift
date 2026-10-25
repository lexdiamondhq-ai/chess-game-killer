import ChessKit
import Foundation
import Observation
import UIKit

/// One friend game on screen. The server's state is the truth: the board follows it, the
/// player's own moves go to the server as they are made (and stay on the board while they
/// travel), the clocks are read from it, and leaving the app or taking a screenshot is reported.
@MainActor
@Observable
final class OnlineGame {
    enum Phase: Equatable {
        /// The game hasn't arrived yet.
        case loading
        /// Only the creator is seated: the lobby.
        case waiting
        case playing
        case over
    }

    enum Connection: Equatable {
        case connecting, live, offline
        /// The game was opened on a newer screen (another device, say). This one only watches until
        /// the player takes it back with `playHere()`.
        case elsewhere
    }

    enum RematchStage: Equatable {
        /// Nobody has asked.
        case none
        /// The player asked; the friend hasn't yet.
        case asked
        /// The friend asked.
        case offered
        /// Both asked: the new game is opening.
        case starting
        /// Both asked, but the new game didn't open. It can be tried again.
        case ready
    }

    struct Toast: Equatable, Identifiable {
        let id: Int
        let text: String
        let symbol: String
        var isWarning = false
    }

    /// One of the player's moves, on the board and on its way to the server.
    struct PendingMove: Equatable {
        let uci: String
        let san: String
        /// The number of half-moves before it: the index it will have.
        let ply: Int
        /// Server time when it was played. The player's clock stops there while the move travels.
        let at: Double
    }

    /// The board. The player taps it; the friend's moves are played on it as they arrive.
    let match: MatchController
    /// The player's entry in their list of friend games, kept up to date.
    private(set) var record: FriendGame
    private(set) var state: FriendGameState? = nil
    private(set) var phase: Phase = .loading
    private(set) var connection: Connection = .connecting
    private(set) var toast: Toast? = nil
    /// Why the game couldn't be opened, when it couldn't.
    private(set) var loadProblem: String? = nil
    /// The action under way, for its button.
    private(set) var sending: ChallengeAction? = nil
    private(set) var isSwitching = false
    /// The player is back in a timed game after leaving the app: the banner says what leaving costs.
    private(set) var cameBack = false
    /// The friend has been away past the grace period: the player may claim the win.
    private(set) var claimReady = false
    /// The friend's absence the player chose to wait out instead of claiming, by when it began.
    private(set) var waitedOutAway: Double? = nil
    /// The fair-play rules were put away on this game's first screen.
    private(set) var fairPlaySeen = false
    /// What the player has reported about the friend in this game.
    private(set) var reported: Set<ChallengeAction> = []
    private(set) var pending: PendingMove? = nil

    /// The record changed: a new state, or a rematch with its own code.
    @ObservationIgnored var onChange: (@MainActor (FriendGame) -> Void)?
    /// The game is over (also when a finished game is opened).
    @ObservationIgnored var onFinish: (@MainActor (FriendGame, FriendGameState) -> Void)?

    @ObservationIgnored private let api: ChallengeAPI
    @ObservationIgnored private let sounds: SoundPlaying?
    /// The moves the board shows, in engine notation: the server's, then the player's pending one.
    @ObservationIgnored private(set) var boardMoves: [String] = []
    /// How many of `boardMoves` the board started from, when it was set up from a position.
    @ObservationIgnored private var boardBase = 0
    @ObservationIgnored private var serverClock: ChallengeServerClock?
    @ObservationIgnored private var live: ChallengeLive?
    @ObservationIgnored private var moveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var claimTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var cameBackTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private(set) var isActive = false
    /// When the player left the app in a timed game.
    @ObservationIgnored private var leftAt: Date?
    /// When the app last went to the background, in any game.
    @ObservationIgnored private var backgroundedAt: Date?
    /// The start of the player's own absence already answered with `back`, so it is said once.
    @ObservationIgnored private var reclaimedAway: Double?
    @ObservationIgnored private var nextToastID = 0
    /// The friend's screenshots and recordings already told.
    @ObservationIgnored private var toldShots = 0
    @ObservationIgnored private var toldRecordings = 0

    /// How often the game is fetched while the live connection is down, as the protocol asks.
    static let pollInterval: Duration = .seconds(3)
    /// Back from the background after this long (seconds), the live connection is opened afresh.
    static let staleAfterBackground: TimeInterval = 10

    init(record: FriendGame, api: ChallengeAPI, sounds: SoundPlaying?, initial: FriendGameState? = nil) {
        self.record = record
        self.api = api
        self.sounds = sounds
        match = MatchController(engine: nil, sounds: sounds)
        startBoard()
        watchBoard()
        if let initial { apply(initial) }
    }

    // MARK: Reading the game

    var code: String { record.code }
    var seat: FriendSeat { record.seat }
    var opponentSeat: FriendSeat { record.seat.opposite }

    /// The friend's name, as they gave it.
    var opponentName: String {
        if let name = state?[opponentSeat].name.map(ChallengeName.clean), !name.isEmpty { return name }
        return record.opponentName ?? "Your friend"
    }

    var myName: String {
        state?[seat].name.map(ChallengeName.clean) ?? ""
    }

    var clock: FriendClock? { state?.clock ?? record.clock }

    /// "vs Sam · 10+0", or "vs Sam · No clock".
    var title: String {
        "vs \(opponentName) · \(clock?.label ?? "No clock")"
    }

    /// Leaving counts: a timed game, under way, both sides have moved. Away past the grace period,
    /// the other side may claim the win.
    var leaveRuleApplies: Bool { state.map(FriendClockMath.leaveRuleApplies) ?? false }
    /// A timed game: closing it is leaving it.
    var isTimed: Bool { clock != nil }
    /// Before both sides have moved, giving up aborts the game instead. A move still on its way counts.
    var canAbort: Bool { phase == .playing && (state?.moves.count ?? 0) + (pending == nil ? 0 : 1) < 2 }
    var drawOfferedByMe: Bool { phase == .playing && state?.drawOffer == seat }
    var drawOfferedToMe: Bool { phase == .playing && state?.drawOffer == opponentSeat }
    var isMyTurn: Bool { phase == .playing && state?.turn == seat && pending == nil }

    /// `seat` has the game open right now.
    func isOnline(_ seat: FriendSeat) -> Bool {
        state?[seat].online ?? false
    }

    /// The moves so far in standard notation, the player's pending one last.
    var ribbon: [String] {
        (state?.san ?? []) + (pending.map { [$0.san] } ?? [])
    }

    var rematchStage: RematchStage {
        guard let state, state.status == .over else { return .none }
        guard let rematch = state.rematch else { return isSwitching ? .starting : .none }
        if rematch.code != nil { return isSwitching ? .starting : .ready }
        if isSwitching { return .starting }
        guard let by = rematch.by else { return .none }
        return by == seat ? .asked : .offered
    }

    /// The server's time now, in milliseconds since 1970.
    func serverNow(at instant: ContinuousClock.Instant = .now) -> Double {
        serverClock?.now(at: instant) ?? Date().timeIntervalSince1970 * 1000
    }

    /// Milliseconds left on `seat`'s clock; nil with no clock.
    func timeLeft(for seat: FriendSeat, at instant: ContinuousClock.Instant = .now) -> Double? {
        guard let clocks = state?.clocks else { return nil }
        var now = serverNow(at: instant)
        // The player's clock stops when they move, not when the server hears of it.
        if let pending, seat == self.seat, clocks.running == seat { now = min(now, pending.at) }
        return FriendClockMath.remaining(clocks, for: seat, serverNow: now)
    }

    func isClockRunning(for seat: FriendSeat) -> Bool {
        guard phase == .playing, state?.clocks?.running == seat else { return false }
        return !(seat == self.seat && pending != nil)
    }

    /// Whole seconds before the other side may claim the win from `seat`; nil when it isn't away.
    func awaySecondsLeft(for seat: FriendSeat, at instant: ContinuousClock.Instant = .now) -> Int? {
        state.flatMap { FriendClockMath.awaySecondsLeft($0, seat: seat, serverNow: serverNow(at: instant)) }
    }

    /// "Sam resigned. You win".
    var resultHeadline: String? {
        guard let state, let result = state.result else { return nil }
        return FriendResultWords.headline(result, me: seat, opponent: opponentName, flagged: flaggedSeat,
                                          creator: state.creator)
    }

    /// "Rapid · 10+0 · 34 moves".
    var resultDetail: String {
        state.map(FriendResultWords.detail) ?? ""
    }

    /// The player won, lost (false), or neither (nil): a draw, or a game that never happened.
    var didWin: Bool? {
        guard let result = state?.result, result.reason.wasPlayed, let winner = result.winner else { return nil }
        return winner == seat
    }

    /// The side whose flag fell, for a game drawn on time.
    private var flaggedSeat: FriendSeat? {
        guard let state else { return nil }
        if let clocks = state.clocks {
            if clocks.white <= 0 { return .white }
            if clocks.black <= 0 { return .black }
        }
        return state.turn
    }

    /// What `color` has taken, counted against a full set of pieces.
    func captured(by color: Piece.Color) -> [CapturedCount] {
        ChallengeMaterial.captured(by: color, pieces: match.game.pieces.map(\.piece))
    }

    func materialLead(for color: Piece.Color) -> Int {
        ChallengeMaterial.lead(for: color, pieces: match.game.pieces.map(\.piece))
    }

    /// The finished game, for the player's saved games.
    func savedGame(date: Date = .now) -> SavedGame? {
        guard let state else { return nil }
        return FriendGameArchive.savedGame(state, seat: seat, id: record.id, date: date, opponent: opponentName)
    }

    // MARK: On screen

    /// The game is on screen: listen live, watch for leaving and screenshots, keep the screen awake.
    func activate() {
        guard !isActive else { return }
        isActive = true
        observe()
        connect()
        Task { [weak self] in await self?.refresh() }
        if phase == .playing {
            // Coming back to a game that was closed a moment ago ends the absence.
            report(.back)
            if screenIsCaptured { report(.recording) }
        }
        scheduleDeadline()
        refreshIdleTimer()
    }

    /// Off screen: closing a game under way counts as leaving it.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if phase == .playing { report(.away) }
        disconnect()
        stopPolling()
        deadlineTask?.cancel()
        deadlineTask = nil
        claimTask?.cancel()
        claimTask = nil
        cameBackTask?.cancel()
        cameBack = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Fetches the game. While the live connection is down this runs every few seconds.
    func refresh() async {
        do {
            apply(try await api.game(code))
        } catch let error as ChallengeError {
            if state == nil {
                loadProblem = error.isNotFound ? "This game isn't on the server any more." : error.message
            }
        } catch {}
    }

    func dismissToast() {
        toast = nil
    }

    /// A word for the player from outside the game, such as a link that has to wait.
    func notify(_ text: String, symbol: String) {
        say(text, symbol: symbol)
    }

    func dismissCameBack() {
        cameBack = false
    }

    /// The fair-play rules show on the first screen of a game under way, until both sides have moved.
    var showsFairPlay: Bool {
        phase == .playing && !fairPlaySeen && (state?.moves.count ?? 0) < 2
    }

    func dismissFairPlay() {
        fairPlaySeen = true
    }

    /// The claim is on offer: the friend left a while ago and the player hasn't chosen to wait.
    var offersClaim: Bool {
        claimReady && waitedOutAway != state?[opponentSeat].away
    }

    /// Keeps waiting for the friend instead of claiming the win. The friend's line still offers it.
    func keepWaiting() {
        waitedOutAway = state?[opponentSeat].away
    }

    /// "Away for over a minute".
    var graceWords: String {
        let seconds = Int(((state?.leaveGraceMs ?? 60_000) / 1000).rounded())
        if seconds == 60 { return "a minute" }
        if seconds % 60 == 0 { return "\(seconds / 60) minutes" }
        return "\(seconds) seconds"
    }

    // MARK: Actions

    func offerDraw() async { await act(.offerDraw) }
    func acceptDraw() async { await act(.acceptDraw) }
    func declineDraw() async { await act(.declineDraw) }
    /// Before both sides have moved, the server aborts instead.
    func resign() async { await act(.resign) }
    /// Stops the game before both sides have moved. Asked for any later (a move crossed the tap),
    /// the server refuses instead of counting it as a resignation.
    func abort() async { await act(.abort) }
    func cancelChallenge() async { await act(.cancel) }

    /// The friend left and stayed away past the grace period: the player takes the win.
    func claimWin() async { await act(.claimWin) }

    /// Reports the friend's name (hidden at once) or cheating. Each counts once.
    func reportOpponent(_ action: ChallengeAction) async {
        guard action == .reportName || action == .reportCheating, !reported.contains(action) else { return }
        guard await act(action) else { return }
        reported.insert(action)
        say(action == .reportName ? "Thanks. The name is hidden and we'll take a look."
                                  : "Thanks. We'll take a look at this game.",
            symbol: "checkmark.shield")
    }

    /// The friend has sat down: there is someone to report.
    var canReport: Bool {
        guard let state, phase == .playing || phase == .over else { return false }
        return state[opponentSeat].seated
    }

    func askForRematch() async {
        if rematchStage == .ready, let code = state?.rematch?.code {
            switchToRematch(code)
            return
        }
        await act(.rematch)
    }

    @discardableResult
    private func act(_ action: ChallengeAction) async -> Bool {
        guard sending == nil else { return false }
        sending = action
        defer { sending = nil }
        do {
            apply(try await api.act(action, in: code, token: record.token))
            return true
        } catch is CancellationError {
        } catch let error as ChallengeError {
            if let game = error.game { apply(game) }
            if error.code != "game_over" {
                say(error.message, symbol: "exclamationmark.circle", warning: true)
            }
        } catch {
            say(ChallengeError.unreachable.message, symbol: "wifi.exclamationmark", warning: true)
        }
        return false
    }

    /// Fire and forget: presence and fair-play reports. The reply still brings the game up to date.
    private func report(_ action: ChallengeAction) {
        let code = record.code
        let token = record.token
        Task { [weak self, api] in
            guard let state = try? await api.act(action, in: code, token: token) else { return }
            self?.apply(state)
        }
    }

    // MARK: The server's state

    /// Takes a state from the server: a reply, the live connection or a fetch. Older ones are ignored.
    func apply(_ new: FriendGameState) {
        guard new.code == record.code else { return }
        if let old = state, Self.isOlder(new, than: old) { return }
        // A move the player has just made goes out before the board follows the server.
        noticeOwnMove()
        if serverClock == nil {
            serverClock = ChallengeServerClock(serverNow: new.now)
        } else {
            serverClock?.note(serverNow: new.now)
        }
        let previous = state
        state = new
        loadProblem = nil
        record.update(from: new)
        syncBoard(with: new, quietly: previous == nil)
        updatePhase(to: new)
        reclaimPresence(new)
        tellChanges(from: previous, to: new)
        scheduleDeadline()
        refreshIdleTimer()
        onChange?(record)
        if new.status == .over, let next = new.rematch?.code {
            switchToRematch(next)
        }
    }

    /// The server can think the player left while they're looking right at the board: the live connection
    /// dropped and polling doesn't count as being there, or the report of leaving arrived after the one of
    /// coming back. In a timed game the friend could soon claim the win, so the app says it's here, once per absence.
    private func reclaimPresence(_ new: FriendGameState) {
        guard isActive, connection != .elsewhere, new.status == .active,
              let away = new[seat].away, away != reclaimedAway,
              UIApplication.shared.applicationState == .active else { return }
        reclaimedAway = away
        report(.back)
    }

    /// Games only move forward: a state with fewer moves, an earlier status or an earlier time is old news.
    static func isOlder(_ new: FriendGameState, than old: FriendGameState) -> Bool {
        if new.status.rank != old.status.rank { return new.status.rank < old.status.rank }
        if new.moves.count != old.moves.count { return new.moves.count < old.moves.count }
        return new.now > 0 && old.now > 0 && new.now < old.now
    }

    private func updatePhase(to new: FriendGameState) {
        let next: Phase
        switch new.status {
        case .waiting: next = .waiting
        case .active: next = .playing
        case .over: next = .over
        }
        if next != .playing { lockBoard() }
        let colors: Set<Piece.Color> = next == .playing ? [seat.color] : []
        if match.game.humanColors != colors { match.game.humanColors = colors }
        let old = phase
        guard next != old else { return }
        phase = next
        if old == .waiting, next == .playing {
            say("\(opponentName) joined the game", symbol: "person.fill.checkmark")
        }
        // A recording already running when play begins is reported too: the game may have opened
        // before its state arrived, or started in the lobby, or as a rematch.
        if next == .playing, isActive, screenIsCaptured {
            report(.recording)
        }
        if next == .over {
            finish(new, seenLive: old == .playing)
        }
    }

    /// Nothing more can be done on the board: a pawn waiting to be promoted goes back, a selection lets go.
    private func lockBoard() {
        let game = match.game
        if game.pendingPromotion != nil { game.undo() }
        if let selected = game.selected, game.isHumanTurn { game.tap(selected) }
    }

    private func finish(_ state: FriendGameState, seenLive: Bool) {
        deadlineTask?.cancel()
        deadlineTask = nil
        // A game decided on the board already had its sound; one decided off it gets it now.
        if seenLive, let result = state.result, result.reason.wasPlayed, !match.game.isGameOver {
            sounds?.play(result.winner == seat ? .victory : .gameOver)
        }
        onFinish?(record, state)
    }

    /// Toasts for what changed on the friend's side. Every one of them is in the state, so they work
    /// the same over the live connection and when the game is fetched.
    private func tellChanges(from previous: FriendGameState?, to new: FriendGameState) {
        let them = new[opponentSeat]
        defer {
            toldShots = them.screenshots
            toldRecordings = them.recordings
        }
        guard let previous else { return }
        let before = previous[opponentSeat]
        if them.screenshots > toldShots {
            say("\(opponentName) took a screenshot", symbol: "camera.viewfinder", warning: true)
        } else if them.recordings > toldRecordings {
            say("\(opponentName) is recording the screen", symbol: "record.circle", warning: true)
        } else if before.away == nil, them.away != nil, FriendClockMath.leaveRuleApplies(new) {
            say("\(opponentName) left the game", symbol: "figure.walk.departure")
        } else if before.away != nil, them.away == nil, new.status == .active {
            say("\(opponentName) is back", symbol: "figure.walk.arrival")
        } else if previous.drawOffer == seat, new.drawOffer == nil, new.status == .active,
                  new.moves.count == previous.moves.count {
            say("\(opponentName) declined the draw", symbol: "equal.circle")
        }
    }

    private func say(_ text: String, symbol: String, warning: Bool = false) {
        nextToastID += 1
        let shown = Toast(id: nextToastID, text: text, symbol: symbol, isWarning: warning)
        toast = shown
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled, let self, self.toast?.id == shown.id else { return }
            self.toast = nil
        }
    }

    // MARK: The board

    /// A fresh board from the player's side, with nothing to tap until the game is under way.
    private func startBoard() {
        match.start(MatchController.Setup(opponent: .computer, playerColor: seat.color, level: .club,
                                          timeControl: .unlimited))
        match.game.humanColors = []
        boardMoves = []
        boardBase = 0
    }

    /// Watches the board for the player's own moves.
    private func watchBoard() {
        withObservationTracking {
            _ = match.game.moveCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.boardChanged()
            }
        }
    }

    private func boardChanged() {
        noticeOwnMove()
        watchBoard()
    }

    /// The player moved on the board: the move goes to the server with its place in the game.
    private func noticeOwnMove() {
        let game = match.game
        guard phase == .playing, pending == nil, game.pendingPromotion == nil,
              boardBase + game.moves.count == boardMoves.count + 1,
              let played = game.lastPlayed, played.color == seat.color else { return }
        let move = PendingMove(uci: played.uci, san: played.san, ply: boardMoves.count, at: serverNow())
        boardMoves.append(played.uci)
        pending = move
        moveTask?.cancel()
        moveTask = Task { [weak self] in
            await self?.send(move)
        }
    }

    /// Sends a move, trying again while the connection is down. A refusal puts the board back as the server has it.
    private func send(_ move: PendingMove) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                let new = try await api.move(code, uci: move.uci, ply: move.ply, token: record.token)
                if pending == move { pending = nil }
                apply(new)
                return
            } catch is CancellationError {
                return
            } catch let error as ChallengeError {
                // A newer state already settled it.
                guard pending == move else { return }
                if error.isRetryable, phase == .playing {
                    attempt += 1
                    try? await Task.sleep(for: .seconds(min(Double(attempt), 4)))
                    continue
                }
                pending = nil
                if let game = error.game { apply(game) } else { await refresh() }
                let stillOnBoard = boardMoves.indices.contains(move.ply) && boardMoves[move.ply] == move.uci
                if !stillOnBoard, error.code != "game_over" {
                    say(error.message, symbol: "arrow.uturn.backward.circle", warning: true)
                }
                return
            } catch {
                return
            }
        }
    }

    /// Brings the board to the server's moves, keeping the player's pending move while it is still on its way.
    private func syncBoard(with state: FriendGameState, quietly: Bool) {
        var target = state.moves
        if let pending {
            let waiting = state.status != .over && state.moves.count == pending.ply
                && boardMoves.count == pending.ply + 1 && boardMoves.starts(with: state.moves)
            if waiting {
                target.append(pending.uci)
            } else {
                // The server has moved past it: it took the move, or the game went on (or ended) without it.
                self.pending = nil
                moveTask?.cancel()
                moveTask = nil
            }
        }
        reconcile(to: target, quietly: quietly)
        // ChessKit can call a draw (a repetition, say) the server doesn't. The server decides: play on.
        if self.pending == nil, state.status == .active, match.game.isGameOver {
            rebuild(to: target, quietly: true)
        }
    }

    private func reconcile(to target: [String], quietly: Bool) {
        let game = match.game
        let common = zip(boardMoves, target).prefix { $0.0 == $0.1 }.count
        let extra = boardMoves.count - common
        let fresh = Array(target[common...])
        guard extra > 0 || !fresh.isEmpty else { return }
        // The board is about to change: a pawn waiting for its promotion goes back first.
        if game.pendingPromotion != nil { game.undo() }
        if extra > 0 {
            guard extra <= 2, extra <= game.moves.count else { return rebuild(to: target, quietly: true) }
            for _ in 0..<extra { game.undo() }
            boardMoves.removeLast(extra)
        }
        guard fresh.count == 1, let uci = fresh.first else {
            if !fresh.isEmpty { rebuild(to: target, quietly: true) }
            return
        }
        guard game.playEngineMove(uci) else { return rebuild(to: target, quietly: true) }
        boardMoves.append(uci)
        if !quietly, let played = game.lastPlayed { playSound(for: played) }
    }

    /// Sets the board up afresh: from the position before the last move, then that move, so it is
    /// marked as the last one played without every capture of the game bursting again.
    /// When the moves can't be replayed, the board takes the server's position as it stands.
    private func rebuild(to target: [String], quietly: Bool) {
        let game = match.game
        guard let last = target.last else {
            game.newGame()
            boardMoves = []
            boardBase = 0
            return
        }
        let head = target.dropLast()
        let scratch = GameModel()
        let replayed = head.allSatisfy { scratch.playEngineMove($0) }
        let before: Position? = head.isEmpty ? .standard : Position(fen: scratch.fen)
        if replayed, let before {
            game.newGame(from: before)
            if game.playEngineMove(last) {
                boardMoves = target
                boardBase = target.count - 1
                // Opening a game whose last move took a piece shouldn't burst it again: start from the position.
                if quietly, game.lastPlayed?.isCapture == true, let state, state.moves == target,
                   let now = Position(fen: state.fen) {
                    game.newGame(from: now)
                    boardBase = target.count
                }
                return
            }
        }
        // The server's position as it stands. A move of the player's still on its way comes back with its answer.
        let server = state?.moves ?? target
        if let fen = state?.fen, let position = Position(fen: fen) {
            game.newGame(from: position)
        } else {
            game.newGame()
        }
        if target.count > server.count { pending = nil }
        boardMoves = server
        boardBase = server.count
    }

    private func playSound(for played: PlayedMove) {
        guard let sounds else { return }
        let game = match.game
        if game.isGameOver {
            sounds.play(game.winner == seat.color ? .victory : .gameOver)
        } else if played.isCapture {
            sounds.play(.capture)
        } else if played.givesCheck {
            sounds.play(.check)
        } else if played.isCastle {
            sounds.play(.castle)
        } else {
            sounds.play(.move)
        }
    }

    // MARK: Rematch

    private func switchToRematch(_ next: String) {
        guard !isSwitching, next != record.code else { return }
        isSwitching = true
        Task { [weak self] in
            await self?.joinRematch(next)
        }
    }

    /// Both asked: the server made the new game with the colors swapped, and the same token holds the new seat.
    private func joinRematch(_ next: String) async {
        let name = myName
        for attempt in 0..<4 {
            do {
                let ticket = try await api.join(next, name: name, token: record.token)
                begin(next, seat: ticket.seat, token: ticket.token, game: ticket.game)
                return
            } catch let error as ChallengeError where error.isRetryable {
                try? await Task.sleep(for: .seconds(Double(attempt + 1)))
            } catch {
                break
            }
        }
        if let game = try? await api.game(next) {
            begin(next, seat: seat.opposite, token: record.token, game: game)
            return
        }
        isSwitching = false
        say("The rematch didn't open. Try again.", symbol: "exclamationmark.circle", warning: true)
    }

    private func begin(_ next: String, seat newSeat: FriendSeat, token: String, game: FriendGameState) {
        let wasActive = isActive
        disconnect()
        stopPolling()
        moveTask?.cancel()
        moveTask = nil
        pending = nil
        deadlineTask?.cancel()
        var fresh = FriendGame(code: next, token: token, seat: newSeat, state: game)
        if fresh.opponentName == nil { fresh.opponentName = record.opponentName }
        record = fresh
        state = nil
        phase = .loading
        serverClock = nil
        toldShots = 0
        toldRecordings = 0
        startBoard()
        isSwitching = false
        apply(game)
        if wasActive { connect() }
        say("New game · you play \(newSeat.name)", symbol: "arrow.triangle.2.circlepath")
    }

    // MARK: Deadlines

    /// When a clock runs out, the server ends the game. Look again just after, so the end shows at once
    /// even when the live connection is quiet. Leaving never ends a game: once the friend has been away
    /// past the grace period, the claim is offered instead.
    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduleClaim()
        guard isActive, let state, state.status == .active else { return }
        var deadlines: [Double] = []
        if let clocks = state.clocks, let running = clocks.running, let since = clocks.since {
            deadlines.append(since + clocks[running])
        }
        guard let first = deadlines.min() else { return }
        let now = serverNow()
        let overdue = now - first
        // Just after the deadline, then less and less often if the server is slow to call it.
        let wait = overdue < 0 ? -overdue / 1000 + 0.6 : min(0.6 + overdue / 2000, 5)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Offers the claim the moment the friend's grace period runs out, and takes it back when they return.
    private func scheduleClaim() {
        claimTask?.cancel()
        claimTask = nil
        guard phase == .playing, let state, let at = FriendClockMath.awayDeadline(state, seat: opponentSeat) else {
            claimReady = false
            return
        }
        let wait = (at - serverNow()) / 1000
        if wait <= 0 {
            claimReady = true
            return
        }
        claimReady = false
        claimTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.05))
            guard !Task.isCancelled, let self, self.phase == .playing else { return }
            self.claimReady = true
        }
    }

    // MARK: Live connection

    private func connect() {
        disconnect()
        guard isActive else { return }
        connection = .connecting
        startPolling()
        guard let live = api.live(code, token: record.token) else {
            connection = .offline
            return
        }
        live.onMessage = { [weak self] message in
            self?.receive(message)
        }
        live.onConnectionChange = { [weak self] connected in
            self?.connectionChanged(connected)
        }
        live.onEnd = { [weak self] end in
            self?.liveEnded(end)
        }
        self.live = live
        live.start()
    }

    private func disconnect() {
        live?.onMessage = nil
        live?.onConnectionChange = nil
        live?.onEnd = nil
        live?.stop()
        live = nil
    }

    /// The live connection won't come back by itself. The game is still fetched every few seconds.
    private func liveEnded(_ end: ChallengeLiveEnd) {
        disconnect()
        connection = end == .openElsewhere ? .elsewhere : .offline
        startPolling()
    }

    /// Takes the game back here after it was opened somewhere newer.
    func playHere() {
        guard isActive else { return }
        connect()
        if phase == .playing { report(.back) }
    }

    private func connectionChanged(_ connected: Bool) {
        connection = connected ? .live : .offline
        if connected { stopPolling() } else { startPolling() }
    }

    private func receive(_ message: ChallengeLiveMessage) {
        switch message {
        case .state(let state):
            apply(state)
        case .notice:
            // Everything a notice says is in the state as well; the toasts come from there.
            break
        }
    }

    private func startPolling() {
        guard pollTask == nil, isActive else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Leaving, screenshots and recordings

    private enum AppEvent: Sendable {
        case background, foreground, screenshot, capture
    }

    private func observe() {
        let center = NotificationCenter.default
        let events: [(Notification.Name, AppEvent)] = [
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .foreground),
            (UIApplication.userDidTakeScreenshotNotification, .screenshot),
            (UIScreen.capturedDidChangeNotification, .capture),
        ]
        for (name, event) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            }
            observers.append(observer)
        }
    }

    private func handle(_ event: AppEvent) {
        switch event {
        case .background:
            backgroundedAt = .now
            wentToBackground()
        case .foreground: cameToForeground()
        case .screenshot:
            if phase == .playing { report(.screenshot) }
        case .capture:
            if phase == .playing, screenIsCaptured { report(.recording) }
        }
    }

    private var screenIsCaptured: Bool {
        UIApplication.shared.connectedScenes.contains { ($0 as? UIWindowScene)?.screen.isCaptured == true }
    }

    /// The app went to the background: the server hears it at once, with a little time granted to say so.
    private func wentToBackground() {
        guard phase == .playing else { return }
        if leaveRuleApplies { leftAt = .now }
        let app = UIApplication.shared
        let backgroundTask = app.beginBackgroundTask(withName: "Friend game away", expirationHandler: nil)
        let code = record.code
        let token = record.token
        Task { [api] in
            _ = try? await api.act(.away, in: code, token: token)
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
    }

    private func cameToForeground() {
        // A connection that sat through a while in the background may look live and be dead.
        let wasAwayAWhile = backgroundedAt.map { Date.now.timeIntervalSince($0) >= Self.staleAfterBackground } ?? false
        defer {
            leftAt = nil
            backgroundedAt = nil
        }
        guard isActive, phase == .playing || phase == .waiting else { return }
        if phase == .playing {
            report(.back)
            if leftAt != nil, leaveRuleApplies {
                cameBack = true
                cameBackTask?.cancel()
                cameBackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    self?.cameBack = false
                }
            }
        }
        // A game taken up somewhere newer stays there until the player says otherwise.
        if connection != .elsewhere, connection != .live || wasAwayAWhile { connect() }
        Task { [weak self] in await self?.refresh() }
    }

    /// The screen stays awake in a timed game under way: locking it would be leaving.
    /// The game screen says it again as it appears, after whatever was on screen before let go.
    func refreshIdleTimer() {
        guard isActive else { return }
        UIApplication.shared.isIdleTimerDisabled = phase == .playing && isTimed
    }
}

/// Material counted against a full set of pieces, since the board may start from a position.
enum ChallengeMaterial {
    static let fullSet: [Piece.Kind: Int] = [.queen: 1, .rook: 2, .bishop: 2, .knight: 2, .pawn: 8]
    private static let values: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9]

    /// The other side's pieces `color` has taken, biggest first. Extra queens and the like are promoted pawns.
    static func captured(by color: Piece.Color, pieces: [Piece]) -> [CapturedCount] {
        var onBoard: [Piece.Kind: Int] = [:]
        for piece in pieces where piece.color == color.opposite && piece.kind != .king {
            onBoard[piece.kind, default: 0] += 1
        }
        let promoted = onBoard.reduce(0) { $0 + max(0, $1.value - (fullSet[$1.key] ?? 0)) }
        let order: [Piece.Kind] = [.queen, .rook, .bishop, .knight, .pawn]
        return order.compactMap { kind in
            var count = (fullSet[kind] ?? 0) - (onBoard[kind] ?? 0)
            if kind == .pawn { count -= promoted }
            return count > 0 ? CapturedCount(kind: kind, count: count) : nil
        }
    }

    /// How far ahead `color` is, in pawns.
    static func lead(for color: Piece.Color, pieces: [Piece]) -> Int {
        pieces.reduce(0) { $0 + (values[$1.kind] ?? 0) * ($1.color == color ? 1 : -1) }
    }
}
