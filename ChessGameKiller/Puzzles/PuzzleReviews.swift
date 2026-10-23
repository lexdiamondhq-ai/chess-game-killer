import Foundation

/// Rated puzzles that weren't solved cleanly, back for another look on a
/// Leitner schedule: tomorrow, then after 3, 7 and 16 days. A clean solve
/// moves a puzzle up a box, anything less sends it back to tomorrow, and a
/// clean solve from the last box retires it as learned.
struct PuzzleReviewQueue: Codable, Equatable {
    /// Days until a puzzle comes back, by box.
    static let intervals = [1, 3, 7, 16]
    /// The most puzzles kept. Past it the oldest leave first, so review stays
    /// a few minutes a day rather than a backlog.
    static let capacity = 100

    /// What happens to a puzzle after a review.
    enum Result: Equatable {
        /// It comes back in this many days.
        case returns(days: Int)
        /// Solved cleanly from the last box: it leaves the queue.
        case learned
    }

    private(set) var items: [PuzzleReviewItem] = []
    /// Puzzles retired after a clean solve from the last box.
    private(set) var learned = 0

    enum CodingKeys: String, CodingKey {
        case items, learned
    }

    var count: Int { items.count }

    var ids: Set<String> { Set(items.map(\.id)) }

    func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    /// The puzzles due at `now`, most overdue first.
    func due(at now: Date) -> [PuzzleReviewItem] {
        items.filter { $0.due <= now }.sorted { ($0.due, $0.added) < ($1.due, $1.added) }
    }

    /// When the next puzzle that isn't due yet comes back.
    func nextDue(after now: Date) -> Date? {
        items.map(\.due).filter { $0 > now }.min()
    }

    /// A puzzle missed in rated play or in review: it comes back tomorrow.
    mutating func missed(_ id: String, now: Date, calendar: Calendar) {
        let due = Self.day(after: now, days: Self.intervals[0], calendar: calendar)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].box = 0
            items[index].due = due
            items[index].misses += 1
            return
        }
        items.append(PuzzleReviewItem(id: id, box: 0, due: due, added: now, misses: 1))
        if items.count > Self.capacity, let oldest = items.indices.min(by: { items[$0].added < items[$1].added }) {
            items.remove(at: oldest)
        }
    }

    /// A review played. Nil when the puzzle isn't in the queue.
    @discardableResult
    mutating func reviewed(_ id: String, clean: Bool, now: Date, calendar: Calendar) -> Result? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard clean else {
            missed(id, now: now, calendar: calendar)
            return .returns(days: Self.intervals[0])
        }
        let box = items[index].box + 1
        guard box < Self.intervals.count else {
            items.remove(at: index)
            learned += 1
            return .learned
        }
        items[index].box = box
        items[index].due = Self.day(after: now, days: Self.intervals[box], calendar: calendar)
        return .returns(days: Self.intervals[box])
    }

    mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// The start of the day `days` after `now`, so a puzzle missed late in
    /// the evening is ready first thing, not at the same minute.
    static func day(after now: Date, days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Double(days) * 86_400)
    }
}

extension PuzzleReviewQueue {
    /// Reads any saved version: a key a file doesn't have yet keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        items = try saved.decodeIfPresent([PuzzleReviewItem].self, forKey: .items) ?? items
        learned = try saved.decodeIfPresent(Int.self, forKey: .learned) ?? learned
    }
}

/// One missed puzzle waiting for review.
struct PuzzleReviewItem: Codable, Equatable, Identifiable {
    /// The Lichess puzzle id.
    let id: String
    /// Leitner box, from 0 (back tomorrow) to 3 (back in 16 days).
    var box: Int
    var due: Date
    let added: Date
    /// Times it was missed, in rated play or in review.
    var misses: Int
}

/// How a player does on one Lichess theme tag in rated puzzles.
struct ThemeRecord: Codable, Equatable {
    var attempts = 0
    /// Solved with no wrong move and no hint.
    var clean = 0

    /// Clean solves out of attempts, from 0 to 1.
    var accuracy: Double {
        attempts == 0 ? 0 : Double(clean) / Double(attempts)
    }
}
