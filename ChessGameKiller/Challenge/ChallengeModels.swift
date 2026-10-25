import ChessKit
import Foundation

// A friend game in the game server's words, decoded as play/PROTOCOL.md describes them.
// Fields the app doesn't know are ignored and missing ones fall back to sensible values,
// so a newer server never breaks an older app.

/// A side in a friend game, as the server names it.
enum FriendSeat: String, Codable, CaseIterable, Sendable {
    case white, black

    init(_ color: Piece.Color) {
        self = color == .white ? .white : .black
    }

    var color: Piece.Color { self == .white ? .white : .black }
    var opposite: FriendSeat { self == .white ? .black : .white }
    /// "White" or "Black". Friend games use the plain names, as the browser board and the invite do.
    var name: String { self == .white ? "White" : "Black" }
}

/// A friend game's time control: seconds each side starts with and seconds added a move.
/// A game with no clock has none of these (nil).
struct FriendClock: Codable, Hashable, Sendable {
    var initial: Int
    var increment: Int

    init(initial: Int, increment: Int) {
        self.initial = initial
        self.increment = increment
    }

    /// The server's clock for one of the app's time controls; nil for no clock.
    init?(_ control: TimeControl) {
        guard control.isTimed else { return nil }
        self.init(initial: Int(control.initial.components.seconds), increment: Int(control.increment.components.seconds))
    }

    /// The app's own time control, when this is one of them.
    var timeControl: TimeControl? {
        TimeControl.allCases.first { FriendClock($0) == self }
    }

    /// "10+0", "3+2".
    var label: String {
        let minutes = initial % 60 == 0 ? "\(initial / 60)" : String(format: "%.1f", Double(initial) / 60)
        return "\(minutes)+\(increment)"
    }

    /// "Blitz" or "Rapid", sorted the way the app's own clocks are.
    var kind: String {
        let estimate = initial + 40 * increment
        if estimate < 180 { return "Bullet" }
        if estimate < 480 { return "Blitz" }
        if estimate < 1500 { return "Rapid" }
        return "Classical"
    }

    /// "10 minutes each", "3 minutes each plus 2 seconds a move".
    var phrase: String {
        let minutes = initial / 60
        var text = initial % 60 == 0
            ? "\(minutes) minute\(minutes == 1 ? "" : "s") each"
            : "\(initial) seconds each"
        if increment > 0 {
            text += " plus \(increment) second\(increment == 1 ? "" : "s") a move"
        }
        return text
    }
}

/// One friend game as the server sends it: in every REST reply and over the live connection.
struct FriendGameState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Only the creator is seated.
        case waiting
        /// Both seated, not over.
        case active
        case over

        /// Games only ever move forward: waiting, then active, then over.
        var rank: Int {
            switch self {
            case .waiting: return 0
            case .active: return 1
            case .over: return 2
            }
        }
    }

    /// One seat at the table.
    struct Player: Codable, Equatable, Sendable {
        var name: String?
        var seated = false
        /// An open live connection, and not away.
        var online = false
        /// When the current absence began, in server milliseconds; nil while present.
        var away: Double?
        /// When the other side may claim the win because this one left, in server milliseconds;
        /// nil while present, or when the leave rule doesn't apply.
        var claimableAt: Double?
        var screenshots = 0
        var recordings = 0

        enum CodingKeys: String, CodingKey {
            case name, seated, online, away, claimableAt, screenshots, recordings
        }
    }

    /// Each side's time in milliseconds: the running side's as of `since`, the waiting side's exactly.
    struct Clocks: Codable, Equatable, Sendable {
        var white: Double
        var black: Double
        /// The side whose clock runs: nil until both sides have moved, and once the game is over.
        var running: FriendSeat?
        /// When the running clock last started, in server milliseconds.
        var since: Double?

        subscript(seat: FriendSeat) -> Double {
            seat == .white ? white : black
        }
    }

    struct Rematch: Codable, Equatable, Sendable {
        /// Who asked first.
        var by: FriendSeat?
        /// The new game, once both have asked. Each player's token works for their seat in it.
        var code: String?
    }

    struct Result: Codable, Equatable, Sendable {
        /// Nil for a draw, and for a game that never really happened.
        var winner: FriendSeat?
        var reason: Reason
    }

    /// Why a game ended.
    enum Reason: Hashable, Sendable, Codable {
        case checkmate, resign, timeout, left, stalemate, repetition, fiftyMoves, insufficient, agreement
        /// The flag fell, but the other side had nothing to mate with: a draw.
        case timeoutInsufficient
        /// Stopped before both sides moved.
        case aborted
        /// The creator withdrew before anyone joined.
        case cancelled
        /// Nobody joined within 7 days, or no move for 30 days.
        case expired
        /// A reason this version of the app doesn't know.
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "checkmate": self = .checkmate
            case "resign": self = .resign
            case "timeout": self = .timeout
            case "left": self = .left
            case "stalemate": self = .stalemate
            case "repetition": self = .repetition
            case "fifty_moves": self = .fiftyMoves
            case "insufficient": self = .insufficient
            case "agreement": self = .agreement
            case "timeout_insufficient": self = .timeoutInsufficient
            case "aborted": self = .aborted
            case "cancelled": self = .cancelled
            case "expired": self = .expired
            default: self = .other(rawValue)
            }
        }

        var rawValue: String {
            switch self {
            case .checkmate: return "checkmate"
            case .resign: return "resign"
            case .timeout: return "timeout"
            case .left: return "left"
            case .stalemate: return "stalemate"
            case .repetition: return "repetition"
            case .fiftyMoves: return "fifty_moves"
            case .insufficient: return "insufficient"
            case .agreement: return "agreement"
            case .timeoutInsufficient: return "timeout_insufficient"
            case .aborted: return "aborted"
            case .cancelled: return "cancelled"
            case .expired: return "expired"
            case .other(let raw): return raw
            }
        }

        /// A game was really played: one worth keeping with the player's games, and a rematch.
        var wasPlayed: Bool {
            switch self {
            case .aborted, .cancelled, .expired: return false
            default: return true
            }
        }

        init(from decoder: Decoder) throws {
            self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    var code: String
    var status: Status
    var createdAt: Double = 0
    var updatedAt: Double = 0
    var clock: FriendClock?
    /// The creator's seat.
    var creator: FriendSeat = .white
    var white = Player()
    var black = Player()
    /// Every move so far in engine notation ("e7e8q" for a promotion).
    var moves: [String] = []
    /// The same moves in standard notation.
    var san: [String] = []
    var fen = Position.standard.fen
    var turn: FriendSeat = .white
    var clocks: Clocks?
    /// The side offering a draw.
    var drawOffer: FriendSeat?
    var rematch: Rematch?
    var result: Result?
    /// How long someone may be away in a timed game before the other side may claim the win.
    var leaveGraceMs: Double = 60_000
    /// The server's time when it sent this, in milliseconds since 1970.
    var now: Double = 0

    enum CodingKeys: String, CodingKey {
        case code, status, createdAt, updatedAt, clock, creator, white, black, moves, san, fen, turn
        case clocks, drawOffer, rematch, result, leaveGraceMs, now
    }

    subscript(seat: FriendSeat) -> Player {
        get { seat == .white ? white : black }
        set {
            if seat == .white { white = newValue } else { black = newValue }
        }
    }
}

extension FriendGameState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code).uppercased()
        status = try c.decode(Status.self, forKey: .status)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        clock = try c.decodeIfPresent(FriendClock.self, forKey: .clock)
        creator = try c.decodeIfPresent(FriendSeat.self, forKey: .creator) ?? .white
        white = try c.decodeIfPresent(Player.self, forKey: .white) ?? Player()
        black = try c.decodeIfPresent(Player.self, forKey: .black) ?? Player()
        moves = try c.decodeIfPresent([String].self, forKey: .moves) ?? []
        san = try c.decodeIfPresent([String].self, forKey: .san) ?? []
        fen = try c.decodeIfPresent(String.self, forKey: .fen) ?? Position.standard.fen
        turn = try c.decodeIfPresent(FriendSeat.self, forKey: .turn) ?? (moves.count % 2 == 0 ? .white : .black)
        clocks = try c.decodeIfPresent(Clocks.self, forKey: .clocks)
        drawOffer = try c.decodeIfPresent(FriendSeat.self, forKey: .drawOffer)
        rematch = try c.decodeIfPresent(Rematch.self, forKey: .rematch)
        result = try c.decodeIfPresent(Result.self, forKey: .result)
        leaveGraceMs = try c.decodeIfPresent(Double.self, forKey: .leaveGraceMs) ?? 60_000
        now = try c.decodeIfPresent(Double.self, forKey: .now) ?? 0
    }
}

extension FriendGameState.Player {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        seated = try c.decodeIfPresent(Bool.self, forKey: .seated) ?? false
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? false
        away = try c.decodeIfPresent(Double.self, forKey: .away)
        claimableAt = try c.decodeIfPresent(Double.self, forKey: .claimableAt)
        screenshots = try c.decodeIfPresent(Int.self, forKey: .screenshots) ?? 0
        recordings = try c.decodeIfPresent(Int.self, forKey: .recordings) ?? 0
    }
}

// MARK: - Live messages

/// A moment the other side's screen may show as a toast.
struct ChallengeNotice: Equatable, Sendable {
    enum Kind: String, Sendable {
        case joined, screenshot, recording, away, back
        case drawOffer = "draw_offer"
        case drawDeclined = "draw_declined"
        case rematchOffer = "rematch_offer"
    }

    /// Nil for a kind this version of the app doesn't know.
    var kind: Kind?
    var seat: FriendSeat
    var at: Double = 0
}

extension ChallengeNotice: Decodable {
    enum CodingKeys: String, CodingKey {
        case kind, seat, at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: try c.decode(String.self, forKey: .kind))
        seat = try c.decode(FriendSeat.self, forKey: .seat)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

/// What the live connection sends.
enum ChallengeLiveMessage: Equatable, Sendable {
    case state(FriendGameState)
    case notice(ChallengeNotice)

    private struct Envelope: Decodable {
        let type: String
    }

    private struct StateMessage: Decodable {
        let game: FriendGameState
    }

    /// Reads one text frame. Nil for anything else, like the server's "pong".
    static func decode(_ text: String) -> ChallengeLiveMessage? {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.type {
        case "state":
            return (try? JSONDecoder().decode(StateMessage.self, from: data)).map { .state($0.game) }
        case "notice":
            return (try? JSONDecoder().decode(ChallengeNotice.self, from: data)).map { .notice($0) }
        default:
            return nil
        }
    }
}

// MARK: - Replies

/// A new challenge: its code and links, the creator's seat and token, and the game.
struct CreatedChallenge: Decodable, Equatable, Sendable {
    var code: String
    /// The https invite link.
    var url: String?
    /// The chessgamekiller:// link.
    var appUrl: String?
    var seat: FriendSeat
    var token: String
    var game: FriendGameState

    /// The link to send: the server's, or one made from the code.
    var inviteURL: URL {
        url.flatMap { URL(string: $0) } ?? ChallengeLink.inviteURL(for: code)
    }
}

/// A seat taken (or taken again, with a token that already holds it).
struct SeatTicket: Decodable, Equatable, Sendable {
    var seat: FriendSeat
    var token: String
    var game: FriendGameState
}

struct FriendGameReply: Decodable, Sendable {
    var game: FriendGameState
}

/// The server's "no": a code, plain words, and the game as it stands when it sent one.
struct ChallengeErrorReply: Decodable, Sendable {
    var error: String
    var message: String?
    var game: FriendGameState?

    enum CodingKeys: String, CodingKey {
        case error, message, game
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decode(String.self, forKey: .error)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        // A game the app can't read never hides the reason itself.
        game = (try? c.decodeIfPresent(FriendGameState.self, forKey: .game)) ?? nil
    }
}

/// Why a request to the game server didn't work, in words a person can act on.
enum ChallengeError: Error, Equatable, Sendable {
    /// The server said no: its HTTP status, its reason ("not_found", "seat_taken"…) and the game as it stands.
    case server(status: Int, code: String, message: String?, game: FriendGameState?)
    /// No connection, or the server didn't answer in time.
    case unreachable
    /// A reply the app couldn't read.
    case badReply

    var code: String? {
        if case .server(_, let code, _, _) = self { return code }
        return nil
    }

    var game: FriendGameState? {
        if case .server(_, _, _, let game) = self { return game }
        return nil
    }

    var isNotFound: Bool {
        if case .server(let status, let code, _, _) = self { return status == 404 || code == "not_found" }
        return false
    }

    /// Worth trying again in a moment: no connection, a busy server, too much at once.
    var isRetryable: Bool {
        switch self {
        case .unreachable: return true
        case .server(let status, let code, _, _): return status >= 500 || code == "rate_limited"
        case .badReply: return false
        }
    }

    var message: String {
        switch self {
        case .unreachable:
            return "Can't reach the game right now. Check your connection and try again."
        case .badReply:
            return "Something went wrong on the game server. Try again in a moment."
        case .server(_, let code, let message, _):
            switch code {
            case "not_found": return "There's no game with that code. Check it and try again."
            case "seat_taken": return "Someone else already took this seat."
            case "unauthorized": return "This game belongs to another device."
            case "not_your_turn": return "It isn't your move yet."
            case "stale": return "The game moved on. Your board is up to date again."
            case "game_over": return "This game is already over."
            case "illegal_move": return "That move isn't allowed here."
            case "rate_limited": return "That was a lot at once. Wait a moment and try again."
            case "server_error": return "Something went wrong on our side. Try again in a moment."
            case "cannot_claim": return message ?? "Your friend came back, so the game goes on."
            default: return message ?? "Something went wrong. Try again in a moment."
            }
        }
    }
}

// MARK: - Words

/// How a friend game ended, in plain words from one player's side of the board.
enum FriendResultWords {
    /// "Sam resigned. You win", "You lost on time", "Draw by repetition".
    static func headline(_ result: FriendGameState.Result, me: FriendSeat, opponent: String,
                         flagged: FriendSeat? = nil, creator: FriendSeat? = nil) -> String {
        let won = result.winner == me
        switch result.reason {
        case .checkmate: return won ? "Checkmate. You win" : "Checkmate. \(opponent) wins"
        case .resign: return won ? "\(opponent) resigned. You win" : "You resigned. \(opponent) wins"
        case .timeout: return won ? "\(opponent) ran out of time. You win" : "You lost on time"
        case .left: return won ? "\(opponent) left the game. You win" : "You were away too long. \(opponent) wins"
        case .stalemate: return "Draw by stalemate"
        case .repetition: return "Draw by repetition"
        case .fiftyMoves: return "Draw by the 50-move rule"
        case .insufficient: return "Draw. Neither side can checkmate"
        case .agreement: return "Draw by agreement"
        case .timeoutInsufficient:
            return flagged == me
                ? "Draw. Your time ran out, but \(opponent) couldn't mate"
                : "Draw. \(opponent)'s time ran out, but you couldn't mate"
        case .aborted: return "Game aborted"
        case .cancelled: return creator == me ? "You cancelled the challenge" : "\(opponent) cancelled the challenge"
        case .expired: return "This challenge expired"
        case .other:
            if let winner = result.winner { return winner == me ? "You win" : "\(opponent) wins" }
            return "Draw"
        }
    }

    /// For a list row: "You won · Checkmate", "Draw · Repetition", "Aborted".
    static func short(_ result: FriendGameState.Result, me: FriendSeat) -> String {
        let reason: String
        switch result.reason {
        case .checkmate: reason = "Checkmate"
        case .resign: reason = "Resignation"
        case .timeout, .timeoutInsufficient: reason = "On time"
        case .left: reason = "Left the game"
        case .stalemate: reason = "Stalemate"
        case .repetition: reason = "Repetition"
        case .fiftyMoves: reason = "50-move rule"
        case .insufficient: reason = "No mating material"
        case .agreement: reason = "Agreed"
        case .aborted: return "Aborted"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        case .other(let raw): reason = raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
        guard let winner = result.winner else { return "Draw · \(reason)" }
        return "\(winner == me ? "You won" : "You lost") · \(reason)"
    }

    /// Under the headline: "Rapid · 10+0 · 34 moves".
    static func detail(_ state: FriendGameState) -> String {
        var parts: [String] = []
        if let clock = state.clock {
            parts.append(clock.kind)
            parts.append(clock.label)
        } else {
            parts.append("No clock")
        }
        let moves = (state.moves.count + 1) / 2
        if moves > 0 { parts.append("\(moves) move\(moves == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

/// The words of an invite: the text message, the email and the share sheet.
enum ChallengeInviteText {
    /// "10 minutes each" or "No clock", capitalized to open a sentence.
    static func clockWords(_ clock: FriendClock?) -> String {
        guard let clock else { return "No clock" }
        let phrase = clock.phrase
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    /// "Alex challenged you to chess on Chess Game Killer. 10 minutes each, you play Black. Tap to play: …"
    static func message(from name: String, clock: FriendClock?, friendPlays side: FriendSeat, url: URL) -> String {
        "\(lead(from: name, clock: clock, friendPlays: side)) Tap to play: \(url.absoluteString)"
    }

    /// The message without its link, for the share sheet, which sends the link itself.
    static func lead(from name: String, clock: FriendClock?, friendPlays side: FriendSeat) -> String {
        "\(sender(name)) challenged you to chess on Chess Game Killer. \(clockWords(clock)), you play \(side.name)."
    }

    static func subject(from name: String) -> String {
        "\(sender(name)) challenged you to a game of chess"
    }

    static func emailBody(from name: String, clock: FriendClock?, friendPlays side: FriendSeat, url: URL, code: String) -> String {
        message(from: name, clock: clock, friendPlays: side, url: url)
            + "\n\nOr open Chess Game Killer and enter the code \(ChallengeLink.spaced(code))."
    }

    private static func sender(_ name: String) -> String {
        let clean = ChallengeName.clean(name)
        return clean.isEmpty ? "A friend" : clean
    }
}

/// The player's name as their friends see it: remembered between challenges.
enum ChallengeName {
    static let key = "challenge.name"
    static let maxLength = 24

    /// As the server cleans a name (play/src/util.js): every kind of space or line break becomes one
    /// plain space, control and invisible characters go, the ends are trimmed, and it is cut to 24 characters.
    static func clean(_ name: String) -> String {
        let space: Unicode.Scalar = " "
        var scalars: [Unicode.Scalar] = []
        for scalar in name.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.isWhitespace {
                // One space between words, none in front.
                if let last = scalars.last, last != space { scalars.append(space) }
            } else if !isUnwanted(scalar) {
                scalars.append(scalar)
            }
        }
        while let last = scalars.last, last == space { scalars.removeLast() }
        if scalars.count > maxLength {
            scalars.removeLast(scalars.count - maxLength)
            // A space or a joiner the cut left dangling goes too.
            while let last = scalars.last, last == space || last.value == 0x200D { scalars.removeLast() }
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Control characters, marks that flip the direction of text, and characters that show as nothing.
    private static func isUnwanted(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return true }
        switch scalar.value {
        case 0x061C, 0x115F, 0x1160, 0x180E, 0x200B, 0x200E, 0x200F, 0x202A...0x202E,
             0x2060...0x2064, 0x2066...0x2069, 0x3164, 0xFFA0:
            return true
        default:
            return false
        }
    }
}

// MARK: - Time

/// The server's time as this phone reckons it. Every state carries the server's `now`;
/// each reading is a little behind by the time it took to arrive, so the earliest-looking
/// one is kept (for half a minute at most, so the two clocks never drift apart).
struct ChallengeServerClock: Equatable, Sendable {
    private var serverMs: Double
    private var local: ContinuousClock.Instant

    init(serverNow: Double, at instant: ContinuousClock.Instant = .now) {
        serverMs = serverNow
        local = instant
    }

    /// The server's time at `instant`, in milliseconds since 1970.
    func now(at instant: ContinuousClock.Instant = .now) -> Double {
        serverMs + Self.milliseconds(instant - local)
    }

    mutating func note(serverNow: Double, at instant: ContinuousClock.Instant = .now) {
        let projected = now(at: instant)
        // A reading behind the one kept took longer to arrive: keep the older, unless it has grown old.
        if serverNow < projected, instant - local < .seconds(30) { return }
        serverMs = serverNow
        local = instant
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}

/// The clock arithmetic of a friend game, shared by the screen and the tests.
enum FriendClockMath {
    /// Milliseconds left for `seat` at server time `serverNow`, never below zero.
    static func remaining(_ clocks: FriendGameState.Clocks, for seat: FriendSeat, serverNow: Double) -> Double {
        let stored = clocks[seat]
        guard clocks.running == seat, let since = clocks.since else { return max(stored, 0) }
        return max(stored - max(serverNow - since, 0), 0)
    }

    /// "4:51", or "0:09.4" in the last ten seconds, as the app's own clocks show it.
    static func label(_ milliseconds: Double) -> String {
        Duration.milliseconds(max(milliseconds, 0)).clockLabel
    }

    /// Leaving counts only in a timed game under way once both sides have moved. It never ends the
    /// game by itself: after the grace period the other side may claim the win, or keep waiting.
    static func leaveRuleApplies(_ state: FriendGameState) -> Bool {
        state.clock != nil && state.status == .active && state.moves.count >= 2
    }

    /// When the other side may claim the win because `seat` left, in server milliseconds; nil when it isn't
    /// away or the rule doesn't apply. The server says so in `claimableAt`; an older server didn't, so it is worked out.
    /// An absence counts from when it began, but never from before the clocks started. One that began
    /// earlier can only still stand with exactly two moves played (a move ends it), and then the clocks
    /// started at the last move: `clocks.since`.
    static func awayDeadline(_ state: FriendGameState, seat: FriendSeat) -> Double? {
        guard leaveRuleApplies(state), let away = state[seat].away else { return nil }
        if let claimable = state[seat].claimableAt { return claimable }
        var start = away
        if state.moves.count == 2, let since = state.clocks?.since { start = max(away, since) }
        return start + state.leaveGraceMs
    }

    /// Whole seconds before the other side may claim the win from `seat`; nil when it isn't away or the rule doesn't apply.
    static func awaySecondsLeft(_ state: FriendGameState, seat: FriendSeat, serverNow: Double) -> Int? {
        guard let deadline = awayDeadline(state, seat: seat) else { return nil }
        let left = (deadline - serverNow) / 1000
        return max(0, Int(left.rounded(.up)))
    }
}
