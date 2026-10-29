import Foundation

/// What the widget shows of the daily habit, written by the app whenever it changes and read by
/// the widget, through the app group both belong to. Compiled into both, so Foundation only.
struct DailySnapshot: Codable, Equatable {
    /// Days in a row the last time the day's goal was met.
    var streak = 0
    /// The last day the goal was met ("2026-10-29").
    var lastDay: String?
    /// The last day the streak still stands without anything more done: the day after `lastDay`,
    /// or two days after when the weekly rest day is still free.
    var aliveThrough: String?
    /// The day Today's Move was last played, and whether it was found.
    var moveDay: String?
    var moveFound = false
    /// The player's best piece, by name, and its rank: "Seraphine", "Legend".
    var hero: String?
    var heroRank: String?

    /// The app group the app and the widget share.
    static let group = "group.com.chessgamekiller.app"
    static let key = "daily.snapshot"

    /// The group's defaults; plain defaults when the group isn't there (an unsigned build).
    static var shared: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func read(_ defaults: UserDefaults = DailySnapshot.shared) -> DailySnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DailySnapshot.self, from: data) else { return DailySnapshot() }
        return snapshot
    }

    func write(_ defaults: UserDefaults = DailySnapshot.shared) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The streak as it stands on `day`: 0 once it has lapsed.
    func streakShown(on day: String) -> Int {
        guard let aliveThrough, day <= aliveThrough else { return 0 }
        return streak
    }

    /// Whether the day's goal is already met on `day`.
    func isDone(on day: String) -> Bool { lastDay == day }

    /// Whether Today's Move has been played on `day`.
    func playedMove(on day: String) -> Bool { moveDay == day }

    private enum CodingKeys: String, CodingKey {
        case streak, lastDay, aliveThrough, moveDay, moveFound, hero, heroRank
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay)
        aliveThrough = try c.decodeIfPresent(String.self, forKey: .aliveThrough)
        moveDay = try c.decodeIfPresent(String.self, forKey: .moveDay)
        moveFound = try c.decodeIfPresent(Bool.self, forKey: .moveFound) ?? false
        hero = try c.decodeIfPresent(String.self, forKey: .hero)
        heroRank = try c.decodeIfPresent(String.self, forKey: .heroRank)
    }
}
