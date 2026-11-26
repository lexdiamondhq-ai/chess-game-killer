import ChessKit
import XCTest
@testable import ChessGameKiller

/// Your Chess DNA: the style, strengths, openings and growth the coach reads from the
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

    func testAnOpeningThatKeepsScoringIsSomethingThePlayerIsGoodAt() throws {
        let games = [
            Self.game(Self.friedLiver, result: .win, daysAgo: 1),
            Self.game(Self.friedLiver, result: .win, daysAgo: 2),
            Self.game(Self.friedLiver, result: .loss, daysAgo: 3),
            Self.game(Self.quietLondon, result: .draw, daysAgo: 4),
        ]
        let dna = ChessDNA.make(games: games)
        let opening = try XCTUnwrap(dna.strengths.first)
        XCTAssertEqual(opening.title, "Italian Game as White")
        XCTAssertEqual(opening.detail, "2 wins, 1 loss.")
        // The proof is the games themselves, newest first, each as a whole.
        XCTAssertEqual(opening.sightings.map(\.game), games.prefix(3).map(\.id))
        XCTAssertTrue(opening.sightings.allSatisfy { $0.ply == 0 })
        // An opening has no puzzles to sharpen it, so it is no weapon.
        XCTAssertNil(opening.theme)
        XCTAssertNil(dna.weapon)

        // Two games aren't a habit, and half the points isn't doing well.
        XCTAssertNil(ChessDNA.bestOpening(in: Array(games.prefix(2)), index: .shared))
        let even = [Self.game(Self.friedLiver, result: .win), Self.game(Self.friedLiver, result: .loss),
                    Self.game(Self.friedLiver, result: .draw)]
        XCTAssertNil(ChessDNA.bestOpening(in: even, index: .shared))
        let unbeaten = (0..<3).map { Self.game(Self.friedLiver, result: $0 == 0 ? .draw : .win, daysAgo: Double($0)) }
        XCTAssertEqual(ChessDNA.bestOpening(in: unbeaten, index: .shared)?.detail, "2 wins, 1 draw, no losses.")
    }

    // MARK: Style

    func testTooFewGamesNamesNoStyle() {
        // Seven games: one short of a name. Three used to be enough, and one odd game renamed the player.
        let dna = ChessDNA.make(games: (0..<7).map { Self.game(Self.friedLiver, daysAgo: Double($0)) })
        XCTAssertNil(dna.style)
        XCTAssertNil(dna.styleNote)
        XCTAssertTrue(dna.traits.allSatisfy { $0.value == nil })
        XCTAssertTrue(dna.traits.allSatisfy { $0.word == "Not enough yet" && $0.comparison == "Not enough yet" })
        XCTAssertTrue(dna.picks.isEmpty)
    }

    func testChecksCapturesAndASacrificeMakeAnAttacker() throws {
        let games = (0..<8).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertGreaterThanOrEqual(habits.sacrifices, 1, "Nxf7 gives a knight for a pawn")
        XCTAssertNil(habits.castledOn)
        XCTAssertGreaterThan(habits.checks, 0)
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.style, .attacker)
        XCTAssertEqual(dna.styleNote, "Named from 8 games. It stays until your games really change.")
        // Sharper and more daring than nearly every real player measured.
        let aggression = try XCTUnwrap(dna.traits.first { $0.kind == .aggression })
        let risk = try XCTUnwrap(dna.traits.first { $0.kind == .risk })
        XCTAssertGreaterThan(aggression.value ?? 0, 0.9)
        XCTAssertGreaterThan(risk.value ?? 0, 0.9)
        XCTAssertEqual(aggression.word, "Aggressive")
        XCTAssertEqual(aggression.comparison, "More aggressive than 9 in 10")
        XCTAssertEqual(risk.comparison, "More daring than 9 in 10")
    }

    func testMaterialGoingInALostGameIsNotASacrifice() {
        // The same knight on f7, but with the engine saying the game was already lost
        // before each move: that is losing more, not daring.
        var game = Self.game(Self.friedLiver)
        XCTAssertGreaterThanOrEqual(ChessDNA.GameHabits(game).sacrifices, 1)
        game.moments = game.moments.map {
            SavedMoment(ply: $0.ply, grade: $0.grade, san: $0.san, uci: $0.uci, byWhite: $0.byWhite,
                        fenBefore: $0.fenBefore, fenAfter: $0.fenAfter, before: -0.6, after: -0.6)
        }
        XCTAssertEqual(ChessDNA.GameHabits(game).sacrifices, 0)
        // Nor is giving material back when the game is as good as won.
        game.moments = game.moments.map {
            SavedMoment(ply: $0.ply, grade: $0.grade, san: $0.san, uci: $0.uci, byWhite: $0.byWhite,
                        fenBefore: $0.fenBefore, fenAfter: $0.fenAfter, before: 0.95, after: 0.95)
        }
        XCTAssertEqual(ChessDNA.GameHabits(game).sacrifices, 0)
    }

    func testQuietSafeGamesMakeABuilder() throws {
        let games = (0..<8).map { Self.game(Self.quietLondon, result: .draw, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertEqual(habits.castledOn, 6)
        XCTAssertEqual(habits.captures, 0)
        XCTAssertEqual(habits.sacrifices, 0)
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.style, .builder)
        XCTAssertEqual(dna.traits.first { $0.kind == .aggression }?.word, "Quiet")
        XCTAssertEqual(dna.traits.first { $0.kind == .aggression }?.comparison, "Quieter than 9 in 10")
        XCTAssertEqual(dna.traits.first { $0.kind == .risk }?.word, "Safe")
        XCTAssertEqual(dna.traits.first { $0.kind == .risk }?.comparison, "Safer than 9 in 10")
        // Long enough games with nothing traded early: a little more patient than most, not clearly.
        XCTAssertEqual(dna.traits.first { $0.kind == .patience }?.word, "Balanced")
        XCTAssertEqual(dna.traits.first { $0.kind == .patience }?.comparison, "Like most players")
    }

    func testPlayingAsBlackReadsBlacksMoves() {
        let games = (0..<8).map { Self.game(Self.quietLondon, white: false, result: .draw, daysAgo: Double($0)) }
        let habits = ChessDNA.GameHabits(games[0])
        XCTAssertEqual(habits.castledOn, 5)
        XCTAssertEqual(habits.moves, 24)
        XCTAssertNotNil(ChessDNA.make(games: games).style)
    }

    func testAGameAgainstAPersonIsReadOnceItIsGraded() {
        // Kept the moment it ends, with no grades: only replayed until Leo has read it.
        var games = (0..<8).map { Self.game(Self.friedLiver, daysAgo: Double($0), level: nil) }
        let waiting = ChessDNA.make(games: games)
        XCTAssertEqual(waiting.gamesRead, 0)
        XCTAssertNil(waiting.style)
        // Graded (the player's moves only, as the fixture has them), it counts like any other game.
        for index in games.indices { games[index].graded = true }
        let read = ChessDNA.make(games: games)
        XCTAssertEqual(read.gamesRead, 8)
        XCTAssertEqual(read.style, .attacker)
    }

    // MARK: The style rule

    /// One real player from the sample the ruler was measured on: quiet, patient, and not good
    /// at coming back. The numbers the app must give are the ones the measurement gave.
    func testTheHabitThatStandsOutMostNamesTheStyle() throws {
        let traits = [
            ChessDNA.Trait(kind: .aggression, standing: RealPlayers.aggression.standing(of: 0.4063)),
            ChessDNA.Trait(kind: .risk, standing: RealPlayers.risk.standing(of: 0.25)),
            ChessDNA.Trait(kind: .patience, standing: RealPlayers.patience.standing(of: 0.4466)),
            ChessDNA.Trait(kind: .endgames, standing: RealPlayers.area(.endgames).standing(of: 0.2946)),
        ]
        XCTAssertEqual(try XCTUnwrap(traits[0].value), 0.1126, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(traits[2].value), 0.7864, accuracy: 0.002)
        let scores = ChessDNA.styleScores(traits: traits, comebacks: 0.1538)
        XCTAssertEqual(try XCTUnwrap(scores[.attacker]), 0.285, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(scores[.tactician]), 0.328, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(scores[.builder]), 0.715, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(scores[.grinder]), 0.616, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(scores[.counterpuncher]), 0.534, accuracy: 0.002)
        XCTAssertEqual(ChessDNA.style(scores: scores, current: nil), .builder)
        // Until comebacks and endgames can be judged, those two styles aren't in the running.
        let early = ChessDNA.styleScores(traits: Array(traits.prefix(3)), comebacks: nil)
        XCTAssertEqual(Set(early.keys), [.attacker, .tactician, .builder])
    }

    func testNothingStandingOutIsAnAllRounder() {
        let scores: [ChessDNA.Style: Double] = [.attacker: 0.55, .tactician: 0.61, .builder: 0.45, .grinder: 0.5]
        XCTAssertEqual(ChessDNA.style(scores: scores, current: nil), .allRounder)
        XCTAssertEqual(ChessDNA.style(scores: [:], current: nil), .allRounder)
    }

    func testANamedStyleStaysUntilAnotherClearlyPassesIt() {
        // The builder's habits slip a little and the grinder's edge ahead: not enough to rename.
        var scores: [ChessDNA.Style: Double] = [.builder: 0.66, .grinder: 0.72, .attacker: 0.3, .tactician: 0.4]
        XCTAssertEqual(ChessDNA.style(scores: scores, current: nil), .grinder, "With no name yet, the top one is it")
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .builder), .builder)
        // Clearly past it: the name changes.
        scores[.grinder] = 0.79
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .builder), .grinder)
        // Nothing stands out any more, but the old habits are still close: the name stays...
        scores = [.builder: 0.55, .grinder: 0.58, .attacker: 0.4, .tactician: 0.45]
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .builder), .builder)
        // ...and goes once they are really gone.
        scores[.builder] = 0.45
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .builder), .allRounder)
        // An all-rounder needs clear proof before getting a name, too.
        scores = [.builder: 0.7, .grinder: 0.5, .attacker: 0.3, .tactician: 0.4]
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .allRounder), .allRounder)
        scores[.builder] = 0.75
        XCTAssertEqual(ChessDNA.style(scores: scores, current: .allRounder), .builder)
    }

    func testOneOddGameDoesNotRenameThePlayerAndARealChangeDoes() {
        // Eight quiet games name a builder. Then wild ones, one after another.
        let quiet = (0..<8).map { Self.game(Self.quietLondon, result: .draw, daysAgo: 30 + Double($0)) }
        func style(afterWild wild: Int) -> ChessDNA.Style? {
            let games = (0..<wild).map { Self.game(Self.friedLiver, daysAgo: Double(wild - $0)) }
            // Whatever order the games are handed over in, they are read oldest first.
            return ChessDNA.make(games: (quiet + games).shuffled()).style
        }
        XCTAssertEqual(style(afterWild: 0), .builder)
        XCTAssertEqual(style(afterWild: 2), .builder)
        // Three in, nothing stands out enough to name any more: the name holds, the old habits are close.
        XCTAssertEqual(style(afterWild: 3), .builder)
        // Twenty in, the newest twenty games are all wild: the player is an attacker now.
        XCTAssertEqual(style(afterWild: 20), .attacker)
    }

    func testTheHabitsComeFromTheNewestGames() throws {
        // Thirty quiet games long ago, twenty wild ones since: the bars read the wild ones.
        let old = (0..<30).map { Self.game(Self.quietLondon, result: .draw, daysAgo: 100 + Double($0)) }
        let new = (0..<20).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let dna = ChessDNA.make(games: old + new)
        XCTAssertEqual(dna.gamesCounted, 50)
        XCTAssertEqual(dna.traits.first { $0.kind == .aggression }?.word, "Aggressive")
        XCTAssertEqual(dna.styleNote, "Named from your last 20 games. It stays until your games really change.")
    }

    func testComingBackCountsOnlyGamesThatWereGoingBadlyInPlay() {
        // A lost game the player never stood clearly worse in isn't one they failed to save:
        // every lost game ends badly, and that used to count.
        let lost = Self.game(Self.quietLondon, result: .loss)
        XCTAssertFalse(ChessDNA.GameHabits(lost).wasWorse)
        // Clearly worse after one of the player's own moves.
        func slipped(_ result: SavedGame.Result) -> SavedGame {
            var game = Self.game(Self.quietLondon, result: result)
            game.moments = game.moments.map {
                SavedMoment(ply: $0.ply, grade: $0.grade, san: $0.san, uci: $0.uci, byWhite: $0.byWhite,
                            fenBefore: $0.fenBefore, fenAfter: $0.fenAfter, before: $0.before,
                            after: $0.ply == 27 ? -0.5 : $0.after)
            }
            return game
        }
        XCTAssertTrue(ChessDNA.GameHabits(slipped(.win)).saved)
        XCTAssertTrue(ChessDNA.GameHabits(slipped(.loss)).wasWorse)
        XCTAssertFalse(ChessDNA.GameHabits(slipped(.loss)).saved)
        var sums = ChessDNA.HabitSums()
        XCTAssertNil(sums.comebacks)
        for _ in 0..<2 { sums.add(ChessDNA.GameHabits(slipped(.win))) }
        XCTAssertNil(sums.comebacks, "Two such games aren't enough to judge")
        sums.add(ChessDNA.GameHabits(slipped(.loss)))
        XCTAssertEqual(sums.comebacks ?? 0, 2.0 / 3.0, accuracy: 0.001)
    }

    func testGamesTooShortToReadDontCountTowardTheStyle() {
        // Three games given up after two moves: read, but nothing to read a style from.
        let short = (0..<3).map { Self.game("e2e4 e7e5 g1f3 b8c6", result: .loss, daysAgo: Double($0)) }
        let dna = ChessDNA.make(games: short)
        XCTAssertEqual(dna.gamesRead, 3)
        XCTAssertEqual(dna.gamesCounted, 0)
        XCTAssertNil(dna.style)
        // The wait used to say "one more game" for ever: three were read, so none seemed left.
        XCTAssertEqual(dna.styleWait, "Play 8 more games of ten moves or more")

        let seven = ChessDNA.make(games: (0..<7).map { Self.game(Self.quietLondon, daysAgo: Double($0)) })
        XCTAssertEqual(seven.gamesCounted, 7)
        XCTAssertEqual(seven.styleWait, "Play one more game")
    }

    func testTheFootnoteSaysWhichGamesCountAndWhatTheBarsMean() {
        var imported = Self.game(Self.quietLondon, daysAgo: 1, level: nil)
        imported.source = "lichess"
        var friend = Self.game(Self.quietLondon, daysAgo: 2, level: nil)
        friend.graded = true
        let all = ChessDNA.make(games: [Self.game(Self.quietLondon), imported, friend])
        XCTAssertEqual(all.gamesRead, 3)
        XCTAssertEqual(all.gamesImported, 1)
        XCTAssertTrue(all.basisNote.hasPrefix("Read from 3 games and your rated puzzles."), all.basisNote)
        XCTAssertTrue(all.basisNote.contains("against people"), all.basisNote)
        XCTAssertTrue(all.basisNote.contains("your newest 20 games, next to 155 real online players"), all.basisNote)
        XCTAssertFalse(all.basisNote.contains("aren't counted"), all.basisNote)
    }

    // MARK: Good at

    /// 1.e4 e5 2.Nf3 Qh4, and the queen is taken for nothing.
    static let freeQueen = "e2e4 e7e5 g1f3 d8h4 f3h4"
    /// The same, and the queen is left standing.
    static let queenLeft = "e2e4 e7e5 g1f3 d8h4 d2d3"

    /// A game where the free queen was missed: the engine's move was to take it.
    static func missedQueen(daysAgo: Double, grade: MoveReview.Grade = .blunder) -> SavedGame {
        var game = Self.game(Self.queenLeft, daysAgo: daysAgo, grades: [5: grade])
        game.moments = game.moments.map { moment in
            guard moment.ply == 5 else { return moment }
            return SavedMoment(ply: moment.ply, grade: moment.grade, san: moment.san, uci: moment.uci,
                               byWhite: moment.byWhite, fenBefore: moment.fenBefore, fenAfter: moment.fenAfter,
                               best: "Nxh4", bestUCI: "f3h4", before: moment.before, after: moment.after)
        }
        return game
    }

    func testAPatternThePlayerKeepsFindingComesFirstWithItsProof() throws {
        let games = (0..<4).map { Self.game(Self.freeQueen, daysAgo: Double($0), grades: [5: .best]) }
        let dna = ChessDNA.make(games: games)
        let first = try XCTUnwrap(dna.strengths.first)
        XCTAssertEqual(first.title, "Free pieces")
        XCTAssertEqual(first.detail, "You took 4 of 4. Most players take 3.")
        XCTAssertEqual(first.theme, "hangingPiece")
        // Each place it happened, newest game first, so the list can open the game at that move.
        XCTAssertEqual(first.sightings, games.map { ChessDNA.Sighting(game: $0.id, ply: 5) })
        // The first thing with puzzles behind it is the weapon.
        XCTAssertEqual(dna.weapon?.title, "Free pieces")
        XCTAssertEqual(dna.weapon?.theme, "hangingPiece")
        XCTAssertLessThanOrEqual(dna.strengths.count, ChessDNA.strengthLimit)
    }

    func testThreeChancesAreTooFewToCallAStrength() {
        let games = (0..<3).map { Self.game(Self.freeQueen, daysAgo: Double($0), grades: [5: .best]) }
        XCTAssertFalse(ChessDNA.make(games: games).strengths.contains { $0.title == "Free pieces" })
    }

    func testFindingItHalfTheTimeIsNoStrengthAndTheMissesAreSomethingToWorkOn() throws {
        // Taken twice, left standing twice: real players take two in three.
        let games = [Self.game(Self.freeQueen, daysAgo: 0, grades: [5: .best]), Self.missedQueen(daysAgo: 1),
                     Self.game(Self.freeQueen, daysAgo: 2, grades: [5: .best]), Self.missedQueen(daysAgo: 3)]
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.report.missed[.missedFreePiece], 2)
        XCTAssertFalse(dna.strengths.contains { $0.title == "Free pieces" })
        XCTAssertNil(dna.weapon)
        let spot = try XCTUnwrap(dna.weakSpots.first)
        XCTAssertEqual(dna.leak, spot)
        XCTAssertEqual(spot.headline, "Free pieces left on the board")
        XCTAssertEqual(spot.proof, "Missed twice.")
        XCTAssertEqual(spot.positions, .skills(["free-pieces"]))
    }

    func testAnAreaAheadOfMostPlayersIsAStrengthOnceThereAreEnoughGames() throws {
        // Quiet draws without a costly move: nothing to say about the opening, plenty about care.
        func dna(games count: Int) -> ChessDNA {
            ChessDNA.make(games: (0..<count).map { Self.game(Self.quietLondon, result: .draw, daysAgo: Double($0)) })
        }
        // Seven games is too few to put next to real players: a clean game or two proves little.
        XCTAssertTrue(dna(games: CoachReport.gamesToCompare - 1).strengths.isEmpty)
        let compared = dna(games: CoachReport.gamesToCompare)
        XCTAssertEqual(compared.strengths.map(\.title), ["Keeping pieces safe", "Tactics", "Openings"])
        XCTAssertTrue(compared.strengths.allSatisfy { $0.detail == "Better than 9 in 10 players." })
        XCTAssertTrue(compared.strengths.allSatisfy { $0.sightings.isEmpty })
        XCTAssertEqual(compared.weapon?.theme, "defensiveMove")
        // Checkmates isn't there: more than half of real players never miss a short mate either.
        XCTAssertFalse(compared.strengths.contains { $0.title == "Checkmates" })
    }

    func testAnAreaToWorkOnIsNotAlsoListedAsAStrength() {
        // Nine games, a free queen left standing in six of them, each a small slip by the
        // engine's count. That is still ahead of most real players in tactics, and it is the
        // one thing there is to work on: it goes in that list and not in this one.
        let games = (0..<9).map { day in
            day < 6 ? Self.missedQueen(daysAgo: Double(day), grade: .inaccuracy)
                    : Self.game(Self.freeQueen, daysAgo: Double(day))
        }
        let dna = ChessDNA.make(games: games)
        XCTAssertEqual(dna.report.scores.first { $0.area == .tactics }?.verdict, "Better than 7 in 10")
        XCTAssertEqual(dna.weakSpots.map(\.area), [.tactics])
        XCTAssertEqual(dna.leak?.proof, "Missed 6 times.")
        XCTAssertFalse(dna.strengths.contains { $0.title == "Tactics" })
        XCTAssertTrue(dna.strengths.contains { $0.title == "Keeping pieces safe" })
    }

    // MARK: Weapon

    func testATradeIsNotCountedAsAFreePieceTaken() throws {
        // The Exchange Ruy Lopez as Black, four times: 4...dxc6 takes back a bishop that
        // just took a knight. That used to count as four free pieces and make the weapon.
        let line = "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5c6 d7c6"
        let games = (0..<4).map { Self.game(line, white: false, daysAgo: Double($0), grades: [8: .best]) }
        let moment = try XCTUnwrap(games[0].playerMoments.last)
        XCTAssertEqual(MomentFinder.find(in: moment.review)?.kind, .foundFreePiece)
        XCTAssertNil(MomentFinder.find(in: games[0].review(of: moment)))
        let dna = ChessDNA.make(games: games)
        XCTAssertNotEqual(dna.weapon?.title, "Free pieces")
        XCTAssertFalse(dna.strengths.contains { $0.title == "Free pieces" })
    }

    func testWhereAPuzzleCameFromIsNotAWeapon() throws {
        // "From master games" says where a puzzle is from, not what the player is good at.
        let stats = ["masterVsMaster": ThemeRecord(attempts: 20, clean: 20), "fork": ThemeRecord(attempts: 20, clean: 19),
                     "pin": ThemeRecord(attempts: 40, clean: 10)]
        let weapon = try XCTUnwrap(ChessDNA.make(games: [], puzzleStats: stats).weapon)
        XCTAssertEqual(weapon.theme, "fork")
    }

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
        let games = (0..<8).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let before = ChessDNA.make(games: Array(games.dropFirst()))
        XCTAssertNil(before.style)
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
        let games = (0..<8).map { Self.game(Self.friedLiver, daysAgo: Double($0)) }
        let stats = ["fork": ThemeRecord(attempts: 30, clean: 27), "pin": ThemeRecord(attempts: 30, clean: 12)]
        let dna = ChessDNA.make(games: games, puzzleStats: stats, puzzlesPlayed: 60)
        XCTAssertEqual(dna.style, .attacker)
        // Eight games without a costly move: nothing left hanging is the weapon the games show.
        let weapon = try XCTUnwrap(dna.weaponTheme)
        XCTAssertEqual(dna.weapon?.title, "Keeping pieces safe")
        let now = Date()
        let plan = try XCTUnwrap(store.todayPlan(puzzles: pack, rating: 1_500, played: 60, recent: [],
                                                 report: dna.report, dna: dna, now: now))
        XCTAssertTrue(plan.reason?.contains("your weapon") ?? false, plan.reason ?? "")
        func themes(_ role: SessionItem.Role) -> [String] {
            guard let item = plan.items.first(where: { $0.role == role }), case .drill(let drill) = item.content,
                  let id = drill.lichessPuzzleID, let puzzle = pack.puzzle(id: id) else { return [] }
            return puzzle.themes
        }
        XCTAssertFalse(Set(themes(.warmUp)).isDisjoint(with: weapon.tags), "\(themes(.warmUp)) for \(weapon.id)")
        // The style puzzle comes from one of the style's themes. Not always the day's first: when
        // that one is also the day's focus (every 28 days for the Attacker), the plan moves to the
        // next, so check against the whole list.
        let style = try XCTUnwrap(dna.style)
        let styleTags = Set(style.themes.flatMap { PuzzleTheme.named($0).tags })
        XCTAssertFalse(Set(themes(.mixed)).isDisjoint(with: styleTags), "\(themes(.mixed)) for \(style.rawValue)")
    }
}
