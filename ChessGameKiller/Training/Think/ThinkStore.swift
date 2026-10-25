import Foundation
import Observation

/// What the thinking drills remember: the candidates drill's record, the
/// positions it showed lately, and the last level check.
struct ThinkProgress: Codable, Equatable {
    /// Positions judged in the candidates drill.
    var positions = 0
    var points = 0
    /// Positions where the winner was on the player's list.
    var found = 0
    /// Positions where the winner was the player's first idea.
    var foundFirst = 0
    /// Rounds of five played to the end, and the best score in one.
    var rounds = 0
    var bestRound = 0
    /// Positions shown lately, so they don't come back soon.
    var recent: [String] = []
    /// The level check's estimate, and when it was taken.
    var level: Int?
    var levelDate: Date?

    init() {}

    /// Keys missing from an older file fall back to their defaults, so saved records keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decodeIfPresent(Int.self, forKey: .positions) ?? 0
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
        found = try container.decodeIfPresent(Int.self, forKey: .found) ?? 0
        foundFirst = try container.decodeIfPresent(Int.self, forKey: .foundFirst) ?? 0
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 0
        bestRound = try container.decodeIfPresent(Int.self, forKey: .bestRound) ?? 0
        recent = try container.decodeIfPresent([String].self, forKey: .recent) ?? []
        level = try container.decodeIfPresent(Int.self, forKey: .level)
        levelDate = try container.decodeIfPresent(Date.self, forKey: .levelDate)
    }
}

/// The thinking drills' record, saved to a small JSON file after each change.
@MainActor
@Observable
final class ThinkStore {
    private(set) var progress: ThinkProgress

    private let fileURL: URL?
    static let recentLimit = 300

    init(progress: ThinkProgress = ThinkProgress(), fileURL: URL? = nil) {
        self.progress = progress
        self.fileURL = fileURL
    }

    /// The app's store: the record saved on this device.
    static func live() -> ThinkStore {
        let url = ProgressFile.url("think-progress.json")
        return ThinkStore(progress: load(from: url) ?? ThinkProgress(), fileURL: url)
    }

    /// The record saved at `url`, or nil when there isn't one that reads (one that doesn't is set aside).
    static func load(from url: URL?) -> ThinkProgress? {
        ProgressFile.read(ThinkProgress.self, at: url)
    }

    // MARK: Recording

    /// Counts a judged position of the candidates drill.
    func record(_ report: CandidateReport, puzzleID: String) {
        progress.positions += 1
        progress.points += report.points
        if let foundAt = report.foundAt {
            progress.found += 1
            if foundAt == 0 { progress.foundFirst += 1 }
        }
        progress.recent.append(puzzleID)
        if progress.recent.count > Self.recentLimit {
            progress.recent.removeFirst(progress.recent.count - Self.recentLimit)
        }
        save()
    }

    /// Counts a finished round. True when it is a new best.
    @discardableResult
    func finishRound(points: Int) -> Bool {
        progress.rounds += 1
        let best = points > progress.bestRound
        if best { progress.bestRound = points }
        save()
        return best
    }

    /// Keeps the level check's estimate.
    func recordLevel(_ rating: Int, on date: Date = .now) {
        progress.level = rating
        progress.levelDate = date
        save()
    }

    // MARK: Reading

    /// A short line for the candidates drill's door, like "Best round 18 of 25".
    var candidateStatus: String {
        if progress.rounds > 0 {
            return "Best round \(progress.bestRound) of \(CandidateRound.maxPoints)"
        }
        if progress.positions > 0 {
            return "Winner found \(progress.found) of \(progress.positions)"
        }
        return "Three candidates, one winner"
    }

    /// The band the last level check found, once there has been one.
    var levelBand: LevelBand? {
        progress.level.map { LevelBand(rating: $0) }
    }

    /// A short line for the level check, like "Club player · 1520". Nil before the first check.
    var levelStatus: String? {
        guard let level = progress.level else { return nil }
        return "\(LevelBand(rating: level).name) · \(level)"
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
