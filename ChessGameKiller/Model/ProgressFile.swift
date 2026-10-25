import Foundation

/// The small JSON files that hold what the player has built up: the army, training, puzzles,
/// the thinking drills, endgames, the opening repertoire and friend games. Each store keeps one
/// file in Application Support and reads it through here.
///
/// A file that can't be read (its format changed in an update, or it was damaged) is never
/// written over: it is set aside as `<name>.unreadable.json`, the store starts fresh, and the
/// file is still there to recover from.
enum ProgressFile {
    /// Where a store's file lives.
    static func url(_ name: String) -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(name)
    }

    /// The value saved at `url`, or nil when there is no file there. A file that won't decode is
    /// set aside, and nil comes back for it too.
    static func read<Saved: Decodable>(_ type: Saved.Type, at url: URL?, decoder: JSONDecoder = JSONDecoder()) -> Saved? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            NSLog("Couldn't read %@, so it was set aside: %@", url.lastPathComponent, "\(error)")
            setAside(url)
            return nil
        }
    }

    /// Where an unreadable file goes: next to the original, as name.unreadable.json.
    static func asideURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("unreadable.json")
    }

    /// Moves the file out of the way, replacing one set aside before it.
    static func setAside(_ url: URL) {
        let aside = asideURL(for: url)
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
