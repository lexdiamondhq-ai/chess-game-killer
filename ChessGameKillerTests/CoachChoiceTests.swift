import ChessKit
import XCTest
@testable import ChessGameKiller

/// Two coaches, Leo and Vera: the course in each one's words, their recordings, the picker's
/// memory, and the short spoken reactions in drills (when they come, and which line).
@MainActor
final class CoachChoiceTests: XCTestCase {

    // MARK: Coaches

    func testVeraTakesLeosPlaceInTheWords() {
        XCTAssertEqual(Coach.vera.personalize("Hi, I'm Leo, your coach. Coach Leo's course."),
                       "Hi, I'm Vera, your coach. Coach Vera's course.")
        // Only the name: other words that start the same way stay.
        XCTAssertEqual(Coach.vera.personalize("Leonardo and Leon"), "Leonardo and Leon")
        XCTAssertEqual(Coach.leo.personalize("Hi, I'm Leo."), "Hi, I'm Leo.")
        XCTAssertEqual(Coach.leo.piece, .knight)
        XCTAssertEqual(Coach.vera.piece, .queen)
    }

    func testEachCoachHasOwnRecordings() {
        // Leo's names never change, so his existing recordings keep working.
        XCTAssertEqual(CoachVoice.fileName(for: "Hello"), "nar-f7ff9e8b7bb2")
        XCTAssertEqual(CoachVoice.fileName(for: "Hello", coach: .leo), "nar-f7ff9e8b7bb2")
        XCTAssertEqual(CoachVoice.fileName(for: "Hello", coach: .vera), "vera-f7ff9e8b7bb2")
    }

    func testThePickIsRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoachChoiceTests"))
        defaults.removePersistentDomain(forName: "CoachChoiceTests")
        XCTAssertEqual(CoachChoice(defaults: defaults).coach, .leo)
        CoachChoice(defaults: defaults).coach = .vera
        XCTAssertEqual(CoachChoice(defaults: defaults).coach, .vera)
        defaults.removePersistentDomain(forName: "CoachChoiceTests")
    }

    func testVeraTeachesTheSameCourseInHerWords() throws {
        let leo = try XCTUnwrap(TrainingLibrary.shared)
        XCTAssertTrue(leo.taught(by: .leo) === leo)
        let vera = leo.taught(by: .vera)
        XCTAssertTrue(vera === leo.taught(by: .vera), "made once")
        XCTAssertEqual(vera.coach.name, "Vera")
        XCTAssertEqual(vera.lessons.map(\.id), leo.lessons.map(\.id))
        XCTAssertEqual(vera.drills.count, leo.drills.count)
        let welcome = try XCTUnwrap(vera.lesson("welcome"))
        XCTAssertEqual(welcome.title, "Meet Coach Vera")
        XCTAssertTrue(welcome.steps.first?.say?.hasPrefix("Hi, I'm Vera") == true)
        // Nothing of Leo's name is left in anything she says.
        let said = vera.lessons.flatMap(\.steps).compactMap(\.say)
        XCTAssertFalse(said.contains { $0.range(of: #"\bLeo\b"#, options: .regularExpression) != nil })
    }

    func testTheStoreFollowsThePick() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoachChoiceStore"))
        defaults.removePersistentDomain(forName: "CoachChoiceStore")
        let choice = CoachChoice(defaults: defaults)
        let store = TrainingStore(library: TrainingLibrary.shared, coach: choice)
        XCTAssertEqual(store.library?.coach.name, "Leo")
        choice.coach = .vera
        XCTAssertEqual(store.library?.coach.name, "Vera")
        XCTAssertEqual(store.library?.lesson("welcome")?.title, "Meet Coach Vera")
        defaults.removePersistentDomain(forName: "CoachChoiceStore")
    }

    func testTalkItThroughAsksForVeraByName() throws {
        var request = TalkRequest(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", said: "rook to a8", typed: true,
                                  reveal: false, context: .session, lastMove: nil, voice: true, facts: nil)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(object["coach"], "Leo is the server's default")
        request.coach = Coach.vera.rawValue
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["coach"] as? String, "vera")
    }

    // MARK: Reaction lines

    func testEveryCoachHasLinesForEveryMoment() throws {
        let lines = try XCTUnwrap(ReactionLines.bundled)
        for coach in Coach.allCases {
            for moment in ReactionMoment.allCases {
                let options = lines.lines(for: coach, moment)
                XCTAssertFalse(options.isEmpty, "\(coach.name) has nothing for \(moment)")
                for line in options {
                    XCTAssertLessThanOrEqual(line.count, 60, "\(coach.name): too long to be a reaction: \(line)")
                }
            }
            // Alex didn't want it said.
            XCTAssertFalse(ReactionMoment.allCases.flatMap { lines.lines(for: coach, $0) }
                .contains { $0.lowercased().contains("why did you do that") })
            XCTAssertTrue(lines.lines(for: coach, .tryAgain).contains("Try again."))
        }
    }

    func testEveryReactionIsRecordedInTheCoachsVoice() throws {
        let lines = try XCTUnwrap(ReactionLines.bundled)
        for coach in Coach.allCases {
            for moment in ReactionMoment.allCases {
                for line in lines.lines(for: coach, moment) {
                    XCTAssertTrue(CoachVoice.hasRecording(for: line, coach: coach),
                                  "No recording of \(coach.name) saying \"\(line)\" (scripts/training/make_narration.py)")
                }
            }
        }
    }

    // MARK: When the coach speaks up

    private func lines(_ moment: ReactionMoment) -> [String] {
        ["\(moment.rawValue) 1", "\(moment.rawValue) 2", "\(moment.rawValue) 3"]
    }

    func testBigMomentsAlwaysGetAReactionAndOrdinaryOnesOnlySometimes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // A roll of 0.8 is above every ordinary chance after the first solve of a sitting.
        var policy = ReactionPolicy(random: { 0.8 })
        XCTAssertNotNil(policy.line(for: .nice, now: start, lines: lines), "the first solve of a sitting")
        XCTAssertNil(policy.line(for: .nice, now: start + 10, lines: lines))
        XCTAssertNil(policy.line(for: .tryAgain, now: start + 20, lines: lines))
        XCTAssertNil(policy.line(for: .keepGoing, now: start + 30, lines: lines))
        XCTAssertNotNil(policy.line(for: .brilliant, now: start + 40, lines: lines))
        XCTAssertNotNil(policy.line(for: .blunder, now: start + 50, lines: lines))
    }

    func testNeverTwoReactionsOnTopOfEachOther() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var policy = ReactionPolicy(random: { 0 })
        XCTAssertNotNil(policy.line(for: .tryAgain, now: start, lines: lines))
        XCTAssertNil(policy.line(for: .tryAgain, now: start + 2, lines: lines), "within a few seconds")
        XCTAssertNotNil(policy.line(for: .tryAgain, now: start + 4, lines: lines))
        // A brilliant move is worth breaking the quiet for, after a moment.
        XCTAssertNotNil(policy.line(for: .brilliant, now: start + 5.5, lines: lines))
    }

    func testTheSameLineNeverComesTwiceInARow() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var policy = ReactionPolicy(random: { 0 })
        var previous: String?
        for step in 0..<12 {
            let line = policy.line(for: .tryAgain, now: start + Double(step) * 5, lines: lines)
            XCTAssertNotNil(line)
            XCTAssertNotEqual(line, previous)
            previous = line
        }
    }

    func testWhyDidYouDoThatAtMostOnceInAWhile() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var policy = ReactionPolicy(random: { 0 })
        XCTAssertTrue(policy.line(for: .blunder, now: start, lines: lines)?.hasPrefix("blunder") == true)
        XCTAssertTrue(policy.line(for: .blunder, now: start + 30, lines: lines)?.hasPrefix("tryAgain") == true)
        XCTAssertTrue(policy.line(for: .blunder, now: start + 200, lines: lines)?.hasPrefix("blunder") == true)
    }

    func testThreeFirstTrySolvesInARowAreAStreak() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var policy = ReactionPolicy(random: { 0 })
        XCTAssertTrue(policy.line(for: .nice, now: start, lines: lines)?.hasPrefix("nice") == true)
        XCTAssertTrue(policy.line(for: .nice, now: start + 10, lines: lines)?.hasPrefix("nice") == true)
        XCTAssertTrue(policy.line(for: .nice, now: start + 20, lines: lines)?.hasPrefix("streak") == true)
        // A miss starts the count again.
        _ = policy.line(for: .tryAgain, now: start + 30, lines: lines)
        XCTAssertTrue(policy.line(for: .nice, now: start + 40, lines: lines)?.hasPrefix("nice") == true)
    }

    func testPuzzleRushIsQuieter() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var policy = ReactionPolicy(random: { 0.3 })
        _ = policy.line(for: .nice, strict: true, now: start, lines: lines)
        XCTAssertNil(policy.line(for: .nice, strict: true, now: start + 10, lines: lines))
        XCTAssertNil(policy.line(for: .tryAgain, strict: true, now: start + 20, lines: lines))
        XCTAssertNil(policy.line(for: .keepGoing, strict: true, now: start + 30, lines: lines))
        XCTAssertNotNil(policy.line(for: .brilliant, strict: true, now: start + 40, lines: lines))
    }

    // MARK: What a drill tells the coach

    @MainActor
    private final class Heard: Reacting {
        var moments: [ReactionMoment] = []
        func react(_ moment: ReactionMoment, strict: Bool) { moments.append(moment) }
    }

    private func runner(_ json: String) throws -> (DrillRunner, Heard) {
        let drill = try JSONDecoder().decode(Drill.self, from: Data(json.utf8))
        let made = try XCTUnwrap(DrillRunner(item: SessionItem(content: .drill(drill), role: .focus), library: nil,
                                             engine: nil, playsSounds: false))
        XCTAssertNil(made.reactions, "no sound, no voice")
        let heard = Heard()
        made.reactions = heard
        return (made, heard)
    }

    private func started(_ runner: DrillRunner) async {
        runner.begin()
        for _ in 0..<60 where runner.phase != .solving {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(runner.phase, .solving)
    }

    private func move(_ runner: DrillRunner, _ uci: String) {
        guard let squares = Notation.squares(of: uci) else { return XCTFail("bad move \(uci)") }
        runner.tap(squares.from)
        runner.tap(squares.to)
    }

    private let backRank = """
    {"id": "r-1", "skill": "back-rank", "type": "move", "rating": 500, "fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1a8"], "mate": 1}
    """
    private let twoSteps = """
    {"id": "r-2", "skill": "back-rank", "type": "move", "rating": 600, "fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1a7", "h7h6", "a7a8"]}
    """
    // Black's bishop on b8 watches a7: a rook that goes there is simply lost.
    private let bishopWatches = """
    {"id": "r-3", "skill": "free-pieces", "type": "move", "rating": 500, "fen": "1b4k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1e1"]}
    """

    func testARightAnswerIsNice() async throws {
        let (runner, heard) = try runner(backRank)
        await started(runner)
        move(runner, "a1a8")
        XCTAssertEqual(heard.moments, [.nice])
    }

    func testALongPuzzleSolvedCleanlyIsBrilliant() async throws {
        let (runner, heard) = try runner(twoSteps)
        await started(runner)
        move(runner, "a1a7")
        for _ in 0..<40 where runner.phase != .solving {
            try await Task.sleep(for: .milliseconds(50))
        }
        move(runner, "a7a8")
        XCTAssertEqual(heard.moments, [.keepGoing, .brilliant])
    }

    func testAWrongMoveIsTryAgainAndASecondIsLeftToTheHint() async throws {
        let (runner, heard) = try runner(backRank)
        await started(runner)
        for wrong in ["h2h3", "g2g3"] {
            move(runner, wrong)
            for _ in 0..<40 where runner.phase != .solving {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        move(runner, "a1a8")
        XCTAssertEqual(heard.moments, [.tryAgain, .afterHelp])
    }

    func testGivingARookAwayGetsWhyDidYouDoThat() async throws {
        let (runner, heard) = try runner(bishopWatches)
        await started(runner)
        move(runner, "a1a7")
        XCTAssertEqual(heard.moments, [.blunder])
    }

    func testWhatCountsAsGivingAPieceAway() {
        let fen = "1b4k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        func played(_ uci: String, capture: Bool = false) -> PlayedMove {
            PlayedMove(uci: uci, san: uci, color: .white, fenBefore: fen, isCapture: capture, isCastle: false, givesCheck: false)
        }
        XCTAssertTrue(DrillRunner.givesPieceAway(played("a1a7")), "the bishop takes it for free")
        XCTAssertFalse(DrillRunner.givesPieceAway(played("a1a2")), "nothing hits a2")
        XCTAssertFalse(DrillRunner.givesPieceAway(played("f2f3")), "a pawn move isn't a lost piece")
        XCTAssertFalse(DrillRunner.givesPieceAway(played("g1f1")), "nor is a king move")
    }
}
