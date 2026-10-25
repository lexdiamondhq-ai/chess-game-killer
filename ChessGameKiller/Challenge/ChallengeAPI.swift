import Foundation

/// Something a player does off the board, posted to `/api/games/{code}/action`.
enum ChallengeAction: String, Sendable {
    /// Before both sides have moved the server aborts instead.
    case resign
    /// Stops a game before both sides have moved.
    case abort
    /// The creator withdraws a challenge nobody has joined.
    case cancel
    case offerDraw = "offer_draw"
    case acceptDraw = "accept_draw"
    case declineDraw = "decline_draw"
    case rematch
    /// Presence: the app went to the background, or came back.
    case away, back
    /// Reported to the other side: a screenshot was taken, or screen recording started.
    case screenshot, recording
    /// The friend has been away past the grace period in a timed game: take the win.
    case claimWin = "claim_win"
    /// Reports about the friend. A name report hides their name at once.
    case reportName = "report_name"
    case reportCheating = "report_cheating"
}

/// The game server, as the app uses it. The live one talks to play/; tests use a fake.
@MainActor
protocol ChallengeAPI: AnyObject {
    /// Makes a challenge. `side` is the creator's; `clock` nil for no clock.
    func create(name: String, side: SideChoice, clock: FriendClock?) async throws -> CreatedChallenge
    func game(_ code: String) async throws -> FriendGameState
    /// Takes the open seat, or with a token that already holds one, gets that seat back.
    func join(_ code: String, name: String, token: String?) async throws -> SeatTicket
    /// `ply` is the number of half-moves already played: the index this move will have.
    func move(_ code: String, uci: String, ply: Int, token: String) async throws -> FriendGameState
    func act(_ action: ChallengeAction, in code: String, token: String) async throws -> FriendGameState
    /// The live connection for a seat, or nil when there is none to be had.
    func live(_ code: String, token: String) -> ChallengeLive?
}

/// A live connection to one game: every change as it happens, and the moments worth a toast.
@MainActor
protocol ChallengeLive: AnyObject {
    var onMessage: (@MainActor (ChallengeLiveMessage) -> Void)? { get set }
    /// True once messages arrive; false when the connection drops (it keeps trying again on its own).
    var onConnectionChange: (@MainActor (Bool) -> Void)? { get set }
    /// The connection stopped for good and won't try again.
    var onEnd: (@MainActor (ChallengeLiveEnd) -> Void)? { get set }
    func start()
    func stop()
}

/// Why a live connection stopped for good.
enum ChallengeLiveEnd: Equatable, Sendable {
    /// This seat opened a newer connection somewhere else (close code 4001). Trying again would only
    /// take the game away from there, so it is left to the player.
    case openElsewhere
    /// The server won't have it: a token that isn't for this game (401 at the upgrade), a game that
    /// isn't there (404), a watcher's place taken by a player (close code 4002), or any other final close.
    case refused
}

// MARK: - The live server

/// The game server over HTTPS, as play/PROTOCOL.md describes it.
@MainActor
final class LiveChallengeAPI: ChallengeAPI {
    private let base: URL
    private let session: URLSession

    init(base: URL = ChallengeLink.serverURL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    func create(name: String, side: SideChoice, clock: FriendClock?) async throws -> CreatedChallenge {
        try await send("POST", "api/games", body: CreateBody(name: name, side: side.rawValue, clock: clock))
    }

    func game(_ code: String) async throws -> FriendGameState {
        let reply: FriendGameReply = try await send("GET", "api/games/\(code)")
        return reply.game
    }

    func join(_ code: String, name: String, token: String?) async throws -> SeatTicket {
        try await send("POST", "api/games/\(code)/join", body: NameBody(name: name), token: token)
    }

    func move(_ code: String, uci: String, ply: Int, token: String) async throws -> FriendGameState {
        let reply: FriendGameReply = try await send("POST", "api/games/\(code)/move", body: MoveBody(uci: uci, ply: ply), token: token)
        return reply.game
    }

    func act(_ action: ChallengeAction, in code: String, token: String) async throws -> FriendGameState {
        let reply: FriendGameReply = try await send("POST", "api/games/\(code)/action", body: ActionBody(type: action.rawValue), token: token)
        return reply.game
    }

    func live(_ code: String, token: String) -> ChallengeLive? {
        guard let url = Self.liveURL(base: base, code: code, token: token) else { return nil }
        return ChallengeSocket(url: url, session: session)
    }

    /// Seconds to wait from a Retry-After header: a number of seconds, one second when it says nothing usable.
    nonisolated static func retryAfter(_ header: String?) -> Double {
        guard let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite else { return 1 }
        return max(seconds, 0.25)
    }

    /// The longest Retry-After the app waits out by itself before saying so.
    nonisolated static var longestRetryWait: Double { 10 }

    /// `wss://…/api/games/{code}/live?token=…`
    nonisolated static func liveURL(base: URL, code: String, token: String) -> URL? {
        guard var components = URLComponents(url: base.appending(path: "api/games/\(code)/live"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    // MARK: Requests

    private struct CreateBody: Encodable {
        let name: String
        let side: String
        let clock: FriendClock?

        enum CodingKeys: String, CodingKey {
            case name, side, clock
        }

        // No clock is sent as an explicit null, as the protocol spells it.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(side, forKey: .side)
            try container.encode(clock, forKey: .clock)
        }
    }

    private struct NameBody: Encodable {
        let name: String
    }

    private struct MoveBody: Encodable {
        let uci: String
        let ply: Int
    }

    private struct ActionBody: Encodable {
        let type: String
    }

    private func send<Reply: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil,
                                        token: String? = nil, retried: Bool = false) async throws -> Reply {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ChallengeError.unreachable
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw ChallengeError.badReply }
        guard (200..<300).contains(http.statusCode) else {
            // Too much at once: wait as long as the server asks (when that's short) and try once more.
            if http.statusCode == 429, !retried {
                let wait = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"))
                if wait <= Self.longestRetryWait {
                    try await Task.sleep(for: .seconds(wait))
                    return try await send(method, path, body: body, token: token, retried: true)
                }
            }
            let reply = try? JSONDecoder().decode(ChallengeErrorReply.self, from: data)
            throw ChallengeError.server(status: http.statusCode, code: reply?.error ?? "http_\(http.statusCode)",
                                        message: reply?.message, game: reply?.game)
        }
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw ChallengeError.badReply
        }
    }
}

// MARK: - The live connection

/// One game's WebSocket: reads every message, says "ping" every 20 seconds as the server asks,
/// and when the connection drops, tries again a moment later (sooner at first, then up to every 15 seconds).
@MainActor
final class ChallengeSocket: ChallengeLive {
    var onMessage: (@MainActor (ChallengeLiveMessage) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onEnd: (@MainActor (ChallengeLiveEnd) -> Void)?

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private(set) var isConnected = false
    private var failures = 0
    /// When the server was last heard from. It answers every ping, so a long silence means a dead connection.
    private var lastHeard: ContinuousClock.Instant = .now

    static let pingInterval: Duration = .seconds(20)
    /// Two pings unanswered: the connection is dropped and opened again, even if it never reported an error.
    static let silenceLimit: Duration = .seconds(30)

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func start() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        pinger?.cancel()
        pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setConnected(false)
    }

    /// The delay before trying again after `failures` failures in a row: 0.5 s, 1 s, 2 s… up to 15 s.
    nonisolated static func retryDelay(after failures: Int) -> Double {
        min(0.5 * pow(2, Double(max(failures, 1) - 1)), 15)
    }

    /// A close the connection must not come back from: the server's close code (every one from 4000 to 4999
    /// is final), or the HTTP status of a refused upgrade.
    nonisolated static func end(closeCode: Int, httpStatus: Int?) -> ChallengeLiveEnd? {
        switch closeCode {
        case 4001: return .openElsewhere
        case 4000...4999: return .refused
        default: break
        }
        switch httpStatus {
        case 401?, 403?, 404?: return .refused
        default: return nil
        }
    }

    private func run() async {
        while !Task.isCancelled {
            let socket = session.webSocketTask(with: url)
            task = socket
            socket.resume()
            ping(socket)
            await read(socket)
            pinger?.cancel()
            pinger = nil
            // The server's close message is final as it arrives; there's no waiting for the connection to wind down.
            let status = (socket.response as? HTTPURLResponse)?.statusCode
            let end = Self.end(closeCode: socket.closeCode.rawValue, httpStatus: status)
            socket.cancel(with: .goingAway, reason: nil)
            if task === socket { task = nil }
            setConnected(false)
            guard !Task.isCancelled else { return }
            if let end {
                onEnd?(end)
                return
            }
            failures += 1
            // A refused upgrade for having too many connections waits longer before the next try.
            let delay = status == 429 ? 15 : Self.retryDelay(after: failures)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Reads until the connection closes or fails.
    private func read(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                return
            }
            failures = 0
            lastHeard = .now
            setConnected(true)
            let text: String?
            switch message {
            case .string(let string): text = string
            case .data(let data): text = String(data: data, encoding: .utf8)
            @unknown default: text = nil
            }
            if let text, let decoded = ChallengeLiveMessage.decode(text) {
                onMessage?(decoded)
            }
        }
    }

    private func ping(_ socket: URLSessionWebSocketTask) {
        pinger?.cancel()
        lastHeard = .now
        pinger = Task { [weak self, weak socket] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pingInterval)
                guard !Task.isCancelled, let self, let socket else { return }
                // A connection can go dead without failing (a network change, say): no pong, no moves.
                // Cancelling it ends the read, and the run loop opens a new one.
                if ContinuousClock.now - self.lastHeard > Self.silenceLimit {
                    socket.cancel(with: .goingAway, reason: nil)
                    return
                }
                try? await socket.send(.string("ping"))
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChange?(connected)
    }
}
