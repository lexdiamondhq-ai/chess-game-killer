import ChessKit
import Foundation
import Observation

/// Everything your Grudge remembers about you.
struct GrudgeRecord: Codable, Equatable {
    /// A piece it took from you in a game it won: what it brings up next time.
    struct Moment: Codable, Equatable {
        let date: Date
        /// The move number, as on a scoresheet.
        let move: Int
        /// "e5".
        let square: String
        /// "knight".
        let piece: String
    }

    /// Your results after one opening, from your side.
    struct Tally: Codable, Equatable {
        var wins = 0
        var draws = 0
        var losses = 0

        var games: Int { wins + draws + losses }
        /// 1 for all wins, 0 for all losses.
        var score: Double { games == 0 ? 0.5 : (Double(wins) + Double(draws) / 2) / Double(games) }
    }

    enum Mood: String, Codable {
        /// It leads.
        case smug
        /// You won the last two.
        case rattled
        /// You ended a run of its wins.
        case furious
        /// You lead by five or more.
        case respect
        /// Level.
        case even

        var title: String {
            switch self {
            case .smug: return "Smug"
            case .rattled: return "Rattled"
            case .furious: return "Furious"
            case .respect: return "Respect"
            case .even: return "Watching"
            }
        }
    }

    var bornAt: Date
    /// Stockfish skill, 1 to 20. Your wins push it up, its wins ease it back, so it stays just ahead.
    var skill: Int
    var yourWins = 0
    var itsWins = 0
    var draws = 0
    /// Your wins in a row, and its.
    var yourRun = 0
    var itsRun = 0
    /// Gold scars on its king: your wins since it was last rebuilt.
    var scars = 0
    /// How many times it has been rebuilt after ten scars.
    var form = 0
    /// Set when your last win ended a run of three or more of its wins.
    var brokeItsRun = false
    var lastLoss: Moment?
    /// Your results by the game's first four moves (standard notation, spaced), so it can steer
    /// back into them.
    var openings: [String: Tally] = [:]
    var lastPlayed: Date?

    var mood: Mood {
        if brokeItsRun { return .furious }
        if yourWins - itsWins >= 5 { return .respect }
        if yourRun >= 2 { return .rattled }
        if itsWins > yourWins { return .smug }
        return .even
    }

    /// "7 – 11": your wins first.
    var score: String { "\(yourWins) – \(itsWins)" }

    /// The crowd it plays closest to, for its rating and the army.
    var level: MatchController.Level { Self.level(forSkill: skill) }

    /// About what it is rated at now.
    var rating: Int { Self.rating(forSkill: skill) }

    static let scarsToRebuild = 10

    static func level(forSkill skill: Int) -> MatchController.Level {
        switch skill {
        case ..<5: return .beginner
        case ..<9: return .casual
        case ..<13: return .club
        case ..<18: return .expert
        default: return .grandmaster
        }
    }

    /// After the calibration of the crowds' Stockfish settings (skill 3 near 800, 10 near 1500,
    /// 14 near 2000, 20 near 3000), joined up in straight lines.
    static func rating(forSkill skill: Int) -> Int {
        let points: [(Double, Double)] = [(0, 600), (3, 800), (6, 1100), (10, 1500), (14, 2000), (20, 3000)]
        let s = Double(min(max(skill, 0), 20))
        for index in 1..<points.count where s <= points[index].0 {
            let (x0, y0) = points[index - 1]
            let (x1, y1) = points[index]
            let value = y0 + (y1 - y0) * (s - x0) / (x1 - x0)
            return Int((value / 50).rounded()) * 50
        }
        return 3000
    }

    /// The opening key of a game: its first four moves.
    static func openingKey(_ moves: [String]) -> String? {
        guard moves.count >= 4 else { return nil }
        return moves.prefix(4).joined(separator: " ")
    }

    /// How much the Grudge wants a move (standard notation) that would make the opening
    /// `moves` + `san`: more for lines you have lost in against it, never less than 1.
    func lean(after moves: [String], toward san: String) -> Double {
        guard moves.count < 4 else { return 1 }
        let line = (moves + [san]).joined(separator: " ")
        let tallies = openings.filter { $0.key.hasPrefix(line) }.map(\.value)
        let games = tallies.reduce(0) { $0 + $1.games }
        guard games > 0 else { return 1 }
        let points = tallies.reduce(0.0) { $0 + Double($1.wins) + Double($1.draws) / 2 }
        let score = points / Double(games)
        return 1 + max(0, 0.5 - score) * 4
    }
}

/// The result of one game against the Grudge, from your side.
enum GrudgeResult: Equatable {
    case youWon
    case itWon
    case draw
}

/// Keeps your Grudge: born the first time a crowd beats you, then one rival that remembers.
@MainActor
@Observable
final class GrudgeStore {
    private(set) var record: GrudgeRecord?
    /// Born but not yet met: the New Game sheet summons it the first time.
    private(set) var unseen = false

    @ObservationIgnored private let defaults: UserDefaults
    static let key = "grudge.record.v1"
    static let unseenKey = "grudge.unseen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        record = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(GrudgeRecord.self, from: $0) }
        unseen = defaults.bool(forKey: Self.unseenKey)
    }

    var isBorn: Bool { record != nil }

    /// A crowd beat you. The first time, someone takes it personally: the Grudge is born, one
    /// step stronger than the crowd that won, with that win already on its side.
    /// Returns true when this loss gave birth to it.
    @discardableResult
    func crowdWon(level: MatchController.Level, moves: [String], playerColor: Piece.Color,
                  positions: [String], now: Date = .now) -> Bool {
        guard record == nil else { return false }
        var born = GrudgeRecord(bornAt: now, skill: min(20, level.skill + 1))
        born.itsWins = 1
        born.itsRun = 1
        born.lastPlayed = now
        born.lastLoss = Self.worstLoss(moves: moves, positions: positions, playerColor: playerColor, date: now)
        record = born
        unseen = true
        save()
        return true
    }

    /// Writes down a finished game against the Grudge.
    func recordGame(_ result: GrudgeResult, moves: [String], playerColor: Piece.Color,
                    positions: [String], now: Date = .now) {
        guard var record else { return }
        record.lastPlayed = now
        record.brokeItsRun = false
        switch result {
        case .youWon:
            record.yourWins += 1
            if record.itsRun >= 3 { record.brokeItsRun = true }
            record.yourRun += 1
            record.itsRun = 0
            record.scars += 1
            record.skill = min(20, record.skill + 1)
            if record.scars >= GrudgeRecord.scarsToRebuild {
                // Rebuilt: the scars are gone and it comes back a little harder.
                record.scars = 0
                record.form += 1
                record.skill = min(20, record.skill + 1)
            }
        case .itWon:
            record.itsWins += 1
            record.itsRun += 1
            record.yourRun = 0
            record.skill = max(1, record.skill - 1)
            if let moment = Self.worstLoss(moves: moves, positions: positions, playerColor: playerColor, date: now) {
                record.lastLoss = moment
            }
        case .draw:
            record.draws += 1
            record.yourRun = 0
            record.itsRun = 0
        }
        if let key = GrudgeRecord.openingKey(moves) {
            var tally = record.openings[key] ?? GrudgeRecord.Tally()
            switch result {
            case .youWon: tally.wins += 1
            case .itWon: tally.losses += 1
            case .draw: tally.draws += 1
            }
            record.openings[key] = tally
        }
        self.record = record
        save()
    }

    /// The summons has played: the Grudge has been met.
    func markSeen() {
        guard unseen else { return }
        unseen = false
        defaults.set(false, forKey: Self.unseenKey)
    }

    /// Forgets the Grudge entirely (Settings, and tests).
    func reset() {
        record = nil
        unseen = false
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.unseenKey)
    }

    private func save() {
        if let record, let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.key)
        }
        defaults.set(unseen, forKey: Self.unseenKey)
    }

    // MARK: What it remembers

    /// The most valuable piece the rival took from you in the game, the earliest if there are two.
    /// `moves` are in standard notation and `positions` holds the FEN before each move, as
    /// `GameModel.moves` and `GameModel.positionFENs` do.
    static func worstLoss(moves: [String], positions: [String], playerColor: Piece.Color,
                          date: Date) -> GrudgeRecord.Moment? {
        let value: [Character: Int] = ["q": 9, "r": 5, "b": 3, "n": 3, "p": 1]
        var best: (value: Int, moment: GrudgeRecord.Moment)?
        for (index, san) in moves.enumerated() where index < positions.count && san.contains("x") {
            let fen = positions[index]
            let fields = fen.split(separator: " ")
            guard fields.count >= 2 else { continue }
            let rivalMoves = (fields[1] == "w") != (playerColor == .white)
            guard rivalMoves, let target = destination(of: san), let piece = pieceAt(target, in: fen) else { continue }
            let mine = piece.isUppercase == (playerColor == .white)
            guard mine, let worth = value[Character(piece.lowercased())] else { continue }
            if best == nil || worth > best!.value {
                let moveNumber = fields.count >= 6 ? Int(fields[5]) ?? 1 : 1
                let moment = GrudgeRecord.Moment(date: date, move: moveNumber, square: target,
                                                 piece: word(for: Character(piece.lowercased())))
                best = (worth, moment)
            }
        }
        return best?.moment
    }

    /// The square a move in standard notation lands on: "Nxe5+" lands on "e5".
    static func destination(of san: String) -> String? {
        let body = san.split(separator: "=").first.map(String.init) ?? san
        let chars = Array(body)
        let files: ClosedRange<Character> = "a"..."h"
        let ranks: ClosedRange<Character> = "1"..."8"
        guard chars.count >= 2 else { return nil }
        for index in stride(from: chars.count - 2, through: 0, by: -1) {
            if files.contains(chars[index]), ranks.contains(chars[index + 1]) {
                return String(chars[index...index + 1])
            }
        }
        return nil
    }

    /// The piece on `square` ("e5") in `fen`, as its FEN letter.
    static func pieceAt(_ square: String, in fen: String) -> Character? {
        let chars = Array(square)
        guard chars.count == 2, let fileValue = chars[0].asciiValue, let rank = Int(String(chars[1])),
              (97...104).contains(fileValue), (1...8).contains(rank) else { return nil }
        let file = Int(fileValue) - 97
        guard let board = fen.split(separator: " ").first else { return nil }
        let rows = board.split(separator: "/")
        guard rows.count == 8 else { return nil }
        var column = 0
        for char in rows[8 - rank] {
            if let skip = char.wholeNumberValue {
                column += skip
            } else {
                if column == file { return char }
                column += 1
            }
            if column > file { return nil }
        }
        return nil
    }

    private static func word(for letter: Character) -> String {
        switch letter {
        case "q": return "queen"
        case "r": return "rook"
        case "b": return "bishop"
        case "n": return "knight"
        default: return "pawn"
        }
    }
}
