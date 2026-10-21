import Foundation
import Observation

/// The player's finished games, newest first, saved on this device.
@MainActor
@Observable
final class GameVault {
    private(set) var games: [SavedGame]

    private let fileURL: URL?

    /// Enough for weeks of play without the file growing without end.
    static let limit = 150

    init(games: [SavedGame] = [], fileURL: URL? = nil) {
        self.games = games
        self.fileURL = fileURL
    }

    static func live() -> GameVault {
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("games.json")
        var games: [SavedGame] = []
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([SavedGame].self, from: data) {
            games = saved
        }
        return GameVault(games: games, fileURL: url)
    }

    func game(_ id: UUID) -> SavedGame? {
        games.first { $0.id == id }
    }

    /// Adds a game, or brings a saved one up to date (its last grades can land after the game ends).
    /// What the player already rewrote is kept.
    func record(_ game: SavedGame) {
        guard !game.moves.isEmpty else { return }
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            var updated = game
            updated.rewritten = games[index].rewritten
            updated.date = games[index].date
            guard updated != games[index] else { return }
            games[index] = updated
        } else {
            games.insert(game, at: 0)
            if games.count > Self.limit { games.removeLast(games.count - Self.limit) }
        }
        save()
    }

    /// The player found the better move at this point of the game.
    func markRewritten(_ ply: Int, in id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        guard games[index].rewritten.insert(ply).inserted else { return }
        save()
    }

    func delete(_ id: UUID) {
        games.removeAll { $0.id == id }
        save()
    }

    // MARK: This week

    /// Moments rewritten in games from the last seven days.
    func rewrittenThisWeek(now: Date = .now) -> Int {
        recent(now: now).reduce(0) { total, game in
            total + game.toRewrite.filter { game.rewritten.contains($0.ply) }.count
        }
    }

    /// Moments still to fix in games from the last seven days.
    func leftThisWeek(now: Date = .now) -> Int {
        recent(now: now).reduce(0) { $0 + $1.leftToRewrite }
    }

    private func recent(now: Date) -> [SavedGame] {
        let start = now.addingTimeInterval(-7 * 24 * 3600)
        return games.filter { $0.date >= start }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(games).write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save the games: \(error)")
        }
    }
}
