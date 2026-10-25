import Foundation
import Observation

/// One endgame study the player has completed.
struct EndgameRecord: Codable, Equatable {
    /// When it was first completed.
    var firstDone: Date
    /// When it was last completed.
    var lastDone: Date
    /// How many times it has been completed.
    var completions: Int
    /// Completed at least once with no slips and no hints.
    var clean: Bool
    /// The fewest moves it has taken.
    var bestMoves: Int?

    init(date: Date, moves: Int, clean: Bool) {
        firstDone = date
        lastDone = date
        completions = 1
        self.clean = clean
        bestMoves = moves
    }

    // A file saved by an older version may lack newer fields, so each one has a fallback.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstDone = try container.decodeIfPresent(Date.self, forKey: .firstDone) ?? .now
        lastDone = try container.decodeIfPresent(Date.self, forKey: .lastDone) ?? firstDone
        completions = try container.decodeIfPresent(Int.self, forKey: .completions) ?? 1
        clean = try container.decodeIfPresent(Bool.self, forKey: .clean) ?? false
        bestMoves = try container.decodeIfPresent(Int.self, forKey: .bestMoves)
    }
}

/// Which Perfect Endgames the player has completed (won, or held the draw). Saved to a small
/// JSON file after each one, and shared by the Endgames door, its list and the endgame screen.
@MainActor
@Observable
final class EndgameProgress {
    /// Completed studies, by id.
    private(set) var records: [String: EndgameRecord]
    /// The library, in the order it is shown.
    let studies: [EndgameStudy]
    private let fileURL: URL?

    /// Days until a completed study comes back for review, by how many times it has been completed.
    static let reviewGaps = [3, 7, 21, 60]

    init(studies: [EndgameStudy], records: [String: EndgameRecord] = [:], fileURL: URL? = nil) {
        self.studies = studies
        self.records = records
        self.fileURL = fileURL
    }

    /// The record the whole app shares.
    static let shared = EndgameProgress.live()

    /// The player's progress, kept in Application Support.
    static func live(studies: [EndgameStudy] = GrandmasterContent.shared.endgames) -> EndgameProgress {
        load(from: ProgressFile.url("endgame-progress.json"), studies: studies)
    }

    /// Progress saved at `url`, or none yet when there's no file (or one that can't be read, which
    /// is set aside). It is saved back there.
    static func load(from url: URL?, studies: [EndgameStudy]) -> EndgameProgress {
        let saved = ProgressFile.read(Saved.self, at: url)
        return EndgameProgress(studies: studies, records: saved?.records ?? [:], fileURL: url)
    }

    // MARK: Reading

    func isDone(_ id: String) -> Bool { records[id] != nil }

    /// Completed at least once with no slips and no hints.
    func isClean(_ id: String) -> Bool { records[id]?.clean == true }

    /// Studies completed, counting only those still in the library.
    var doneCount: Int { studies.filter { isDone($0.id) }.count }

    var total: Int { studies.count }

    var allDone: Bool { !studies.isEmpty && doneCount == total }

    func studies(in group: EndgameStudy.Group) -> [EndgameStudy] {
        studies.filter { $0.group == group }
    }

    func doneCount(in group: EndgameStudy.Group) -> Int {
        studies(in: group).filter { isDone($0.id) }.count
    }

    /// The first study not yet completed, in library order: what to suggest next.
    var nextUp: EndgameStudy? {
        studies.first { !isDone($0.id) }
    }

    /// The study to offer after `study`: the next one not yet completed, going round to the
    /// start of the library, or simply the next one once everything is done.
    func next(after study: EndgameStudy) -> EndgameStudy? {
        guard let index = studies.firstIndex(where: { $0.id == study.id }) else { return nextUp }
        let rest = studies[(index + 1)...] + studies[..<index]
        return rest.first { !isDone($0.id) } ?? rest.first
    }

    /// Completed studies due for another look, the longest-waiting first.
    func dueForReview(now: Date = .now) -> [EndgameStudy] {
        let due = studies.compactMap { study -> (study: EndgameStudy, date: Date)? in
            guard let record = records[study.id] else { return nil }
            let gap = Self.reviewGaps[min(max(record.completions, 1), Self.reviewGaps.count) - 1]
            let date = Calendar.current.date(byAdding: .day, value: gap, to: record.lastDone) ?? record.lastDone
            return date <= now ? (study, date) : nil
        }
        return due.sorted { $0.date < $1.date }.map(\.study)
    }

    // MARK: Recording

    /// Records a completed study: won, or the draw held.
    func record(_ study: EndgameStudy, moves: Int, clean: Bool, now: Date = .now) {
        if var record = records[study.id] {
            record.lastDone = now
            record.completions += 1
            record.clean = record.clean || clean
            record.bestMoves = min(record.bestMoves ?? moves, moves)
            records[study.id] = record
        } else {
            records[study.id] = EndgameRecord(date: now, moves: moves, clean: clean)
        }
        save()
    }

    private struct Saved: Codable {
        var records: [String: EndgameRecord]

        init(records: [String: EndgameRecord]) {
            self.records = records
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let saved = try container.decodeIfPresent([String: Readable].self, forKey: .records) ?? [:]
            records = saved.compactMapValues(\.record)
        }

        /// One saved record, or nil when it can't be read, so one bad entry never loses the rest.
        private struct Readable: Decodable {
            let record: EndgameRecord?

            init(from decoder: Decoder) throws {
                record = try? EndgameRecord(from: decoder)
            }
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(Saved(records: records)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Couldn't save endgame progress: %@", "\(error)")
        }
    }
}
