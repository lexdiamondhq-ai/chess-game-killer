import ChessKit
import Foundation
import XCTest
@testable import ChessGameKiller

/// The game server, played by the test: games kept in memory, replies scripted where a test needs
/// them, and every request written down. Nothing here touches the network.
@MainActor
final class FakeChallengeAPI: ChallengeAPI {
    struct CreateRequest: Equatable {
        let name: String
        let side: SideChoice
        let clock: FriendClock?
    }

    struct JoinRequest: Equatable {
        let code: String
        let name: String
        let token: String?
    }

    struct MoveRequest: Equatable {
        let code: String
        let uci: String
        let ply: Int
        let token: String
    }

    struct ActionRequest: Equatable {
        let action: ChallengeAction
        let code: String
        let token: String
    }

    /// The games the server knows, by code.
    var games: [String: FriendGameState] = [:]
    /// The reply to a create.
    var created: CreatedChallenge?
    /// The reply to a join, by code.
    var tickets: [String: SeatTicket] = [:]
    /// Replaces the server's own handling of a move.
    var moveReply: ((MoveRequest) throws -> FriendGameState)?
    /// Replaces the server's own handling of an action.
    var actionReply: ((ActionRequest) throws -> FriendGameState)?
    /// Thrown by every request while set.
    var failure: ChallengeError?
    /// Thrown by a join while set.
    var joinError: ChallengeError?
    /// Whether `live` hands out a connection.
    var offersLive = true

    private(set) var creates: [CreateRequest] = []
    private(set) var fetches: [String] = []
    private(set) var joins: [JoinRequest] = []
    private(set) var moves: [MoveRequest] = []
    private(set) var actions: [ActionRequest] = []
    private(set) var lives: [FakeLive] = []

    static let notFound = ChallengeError.server(status: 404, code: "not_found", message: nil, game: nil)

    func create(name: String, side: SideChoice, clock: FriendClock?) async throws -> CreatedChallenge {
        creates.append(CreateRequest(name: name, side: side, clock: clock))
        if let failure { throw failure }
        guard let created else { throw ChallengeError.unreachable }
        games[created.code] = created.game
        return created
    }

    func game(_ code: String) async throws -> FriendGameState {
        fetches.append(code)
        if let failure { throw failure }
        guard let game = games[code] else { throw Self.notFound }
        return game
    }

    func join(_ code: String, name: String, token: String?) async throws -> SeatTicket {
        joins.append(JoinRequest(code: code, name: name, token: token))
        if let failure = failure ?? joinError { throw failure }
        guard let ticket = tickets[code] else { throw Self.notFound }
        games[code] = ticket.game
        return ticket
    }

    func move(_ code: String, uci: String, ply: Int, token: String) async throws -> FriendGameState {
        let request = MoveRequest(code: code, uci: uci, ply: ply, token: token)
        moves.append(request)
        if let failure { throw failure }
        if let moveReply {
            let state = try moveReply(request)
            games[code] = state
            return state
        }
        guard let game = games[code] else { throw Self.notFound }
        guard ply == game.moves.count else {
            throw ChallengeError.server(status: 409, code: "stale", message: nil, game: game)
        }
        let next = game.playing(uci)
        games[code] = next
        return next
    }

    func act(_ action: ChallengeAction, in code: String, token: String) async throws -> FriendGameState {
        let request = ActionRequest(action: action, code: code, token: token)
        actions.append(request)
        if let failure { throw failure }
        if let actionReply {
            let state = try actionReply(request)
            games[code] = state
            return state
        }
        guard let game = games[code] else { throw Self.notFound }
        return game
    }

    func live(_ code: String, token: String) -> ChallengeLive? {
        guard offersLive else { return nil }
        let live = FakeLive(code: code)
        lives.append(live)
        return live
    }

    /// The actions asked for, in order, without presence and fair-play reports.
    var playerActions: [ChallengeAction] {
        let reports: Set<ChallengeAction> = [.away, .back, .screenshot, .recording]
        return actions.map(\.action).filter { !reports.contains($0) }
    }
}

/// A live connection the test speaks through.
@MainActor
final class FakeLive: ChallengeLive {
    let code: String
    var onMessage: (@MainActor (ChallengeLiveMessage) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onEnd: (@MainActor (ChallengeLiveEnd) -> Void)?
    private(set) var isStarted = false
    private(set) var isStopped = false

    init(code: String) {
        self.code = code
    }

    func start() {
        isStarted = true
    }

    func stop() {
        isStopped = true
    }

    /// The server sends the game as it now stands.
    func push(_ state: FriendGameState) {
        onConnectionChange?(true)
        onMessage?(.state(state))
    }

    /// The server closes the connection for good.
    func end(_ end: ChallengeLiveEnd) {
        onEnd?(end)
    }
}

extension FriendGameState {
    /// The server's clock in these tests: a fixed moment, so nothing depends on when they run.
    static let sampleNow: Double = 1_760_000_000_000

    /// A game as the server would send it, the moves replayed for their notation and position.
    /// Both players are seated (and online) unless the game is still waiting.
    static func sample(code: String = "7KQ2XM", status: Status = .active, moves: [String] = [],
                       clock: FriendClock? = FriendClock(initial: 600, increment: 0),
                       creator: FriendSeat = .white, white: String? = "Alex", black: String? = "Sam",
                       now: Double = sampleNow) -> FriendGameState {
        var state = FriendGameState(code: code, status: status)
        state.createdAt = now - 600_000
        state.updatedAt = now
        state.clock = clock
        state.creator = creator
        let seated: (FriendSeat) -> Bool = { status != .waiting || $0 == creator }
        state.white = Player(name: seated(.white) ? white : nil, seated: seated(.white), online: seated(.white))
        state.black = Player(name: seated(.black) ? black : nil, seated: seated(.black), online: seated(.black))
        state.now = now
        state.setMoves(moves)
        return state
    }

    /// The same game with one more move, as the server answers a move.
    func playing(_ uci: String, at time: Double? = nil) -> FriendGameState {
        var next = self
        let now = time ?? self.now + 3_000
        // The side that moved stops its clock and gets its increment; then the other side's starts.
        if var clocks = next.clocks, let clock = next.clock, clocks.running == turn {
            let left = FriendClockMath.remaining(clocks, for: turn, serverNow: now) + Double(clock.increment * 1000)
            if turn == .white { clocks.white = left } else { clocks.black = left }
            next.clocks = clocks
        }
        next.now = now
        next.updatedAt = now
        next.setMoves(moves + [uci])
        return next
    }

    /// Sets the moves, with the notation, position, side to move and clocks that follow from them.
    mutating func setMoves(_ list: [String]) {
        let replay = GameModel()
        var legal: [String] = []
        for move in list {
            guard replay.playEngineMove(move) else {
                XCTFail("\(move) isn't legal after \(legal)")
                break
            }
            legal.append(move)
        }
        moves = legal
        san = replay.moves
        fen = replay.fen
        turn = FriendSeat(replay.sideToMove)
        guard let clock else {
            clocks = nil
            return
        }
        let full = Double(clock.initial * 1000)
        var next = clocks ?? Clocks(white: full, black: full, running: nil, since: nil)
        // No clock runs until both sides have moved, nor once the game is over.
        if status == .active, legal.count >= 2 {
            next.running = turn
            next.since = now
        } else {
            next.running = nil
            next.since = nil
        }
        clocks = next
    }
}

extension FriendGame {
    /// The player's record of a game, for the seat given.
    static func sample(_ state: FriendGameState, seat: FriendSeat) -> FriendGame {
        FriendGame(code: state.code, token: "token-\(seat.rawValue)", seat: seat, state: state)
    }
}

/// Collects what a callback hands over, for a test to look at.
@MainActor
final class Recorder<Value> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}
