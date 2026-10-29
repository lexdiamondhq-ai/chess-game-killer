import Foundation

// Today's Move: one puzzle a day, the same for every player, like a newspaper's chess column.
// The list is daily-moves.csv beside this file, built once by scripts/daily/build_daily_moves.py
// from the bundled Lichess puzzles. The week climbs: Monday is the easiest, Sunday the hardest.
//
// This file is compiled into both the app and the widget, so it uses Foundation only.

/// One day's puzzle.
struct DailyPuzzle: Equatable, Sendable {
    /// Counted from 1 on October 1, 2026.
    let number: Int
    /// The Lichess puzzle id.
    let id: String
    /// The position before the opponent's move.
    let fen: String
    /// The opponent's move first, then the answer and replies, in UCI.
    let moves: [String]
    let rating: Int
    let themes: [String]
    /// The position the solver sees, after the opponent's move.
    let shownFEN: String

    /// White solves when it is White's move in the position shown.
    var solverIsWhite: Bool {
        shownFEN.split(separator: " ").dropFirst().first != "b"
    }

    var mateIn: Int? {
        for n in 1...5 where themes.contains("mateIn\(n)") { return n }
        return nil
    }

    /// The way a chess column puts it: "White to play and mate in two.", "Black to play and win."
    var headline: String {
        let side = solverIsWhite ? "White" : "Black"
        if let mate = mateIn {
            let words = ["zero", "one", "two", "three", "four", "five"]
            return mate == 1 ? "\(side) to play and mate." : "\(side) to play and mate in \(words[mate])."
        }
        return "\(side) to play and win."
    }

    /// "Easy" on Monday up to "Hardest" on Sunday, from the rating the list was built by.
    var difficulty: String {
        switch rating {
        case ..<1400: return "Easy"
        case ..<1600: return "Medium"
        case ..<1800: return "Tricky"
        case ..<2000: return "Hard"
        default: return "Hardest"
        }
    }
}

enum DailyMoves {
    /// Day 1.
    static let epoch = DateComponents(year: 2026, month: 10, day: 1)

    /// Every day's puzzle, read once from the bundle.
    static let all: [DailyPuzzle] = load()

    /// The puzzle for `date` in the player's own calendar: everyone gets the same one on the same date.
    /// The list starts over once it runs out.
    static func puzzle(for date: Date, calendar: Calendar = .current, list: [DailyPuzzle] = all) -> DailyPuzzle? {
        guard !list.isEmpty else { return nil }
        let index = (dayNumber(for: date, calendar: calendar) - 1) % list.count
        return list[index]
    }

    /// 1 on October 1, 2026, 2 the day after, and so on. Never below 1, even with the clock set back.
    static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        guard let start = calendar.date(from: epoch) else { return 1 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return max(1, days + 1)
    }

    /// "2026-10-29", in the player's own calendar: the name of a day everywhere in the daily habit.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func load(_ bundle: Bundle = .main) -> [DailyPuzzle] {
        guard let url = bundle.url(forResource: "daily-moves", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Reads the list: day,id,fen,moves,rating,themes,shown. A line that can't be read is skipped.
    static func parse(_ text: String) -> [DailyPuzzle] {
        text.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 7, let number = Int(fields[0]), let rating = Int(fields[4]) else { return nil }
            let moves = fields[3].split(separator: " ").map(String.init)
            guard moves.count >= 2, moves.count % 2 == 0 else { return nil }
            return DailyPuzzle(number: number, id: String(fields[1]), fen: String(fields[2]), moves: moves,
                               rating: rating, themes: fields[5].split(separator: " ").map(String.init),
                               shownFEN: String(fields[6]))
        }
    }
}
