import ChessKit
import XCTest
@testable import ChessGameKiller

/// Your Chess DNA: the style, weapon, openings and growth the coach reads from the
/// player's own games and puzzles, and how it steers today's training.
final class ChessDNATests: XCTestCase {

    // MARK: Sample games

    /// The Fried Liver: a knight given up on f7 for an attack on the king, checks all the way.
    static let friedLiver = "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5 d7d5 e4d5 f6d5 g5f7 e8f7 d1f3 f7e6 b1c3 c6b4 f3e4 c7c6 a2a3 b4a6 d2d4 a6c7 c1f4 e6f7 f4e5 c8e6 c3d5 c6d5 c4d5 e6d5 e4f5 f7e8"
    /// A London System, castled early, then rooks shuffling: no checks, no captures.
    static let quietLondon = "d2d4 d7d5 g1f3 g8f6 c1f4 e7e6 e2e3 f8e7 f1d3 e8g8 e1g1 c7c5 c2c3 b8c6 b1d2 b7b6 d1e2 c8b7 h2h3 a8c8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8"

    /// A game played out from the start in engine notation, with every player move graded
    /// `.good` unless `grades` says otherwise (by ply).
    static func game(_ line: String, white: Bool = true, result: SavedGame.Result = .win, accuracy: Int? = 85,
                     daysAgo: Double = 0, grades: [Int: MoveReview.Grade] = [:], level: Int? = 2) -> SavedGame {
        var fen = Position.standard.fen
        var positions = [fen]
        var moves: [String] = []
        var moments: [SavedMoment] = []
        for (offset, uci) in line.split(separator: " ").map(String.init).enumerated() {
            guard let san = Notation.san(of: uci, fen: fen), let next = TrainingChess.fen(after: [uci], from: fen) else {
                XCTFail("Illegal move \(uci) at ply \(offset + 1)")
                break
            }
            let byWhite = offset % 2 == 0
            if byWhite == white {
                let grade = grades[offset + 1] ?? .good
                let bad = CoachReport.weight(of: grade) != nil
                moments.append(SavedMoment(ply: offset + 1, grade: grade.rawValue, san: san, uci: uci, byWhite: byWhite,
                                           fenBefore: fen, fenAfter: next, before: 0.1, after: bad ? -0.3 : 0.1))
            }
            moves.append(san)
            positions.append(next)
            fen = next
        }
        return SavedGame(id: UUID(), date: Date().addingTimeInterval(-daysAgo * 86_400 - 60), opponent: "Drift",
                         level: level, playerIsWhite: white, result: result, accuracy: accuracy,
                         positions: positions, moves: moves, moments: moments)
    }

    // MARK: Openings

    func testEveryNamedLineIsIndexedByItsPosition() throws {
        let index = OpeningIndex.shared
        XCTAssertGreaterThan(index.lines.count, 3_000, "openings.tsv isn't in the app")
        XCTAssertGreaterThan(index.byKey.count, 3_000, "opening-positions.tsv isn't in the app")
        // A sample of lines: the position each ends in names a line ending in that same position.
        for line in index.lines.enumerated().filter({ $0.offset % 25 == 0 }).map(\.element) {
            let fen = try XCTUnwrap(TrainingChess.fen(after: line.moves, from: Position.standard.fen), line.name)
            let named = try XCTUnwrap(index.byKey[TrainingChess.key(fen)], "\(line.name) isn't indexed: run build_opening_positions.py")
            let end = TrainingChess.fen(after: index.lines[named].moves, from: Position.standard.fen)
            XCTAssertEqual(end.map(TrainingChess.key), TrainingChess.key(fen), line.name)
        }
    }

    func testAnOpeningIsNamedWhateverTheMoveOrder() throws {
        let one = Self.game("d2d4 g8f6 c2c4 e7e6 b1c3 f8b4")
        let two = Self.game("c2c4 e7e6 b1c3 g8f6 d2d4 f8b4")
        let first = try XCTUnwrap(OpeningIndex.shared.opening(of: one.positions))
        XCTAssertEqual(first.family, "Nimzo-Indian Defense")
        XCTAssertEqual(OpeningIndex.shared.opening(of: two.positions)?.family, "Nimzo-Indian Defense")
    }

    func testTheOpeningsThePlayerPlaysAndHowTheyGo() throws {
        let games = [
            Self.game(Self.friedLiver, result: .win, accuracy: 90, daysAgo: 1),
            Self.game(Self.friedLiver, result: .win, accuracy: 80, daysAgo: 2),
            Self.game(Self.friedLiver, result: .loss, accuracy: 70, daysAgo: 3),
            Self.game(Self.quietLondon, result: .draw, daysAgo: 4),
        ]
        let dna = ChessDNA.make(games: games)
        let italian = try XCTUnwrap(dna.openings.first)
        XCTAssertEqual(italian.family, "Italian Game")
        XCTAssertTrue(italian.playerIsWhite)
        XCTAssertEqual(italian.tally, "2–0–1")
        XCTAssertEqual(italian.accuracy, 80)
        XCTAssertEqual(dna.openings.count, 2)
        // Two thirds of the points in three games: the Italian is theirs, so it's the pick for White.
        let pick = try XCTUnwrap(dna.picks.first { $0.playerIsWhite })
        XCTAssertTrue(pick.isTheirs)
        XCTAssertEqual(pick.line.family, "Italian Game")
        // For Black there's nothing of theirs yet, so the pick fits the style.
        let black = try XCTUnwrap(dna.picks.first { !$0.playerIsWhite })
        XCTAssertFalse(black.isTheirs)
    }

    // MARK: Style

    func testTooFewGamesNamesNoStyle() {
        let dna = ChessDNA.make(games: [Self.game(Self.friedLiver), Self.game(Self.friedLiver)])
        XCTAssertNil(dna.style)
        XCTAssertTrue(dna.traits.allSatisfy { $0.value == nil })
        XCTAssertTrue(dna.picks.isEmpty)
    }

    func testChecksCapturesAndASacrificeMakeAnAttacker() throws {
        let games = (0..<4).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertGreaterThanOrEqual(habits.sacrifices, 1, "Nxf7 gives a knight for a pawn")
        XCTAssertNil(habits.castledOn)
        XCTAssertGreaterThan(habits.checks, 0)
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.style, .attacker)
        let aggression = try XCTUnwrap(dna.traits.first { $0.kind == .aggression }?.value)
        let risk = try XCTUnwrap(dna.traits.first { $0.kind == .risk }?.value)
        XCTAssertGreaterThan(aggression, 0.6)
        XCTAssertGreaterThan(risk, 0.5)
    }

    func testQuietSafeGamesMakeABuilder() throws {
        let games = (0..<4).map { Self.game(Self.quietLondon, result: .draw, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertEqual(habits.castledOn, 6)
        XCTAssertEqual(habits.captures, 0)
        XCTAssertEqual(habits.sacrifices, 0)
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.style, .builder)
        XCTAssertEqual(dna.traits.first { $0.kind == .aggression }?.word, "Quiet")
        XCTAssertEqual(dna.traits.first { $0.kind == .risk }?.word, "Safe")
    }

    func testPlayingAsBlackReadsBlacksMoves() {
        let games = (0..<3).map { Self.game(Self.quietLondon, white: false, result: .draw, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertEqual(habits.castledOn, 5)
        XCTAssertEqual(habits.moves, 26)
        XCTAssertNotNil(ChessDNA.make(games: games).style)
    }

    func testFriendGamesAreLeftOut() {
        let games = (0..<4).map { Self.game(Self.friedLiver, daysAgo: Double($0), level: nil) }
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.gamesRead, 0)
        XCTAssertNil(dna.style)
    }

    // MARK: Weapon

    func testAPuzzleThemeWellAboveAverageIsTheWeapon() throws {
        let stats = ["fork": ThemeRecord(attempts: 20, clean: 18), "pin": ThemeRecord(attempts: 20, clean: 8)]
        let weapon = try XCTUnwrap(ChessDNA.make(games: [], puzzleStats: stats).weapon)
        XCTAssertEqual(weapon.title, "Forks")
        XCTAssertEqual(weapon.theme, "fork")
        XCTAssertTrue(weapon.detail.contains("90%"), weapon.detail)
    }

    func testFewPuzzlesAreNoEvidence() {
        let stats = ["fork": ThemeRecord(attempts: 4, clean: 4)]
        XCTAssertNil(ChessDNA.make(games: [], puzzleStats: stats).weapon)
    }

    // MARK: Growth

    func testFewerMistakesLatelyShowAsGrowth() throws {
        // The older games each had three bad moves in the middlegame; the newest are clean.
        let bad: [Int: MoveReview.Grade] = [27: .blunder, 31: .mistake, 35: .mistake]
        let old = (0..<4).map { Self.game(Self.quietLondon, accuracy: 60, daysAgo: 10 + Double($0), grades: bad) }
        let new = (0..<4).map { Self.game(Self.quietLondon, accuracy: 88, daysAgo: Double($0)) }
        let dna = ChessDNA.make(games: old + new)
        let improved = try XCTUnwrap(dna.biggestImprovement)
        XCTAssertEqual(improved.now, 0, accuracy: 0.001)
        XCTAssertEqual(dna.trends.reduce(0) { $0 + $1.before }, 3, accuracy: 0.001)
        XCTAssertTrue(dna.trends.allSatisfy { $0.now == 0 })
        XCTAssertEqual(dna.accuracyTrend, ChessDNA.AccuracyTrend(before: 60, now: 88))
    }

    func testNoGrowthUntilThereAreTwoWindowsOfGames() {
        let games = (0..<5).map { Self.game(Self.quietLondon, daysAgo: Double($0)) }
        XCTAssertTrue(ChessDNA.make(games: games).trends.isEmpty)
        XCTAssertNil(ChessDNA.make(games: games).accuracyTrend)
    }

    // MARK: What the coach learned

    func testTheGameThatRevealsTheStyleSaysSo() throws {
        let games = (0..<3).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let before = ChessDNA.make(games: Array(games.dropFirst()))
        let after = ChessDNA.make(games: games)
        let line = try XCTUnwrap(ChessDNA.learned(before: before, after: after, game: games[0]))
        XCTAssertTrue(line.contains("an Attacker"), line)
    }

    func testAnotherGameInAnOpeningKeepsCount() throws {
        let games = (0..<2).map { Self.game(Self.quietLondon, result: .win, daysAgo: Double($0)) }
        let before = ChessDNA.make(games: [games[1]])
        let after = ChessDNA.make(games: games)
        let line = try XCTUnwrap(ChessDNA.learned(before: before, after: after, game: games[0]))
        XCTAssertEqual(line, "You're 2–0–0 with the Queen's Pawn Game as White now.")
        let first = try XCTUnwrap(ChessDNA.learned(before: ChessDNA.make(games: []), after: before, game: games[1]))
        XCTAssertTrue(first.hasPrefix("First time I've seen you in the Queen's Pawn Game"), first)
    }

    // MARK: Today's training

    @MainActor
    func testTodaysPuzzlesWarmUpOnTheWeaponAndFitTheStyle() throws {
        let pack = try XCTUnwrap(PuzzleLibrary.bundled())
        let store = TrainingStore(library: try XCTUnwrap(TrainingLibrary.shared))
        let games = (0..<4).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let stats = ["fork": ThemeRecord(attempts: 30, clean: 27), "pin": ThemeRecord(attempts: 30, clean: 12)]
        let dna = ChessDNA.make(games: games, puzzleStats: stats, puzzlesPlayed: 60)
        XCTAssertEqual(dna.style, .attacker)
        XCTAssertEqual(dna.weapon?.theme, "fork")
        let now = Date()
        let plan = try XCTUnwrap(store.todayPlan(puzzles: pack, rating: 1_500, played: 60, recent: [],
                                                 report: dna.report, dna: dna, now: now))
        XCTAssertTrue(plan.reason?.contains("your weapon") ?? false, plan.reason ?? "")
        func themes(_ role: SessionItem.Role) -> [String] {
            guard let item = plan.items.first(where: { $0.role == role }), case .drill(let drill) = item.content,
                  let id = drill.lichessPuzzleID, let puzzle = pack.puzzle(id: id) else { return [] }
            return puzzle.themes
        }
        XCTAssertTrue(themes(.warmUp).contains("fork"), "\(themes(.warmUp))")
        let style = try XCTUnwrap(dna.styleTheme(on: now))
        XCTAssertFalse(Set(themes(.mixed)).isDisjoint(with: style.tags), "\(themes(.mixed)) for \(style.id)")
    }
}
