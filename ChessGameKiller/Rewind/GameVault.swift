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
        let games = url.map { Self.load(from: $0) } ?? []
        return GameVault(games: games, fileURL: url)
    }

    /// The games saved at `url`, skipping any one that can't be read (say, after its format
    /// changed). A file that can't be read at all is moved aside instead of being written
    /// over by the next save, so nothing is lost for good.
    static func load(from url: URL) -> [SavedGame] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let saved = try? JSONDecoder().decode([Lossy<SavedGame>].self, from: data) {
            return saved.compactMap(\.value)
        }
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        NSLog("The saved games couldn't be read; the file was moved aside")
        return []
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

    /// Saving runs off the main thread, one write after another, so the end of a game
    /// (when the king falls) never waits on the disk.
    private let writer = DispatchQueue(label: "GameVault.writer", qos: .utility)

    private func save() {
        guard let fileURL else { return }
        let snapshot = games
        writer.async {
            do {
                try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
            } catch {
                NSLog("Couldn't save the games: %@", "\(error)")
            }
        }
    }

    /// Waits until every save asked for so far is on disk.
    func waitUntilSaved() {
        writer.sync {}
    }
}

/// Decodes a value when it can, and stands in for it with nil when it can't, so one
/// unreadable item never costs the rest.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
