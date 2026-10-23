import ChessKit
import Foundation
import Observation

/// One friend game on this phone: the seat and token that prove it is ours, and enough
/// about the game to list it ("vs Sam · Your move") without asking the server.
struct FriendGame: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var code: String
    /// The only proof of the seat. Never shown, never shared.
    var token: String
    var seat: FriendSeat
    /// This phone made the challenge.
    var isCreator: Bool
    var opponentName: String?
    var clock: FriendClock?
    var status: FriendGameState.Status
    var turn: FriendSeat
    var result: FriendGameState.Result?
    var moveCount: Int
    var createdAt: Date
    var updatedAt: Date
    /// Already kept with the player's games, so it is saved once.
    var recorded: Bool

    init(id: UUID = UUID(), code: String, token: String, seat: FriendSeat, isCreator: Bool,
         opponentName: String? = nil, clock: FriendClock? = nil, status: FriendGameState.Status = .waiting,
         turn: FriendSeat = .white, result: FriendGameState.Result? = nil, moveCount: Int = 0,
         createdAt: Date = .now, updatedAt: Date = .now, recorded: Bool = false) {
        self.id = id
        self.code = code
        self.token = token
        self.seat = seat
        self.isCreator = isCreator
        self.opponentName = opponentName
        self.clock = clock
        self.status = status
        self.turn = turn
        self.result = result
        self.moveCount = moveCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recorded = recorded
    }

    /// A record for a game as the server sent it.
    init(code: String, token: String, seat: FriendSeat, state: FriendGameState, id: UUID = UUID()) {
        self.init(id: id, code: code, token: token, seat: seat, isCreator: state.creator == seat)
        update(from: state)
        createdAt = state.createdAt > 0 ? Date(timeIntervalSince1970: state.createdAt / 1000) : .now
    }

    mutating func update(from state: FriendGameState) {
        if let name = state[seat.opposite].name.map(ChallengeName.clean), !name.isEmpty {
            opponentName = name
        }
        clock = state.clock
        status = state.status
        turn = state.turn
        result = state.result
        moveCount = state.moves.count
        updatedAt = state.updatedAt > 0 ? Date(timeIntervalSince1970: state.updatedAt / 1000) : .now
    }

    var isOver: Bool { status == .over }
    var isYourMove: Bool { status == .active && turn == seat }

    /// "vs Sam", or "Open challenge" while nobody has joined.
    var title: String {
        if let opponentName { return "vs \(opponentName)" }
        return status == .waiting ? "Open challenge" : "vs your friend"
    }

    /// "Your move", "Their move", "Waiting for your friend to join", "You won · Checkmate".
    var statusLine: String {
        switch status {
        case .waiting: return "Waiting for \(opponentName ?? "your friend") to join"
        case .active: return isYourMove ? "Your move" : "Their move"
        case .over:
            guard let result else { return "Game over" }
            return FriendResultWords.short(result, me: seat)
        }
    }

    /// Your move first, then their move, then open challenges, then finished games.
    var listRank: Int {
        switch status {
        case .active: return isYourMove ? 0 : 1
        case .waiting: return 2
        case .over: return 3
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, code, token, seat, isCreator, opponentName, clock, status, turn, result, moveCount
        case createdAt, updatedAt, recorded
    }
}

extension FriendGame {
    /// Tolerant of a record written by another version of the app.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        code = try c.decode(String.self, forKey: .code)
        token = try c.decode(String.self, forKey: .token)
        seat = try c.decode(FriendSeat.self, forKey: .seat)
        isCreator = try c.decodeIfPresent(Bool.self, forKey: .isCreator) ?? false
        opponentName = try c.decodeIfPresent(String.self, forKey: .opponentName)
        clock = try c.decodeIfPresent(FriendClock.self, forKey: .clock)
        status = (try? c.decodeIfPresent(FriendGameState.Status.self, forKey: .status)) ?? .active
        turn = (try? c.decodeIfPresent(FriendSeat.self, forKey: .turn)) ?? .white
        result = try? c.decodeIfPresent(FriendGameState.Result.self, forKey: .result)
        moveCount = try c.decodeIfPresent(Int.self, forKey: .moveCount) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        recorded = try c.decodeIfPresent(Bool.self, forKey: .recorded) ?? false
    }
}

/// The player's friend games, saved on this phone (Application Support/friend-games.json).
@MainActor
@Observable
final class ChallengeStore {
    private(set) var games: [FriendGame]

    @ObservationIgnored private let fileURL: URL?

    /// Plenty for months of friend games.
    static let limit = 50
    /// The server deletes finished games after 30 days; so does the list.
    static let keepFinished: TimeInterval = 30 * 24 * 60 * 60

    init(games: [FriendGame] = [], fileURL: URL? = nil) {
        self.games = Self.pruned(games, now: .now)
        self.fileURL = fileURL
    }

    static func live() -> ChallengeStore {
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("friend-games.json")
        return ChallengeStore(games: url.map { load(from: $0) } ?? [], fileURL: url)
    }

    static func load(from url: URL) -> [FriendGame] {
        guard let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([FriendGame].self, from: data) else { return [] }
        return games
    }

    /// Your move first, then their move, open challenges, and finished games, newest first within each.
    var sorted: [FriendGame] {
        games.sorted { a, b in
            if a.listRank != b.listRank { return a.listRank < b.listRank }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Games still going, or waiting for a friend to join.
    var unfinished: [FriendGame] { games.filter { !$0.isOver } }

    func game(code: String) -> FriendGame? {
        games.first { $0.code == code }
    }

    /// Adds a game, or replaces the one with the same code.
    func add(_ game: FriendGame) {
        if let index = games.firstIndex(where: { $0.code == game.code }) {
            guard games[index] != game else { return }
            var updated = game
            updated.recorded = updated.recorded || games[index].recorded
            games[index] = updated
        } else {
            games.insert(game, at: 0)
        }
        games = Self.pruned(games, now: .now)
        save()
    }

    /// Brings a listed game up to date with the server's state; nil when it isn't listed.
    @discardableResult
    func update(code: String, from state: FriendGameState) -> FriendGame? {
        guard let index = games.firstIndex(where: { $0.code == code }) else { return nil }
        var game = games[index]
        game.update(from: state)
        if game != games[index] {
            games[index] = game
            save()
        }
        return game
    }

    func markRecorded(code: String) {
        guard let index = games.firstIndex(where: { $0.code == code }), !games[index].recorded else { return }
        games[index].recorded = true
        save()
    }

    func remove(code: String) {
        games.removeAll { $0.code == code }
        save()
    }

    /// Finished games go after 30 days, and the oldest finished ones first past the limit.
    static func pruned(_ games: [FriendGame], now: Date) -> [FriendGame] {
        var kept = games.filter { !$0.isOver || now.timeIntervalSince($0.updatedAt) < keepFinished }
        if kept.count > limit {
            let finished = kept.filter(\.isOver).sorted { $0.updatedAt < $1.updatedAt }
            let drop = Set(finished.prefix(kept.count - limit).map(\.code))
            kept.removeAll { drop.contains($0.code) }
            if kept.count > limit {
                kept = Array(kept.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
            }
        }
        return kept
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// A finished friend game, kept with the player's games so it can be reviewed in Rewind.
@MainActor
enum FriendGameArchive {
    /// Nil for a game that never really happened (aborted, cancelled, expired) or had no moves.
    static func savedGame(_ state: FriendGameState, seat: FriendSeat, id: UUID, date: Date, opponent: String) -> SavedGame? {
        guard state.status == .over, let result = state.result, result.reason.wasPlayed, !state.moves.isEmpty else { return nil }
        let replay = GameModel()
        for uci in state.moves {
            guard replay.playEngineMove(uci) else { return nil }
        }
        guard replay.moves.count == state.moves.count else { return nil }
        return SavedGame.make(
            id: id, date: date, opponent: opponent, level: nil, playerColor: seat.color,
            winner: result.winner?.color, isOver: true, accuracy: nil,
            positions: replay.positionFENs, moves: replay.moves, moments: []
        )
    }
}
