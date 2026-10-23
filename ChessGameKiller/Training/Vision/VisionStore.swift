import ChessKit
import Foundation
import Observation

/// The player's board vision record: the best coordinates score as each side, the best
/// board scan in each mode, and the puzzles scanned lately.
struct VisionRecord: Codable, Equatable {
    var coordinatesWhite = 0
    var coordinatesBlack = 0
    var coordinateRounds = 0
    /// Best round in each scan mode, by the mode's raw value.
    var scans: [String: BoardScan.Summary] = [:]
    var scanRounds = 0
    /// Puzzles scanned lately, so they don't come back soon.
    var recentScans: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case coordinatesWhite, coordinatesBlack, coordinateRounds, scans, scanRounds, recentScans
    }

    /// Every field is optional in the file, so a record saved before a field existed still loads.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        coordinatesWhite = try values.decodeIfPresent(Int.self, forKey: .coordinatesWhite) ?? 0
        coordinatesBlack = try values.decodeIfPresent(Int.self, forKey: .coordinatesBlack) ?? 0
        coordinateRounds = try values.decodeIfPresent(Int.self, forKey: .coordinateRounds) ?? 0
        scans = try values.decodeIfPresent([String: BoardScan.Summary].self, forKey: .scans) ?? [:]
        scanRounds = try values.decodeIfPresent(Int.self, forKey: .scanRounds) ?? 0
        recentScans = try values.decodeIfPresent([String].self, forKey: .recentScans) ?? []
    }
}

/// Keeps the board vision record, saved to a small JSON file after each round.
@MainActor
@Observable
final class VisionStore {
    private(set) var record: VisionRecord
    private let fileURL: URL?
    static let recentLimit = 300

    init(record: VisionRecord = VisionRecord(), fileURL: URL? = nil) {
        self.record = record
        self.fileURL = fileURL
    }

    private static var shared: VisionStore?

    /// The app's one store, read from disk the first time it's asked for, so the training
    /// screen and the drills always show the same record.
    static func live() -> VisionStore {
        if let shared { return shared }
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("vision-progress.json")
        var record = VisionRecord()
        if let url, let data = try? Data(contentsOf: url) {
            do {
                record = try JSONDecoder().decode(VisionRecord.self, from: data)
            } catch {
                NSLog("Board vision record unreadable, starting fresh: %@", "\(error)")
            }
        }
        let store = VisionStore(record: record, fileURL: url)
        shared = store
        return store
    }

    // MARK: Coordinates

    func coordinatesBest(as side: Piece.Color) -> Int {
        side == .white ? record.coordinatesWhite : record.coordinatesBlack
    }

    /// Saves a coordinates round. True when it is a new best for that side.
    @discardableResult
    func finishCoordinates(score: Int, as side: Piece.Color) -> Bool {
        record.coordinateRounds += 1
        let best = score > coordinatesBest(as: side)
        if best {
            if side == .white { record.coordinatesWhite = score } else { record.coordinatesBlack = score }
        }
        save()
        return best
    }

    // MARK: Board scan

    func scanBest(_ mode: BoardScan.Mode) -> BoardScan.Summary? {
        record.scans[mode.rawValue]
    }

    var recentScans: Set<String> { Set(record.recentScans) }

    /// Saves a scan round and the puzzles it used. True when it is a new best for the mode.
    @discardableResult
    func finishScan(_ summary: BoardScan.Summary, mode: BoardScan.Mode, puzzles: [String]) -> Bool {
        record.scanRounds += 1
        record.recentScans.append(contentsOf: puzzles)
        if record.recentScans.count > Self.recentLimit {
            record.recentScans.removeFirst(record.recentScans.count - Self.recentLimit)
        }
        let best = summary.beats(scanBest(mode))
        if best { record.scans[mode.rawValue] = summary }
        save()
        return best
    }

    // MARK: For the training screen

    /// The best coordinates score on either side; 0 before the first round.
    var bestSquares: Int { max(record.coordinatesWhite, record.coordinatesBlack) }

    /// The most accurate scan round in any mode, in percent. Nil before the first round.
    var bestScanPercent: Int? { record.scans.values.map(\.percent).max() }

    /// For the Coordinates row, like "Best 23". Nil before the first round.
    var coordinatesStatus: String? {
        bestSquares > 0 ? "Best \(bestSquares)" : nil
    }

    /// For the Board scan row, like "Best 92%". Nil before the first round.
    var scanStatus: String? {
        bestScanPercent.map { "Best \($0)%" }
    }

    /// One short line for the training door: both bests, or what's inside.
    var status: String {
        switch (bestSquares > 0, bestScanPercent) {
        case (true, let scan?): return "Best \(bestSquares) squares · scan \(scan)%"
        case (true, nil): return "Best \(bestSquares) squares"
        case (false, let scan?): return "Scan best \(scan)%"
        case (false, nil): return "Know every square. Scan every position."
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(record) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Couldn't save the board vision record: %@", "\(error)")
        }
    }
}
