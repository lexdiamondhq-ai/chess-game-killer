import Foundation
import Observation

/// Challenge a friend, for the whole app: the friend games on this phone, the links that open
/// them, and which of its screens is up (the composer, an invite, or a game).
/// The app owns one and puts it in the environment; `challengeHost()` shows its screens.
@MainActor
@Observable
final class ChallengeCenter {
    enum Screen {
        /// Making a challenge, and sending it.
        case composer(ChallengeComposer)
        /// A friend's challenge, opened from its link.
        case invite(ChallengeInvite)
        /// A game: the lobby while nobody has joined, then the board.
        case game(OnlineGame)

        /// Tells the screens apart, so moving between them is animated and each starts fresh.
        var key: String {
            switch self {
            case .composer: return "composer"
            case .invite(let invite): return "invite-\(invite.code)"
            case .game(let game): return "game-\(ObjectIdentifier(game).hashValue)"
            }
        }
    }

    private(set) var screen: Screen? = nil
    /// One of the screens is up (or about to be).
    var isPresenting: Bool { screen != nil }

    let store: ChallengeStore
    @ObservationIgnored let api: ChallengeAPI
    @ObservationIgnored private let sounds: SoundPlaying?
    @ObservationIgnored private let defaults: UserDefaults
    /// A finished friend game, to keep with the player's games. ContentView keeps it in its vault,
    /// the only place games.json is written from.
    @ObservationIgnored var onGameFinished: (@MainActor (SavedGame) -> Void)?
    @ObservationIgnored private var lastRefresh: Date?
    /// A link opened during a timed game: it opens once that game is closed.
    @ObservationIgnored private(set) var heldCode: String?

    /// The list is fetched again at most this often, unless asked.
    static let refreshInterval: TimeInterval = 15

    init(api: ChallengeAPI, store: ChallengeStore, sounds: SoundPlaying?, defaults: UserDefaults = .standard) {
        self.api = api
        self.store = store
        self.sounds = sounds
        self.defaults = defaults
    }

    /// The app's: the real server, the friend games saved on this phone and the bundled sounds.
    static func live() -> ChallengeCenter {
        ChallengeCenter(api: LiveChallengeAPI(), store: .live(), sounds: SoundPlayer.shared)
    }

    // MARK: The player's name

    /// The name friends see, remembered from the last challenge.
    var playerName: String {
        defaults.string(forKey: ChallengeName.key) ?? ""
    }

    func rememberName(_ name: String) {
        let clean = ChallengeName.clean(name)
        guard !clean.isEmpty else { return }
        defaults.set(clean, forKey: ChallengeName.key)
    }

    // MARK: Screens

    /// Opens the composer: pick a clock and a side, then send the link.
    func compose() {
        leaveScreen(keeping: nil)
        screen = .composer(ChallengeComposer(center: self))
    }

    /// Opens a challenge link: `https://play.chess-game-killer.workers.dev/c/CODE` or `chessgamekiller://c/CODE`.
    /// False for a link that isn't one.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let code = ChallengeLink.code(from: url) else { return false }
        open(code: code)
        return true
    }

    /// Opens a game by its code: one of the player's own straight away, anyone else's as an invite.
    func open(code text: String) {
        guard let code = ChallengeLink.code(fromText: text) else { return }
        if case .game(let game)? = screen, game.code == code { return }
        // Leaving a timed game under way lets the friend claim the win after a minute, so the link waits for it to close.
        if case .game(let game)? = screen, game.phase == .playing, game.isTimed {
            heldCode = code
            game.notify("Finish this game first. The other challenge opens after it.", symbol: "hourglass")
            return
        }
        if let record = store.game(code: code) {
            play(record)
            return
        }
        if case .invite(let invite)? = screen, invite.code == code { return }
        leaveScreen(keeping: nil)
        let invite = ChallengeInvite(code: code, center: self)
        screen = .invite(invite)
        Task { await invite.load() }
    }

    /// Opens one of the player's friend games.
    func play(_ record: FriendGame, initial: FriendGameState? = nil) {
        if case .game(let game)? = screen, game.code == record.code { return }
        show(makeGame(record, initial: initial))
    }

    /// Puts a game on screen: live, watched for leaving and screenshots.
    func show(_ game: OnlineGame) {
        if case .game(let current)? = screen, current === game { return }
        leaveScreen(keeping: game)
        screen = .game(game)
        game.activate()
    }

    /// A game wired to the list: every change is saved, and a finished game is kept with the player's games.
    func makeGame(_ record: FriendGame, initial: FriendGameState? = nil) -> OnlineGame {
        let game = OnlineGame(record: record, api: api, sounds: sounds)
        game.onChange = { [weak self, weak game] record in
            guard let self else { return }
            self.store.add(record)
            // The friend opened the link while the player was still sending it: on to the board.
            if let game, case .composer(let composer)? = self.screen, composer.game === game, game.phase != .waiting {
                self.show(game)
            }
        }
        game.onFinish = { [weak self] record, state in
            self?.keep(record, state)
        }
        if let initial { game.apply(initial) }
        return game
    }

    /// Closes the screens. A game under way is left (in a timed game, away past a minute the friend can claim the win).
    func dismiss() {
        leaveScreen(keeping: nil)
        screen = nil
        if let held = heldCode {
            heldCode = nil
            open(code: held)
        }
    }

    /// Takes a finished game off the list. Games still going stay.
    func remove(_ record: FriendGame) {
        guard record.isOver || store.game(code: record.code)?.isOver == true else { return }
        store.remove(code: record.code)
    }

    private func leaveScreen(keeping kept: OnlineGame?) {
        switch screen {
        case .game(let game)? where game !== kept:
            game.deactivate()
        case .composer(let composer)?:
            if let waiting = composer.game, waiting !== kept { waiting.deactivate() }
        default:
            break
        }
    }

    // MARK: The list

    /// Brings the unfinished games up to date: whose move it is, and which ended meanwhile.
    /// At most every 15 seconds unless `force`d.
    func refreshGames(force: Bool = false) async {
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        lastRefresh = .now
        // Games still going, and finished ones not yet kept with the player's games.
        let due = store.games.filter { !$0.isOver || !$0.recorded }
        for record in due {
            if case .game(let game)? = screen, game.code == record.code { continue }
            do {
                let state = try await api.game(record.code)
                if let updated = store.update(code: record.code, from: state), updated.isOver {
                    keep(updated, state)
                }
            } catch let error as ChallengeError where error.isNotFound {
                if record.isOver {
                    store.markRecorded(code: record.code)
                } else {
                    // The server no longer has it: a challenge nobody took, long expired.
                    var expired = record
                    expired.status = .over
                    expired.result = FriendGameState.Result(winner: nil, reason: .expired)
                    expired.updatedAt = .now
                    expired.recorded = true
                    store.add(expired)
                }
            } catch {
                return
            }
        }
    }

    /// Keeps a finished game with the player's games, once.
    private func keep(_ record: FriendGame, _ state: FriendGameState) {
        guard store.game(code: record.code)?.recorded != true else { return }
        let date = state.updatedAt > 0 ? Date(timeIntervalSince1970: state.updatedAt / 1000) : Date.now
        let opponent = state[record.seat.opposite].name.map(ChallengeName.clean).flatMap { $0.isEmpty ? nil : $0 }
            ?? record.opponentName ?? "Friend"
        guard let saved = FriendGameArchive.savedGame(state, seat: record.seat, id: record.id, date: date, opponent: opponent) else {
            // Nothing to keep: aborted, cancelled, or expired.
            store.markRecorded(code: record.code)
            return
        }
        // Until the game screen has hooked up its vault, the game waits to be kept next time.
        guard let onGameFinished else { return }
        onGameFinished(saved)
        store.markRecorded(code: record.code)
    }
}

/// The composer's work: making the challenge, and the lobby game that starts the moment it exists.
@MainActor
@Observable
final class ChallengeComposer {
    private(set) var created: FriendGame? = nil
    private(set) var link: URL? = nil
    private(set) var isCreating = false
    private(set) var problem: String? = nil
    /// The new challenge, live from the start, so a friend joining is seen at once.
    private(set) var game: OnlineGame? = nil

    @ObservationIgnored private weak var center: ChallengeCenter?

    init(center: ChallengeCenter) {
        self.center = center
    }

    /// The side the friend plays.
    var friendSeat: FriendSeat? { created?.seat.opposite }

    func create(name: String, clock: FriendClock?, side: SideChoice) async {
        guard !isCreating, created == nil, let center else { return }
        isCreating = true
        problem = nil
        defer { isCreating = false }
        center.rememberName(name)
        do {
            let reply = try await center.api.create(name: ChallengeName.clean(name), side: side, clock: clock)
            let record = FriendGame(code: reply.code, token: reply.token, seat: reply.seat, state: reply.game)
            center.store.add(record)
            // Closed while the challenge was being made: it waits in Friend games, with nothing left running.
            guard case .composer(let shown)? = center.screen, shown === self else { return }
            let game = center.makeGame(record, initial: reply.game)
            game.activate()
            self.game = game
            link = reply.inviteURL
            created = record
        } catch is CancellationError {
        } catch let error as ChallengeError {
            problem = error.message
        } catch {
            problem = ChallengeError.unreachable.message
        }
    }

    /// On to the lobby: the board, waiting for the friend.
    func goToBoard() {
        guard let game else { return }
        center?.show(game)
    }
}

/// A friend's challenge, opened from its link: what it is, and taking the seat.
@MainActor
@Observable
final class ChallengeInvite {
    enum Stage: Equatable {
        case loading
        case ready(FriendGameState)
        /// Taken, cancelled, expired, over, or no such game.
        case unavailable(title: String, detail: String)
        /// The server couldn't be reached.
        case failed(String)
    }

    let code: String
    private(set) var stage: Stage = .loading
    private(set) var isJoining = false
    private(set) var joinProblem: String? = nil

    @ObservationIgnored private weak var center: ChallengeCenter?

    init(code: String, center: ChallengeCenter) {
        self.code = code
        self.center = center
    }

    /// The challenger's name.
    var host: String {
        guard case .ready(let state) = stage else { return "Your friend" }
        return Self.name(of: state.creator, in: state)
    }

    func load() async {
        guard let center else { return }
        stage = .loading
        do {
            stage = Self.stage(for: try await center.api.game(code))
        } catch let error as ChallengeError {
            stage = error.isNotFound
                ? .unavailable(title: "No game with this code",
                               detail: "Check the code and try again. A challenge nobody takes expires after 7 days.")
                : .failed(error.message)
        } catch {
            stage = .failed(ChallengeError.unreachable.message)
        }
    }

    func accept(name: String) async {
        guard let center, !isJoining, case .ready = stage else { return }
        isJoining = true
        joinProblem = nil
        defer { isJoining = false }
        center.rememberName(name)
        do {
            let ticket = try await center.api.join(code, name: ChallengeName.clean(name), token: nil)
            let record = FriendGame(code: code, token: ticket.token, seat: ticket.seat, state: ticket.game)
            center.store.add(record)
            center.play(record, initial: ticket.game)
        } catch is CancellationError {
        } catch let error as ChallengeError {
            if error.code == "seat_taken" {
                stage = .unavailable(title: "This challenge was taken", detail: "Someone else accepted it first.")
            } else if let game = error.game, game.status != .waiting {
                stage = Self.stage(for: game)
            } else if error.code == "game_over" {
                stage = .unavailable(title: "This game is over", detail: "Ask \(host) for a new link to play again.")
            } else if error.isNotFound {
                stage = .unavailable(title: "No game with this code", detail: "The challenge isn't on the server any more.")
            } else {
                joinProblem = error.message
            }
        } catch {
            joinProblem = ChallengeError.unreachable.message
        }
    }

    /// What the invite screen shows for a game as it stands.
    static func stage(for state: FriendGameState) -> Stage {
        let host = name(of: state.creator, in: state)
        switch state.status {
        case .waiting:
            return .ready(state)
        case .active:
            return .unavailable(title: "This challenge was taken",
                                detail: "Someone already accepted it. Ask \(host) for a new link.")
        case .over:
            switch state.result?.reason {
            case .cancelled?:
                return .unavailable(title: "\(host) cancelled this challenge", detail: "Ask \(host) for a new link.")
            case .expired?:
                return .unavailable(title: "This challenge expired",
                                    detail: "Nobody took it within 7 days. Ask \(host) for a new link.")
            default:
                return .unavailable(title: "This game is over", detail: "Ask \(host) for a new link to play again.")
            }
        }
    }

    private static func name(of seat: FriendSeat, in state: FriendGameState) -> String {
        let clean = state[seat].name.map(ChallengeName.clean) ?? ""
        return clean.isEmpty ? "Your friend" : clean
    }
}
