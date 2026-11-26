import XCTest
@testable import ChessGameKiller

/// The ruler Chess DNA measures against: where a number sits among the real players measured,
/// and the words a bar says about it.
final class RealPlayersTests: XCTestCase {

    func testEveryRulerRunsLowToHighInTwentySteps() {
        var rulers = [RealPlayers.aggression, RealPlayers.risk, RealPlayers.patience, RealPlayers.comebacks]
        rulers += CoachReport.Area.allCases.map { RealPlayers.area($0) }
        XCTAssertEqual(rulers.count, 10)
        for ruler in rulers {
            XCTAssertEqual(ruler.marks.count, 21)
            XCTAssertEqual(ruler.marks, ruler.marks.sorted())
            XCTAssertLessThan(ruler.marks[0], ruler.marks[20], "Players differ on every measure")
        }
    }

    func testAValueSitsWhereItFallsAmongThePlayers() {
        // Twenty-one players scoring 0, 1, 2 and so on up to 20.
        let ruler = RealPlayers.Ruler(marks: (0...20).map(Double.init))
        // Level with the sixth of them: five below, fifteen above.
        let level = ruler.standing(of: 5)
        XCTAssertEqual(level.below, 0.25, accuracy: 0.0001)
        XCTAssertEqual(level.above, 0.75, accuracy: 0.0001)
        XCTAssertEqual(level.place, 0.25, accuracy: 0.0001)
        // Halfway to the next one.
        let between = ruler.standing(of: 5.5)
        XCTAssertEqual(between.below, 0.275, accuracy: 0.0001)
        XCTAssertEqual(between.above, 0.725, accuracy: 0.0001)
        // Past either end.
        XCTAssertEqual(ruler.standing(of: -3), RealPlayers.Standing(below: 0, above: 1))
        XCTAssertEqual(ruler.standing(of: 30), RealPlayers.Standing(below: 1, above: 0))
        XCTAssertEqual(ruler.standing(of: -3).place, 0)
        XCTAssertEqual(ruler.standing(of: 30).place, 1)
        // The middle one is the typical player.
        XCTAssertEqual(ruler.standing(of: 10).place, 0.5, accuracy: 0.0001)
    }

    func testAScoreMostPlayersShareIsNotBetterThanMost() {
        // More than half of the players never missed a short mate in their twenty games.
        let perfect = RealPlayers.area(.checkmates).standing(of: 1)
        XCTAssertEqual(perfect.below, 0.45, accuracy: 0.0001)
        XCTAssertEqual(perfect.above, 0, accuracy: 0.0001)
        XCTAssertFalse(perfect.isAhead)
        XCTAssertFalse(perfect.isBehind)
        XCTAssertEqual(perfect.words, "Like most players")
        // Drawn a little past the middle: level with the best, who are most of them.
        XCTAssertEqual(perfect.place, 0.725, accuracy: 0.0001)
        // One mate missed in twenty games and nearly everyone is ahead.
        XCTAssertEqual(RealPlayers.area(.checkmates).standing(of: 0.9).words, "Below most players")
        // Where few reach the top, the top is clearly ahead.
        XCTAssertEqual(RealPlayers.area(.safety).standing(of: 1).words, "Better than 9 in 10")
    }

    func testTheWordsOnABar() {
        func words(_ below: Double) -> String { RealPlayers.Standing(below: below, above: 1 - below).words }
        XCTAssertEqual(words(0.99), "Better than 9 in 10")
        XCTAssertEqual(words(1), "Better than 9 in 10", "Never ten in ten: there is always someone")
        XCTAssertEqual(words(0.8), "Better than 8 in 10")
        XCTAssertEqual(words(0.79), "Better than 7 in 10")
        XCTAssertEqual(words(0.7), "Better than 7 in 10")
        XCTAssertEqual(words(0.65), "Better than 6 in 10")
        // Not far enough from the middle to say so, either way.
        XCTAssertEqual(words(0.64), "Like most players")
        XCTAssertEqual(words(0.5), "Like most players")
        XCTAssertEqual(words(0.36), "Like most players")
        XCTAssertEqual(words(0.35), "Below most players")
        XCTAssertEqual(words(0), "Below most players")
    }

    func testHowFarAFindRateIsPastTheUsualOne() {
        // Real players play about three forks in four. All of them is well past that...
        XCTAssertEqual(RealPlayers.forks.lead(of: 1), 1.21, accuracy: 0.01)
        // ...the usual share is no lead at all, and half is behind.
        XCTAssertEqual(RealPlayers.forks.lead(of: 0.77), 0, accuracy: 0.0001)
        XCTAssertLessThan(RealPlayers.freePieces.lead(of: 0.5), 0)
        XCTAssertGreaterThan(RealPlayers.mates.lead(of: 0.9), ChessDNA.clearLead)
    }
}

/// Practice for one thing to work on: the player's own positions first, then more of the kind.
final class WeakSpotPracticeTests: XCTestCase {

    private let spot = CoachReport.Leak(area: .tactics, headline: "Free pieces left on the board", detail: "",
                                        skill: "free-pieces", action: "Practice free pieces",
                                        proof: "Missed twice.", positions: .skills(["free-pieces"]))

    /// A position saved from a game, due `days` from now.
    private func saved(_ id: String, skill: String = "free-pieces", dueIn days: Double = 0, fixed: Bool = false) -> GameMistake {
        let due = Date(timeIntervalSince1970: 1_800_000_000 + days * 86_400)
        return GameMistake(id: id, fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8", played: "h2h3",
                           skill: skill, title: "Missed", created: due, due: due, fixed: fixed)
    }

    /// Eight puzzles standing in for "more of the same kind".
    private func more() throws -> SessionPlan {
        let pack = try XCTUnwrap(PuzzleLibrary.bundled(), "The puzzle pack isn't in the app")
        let items = pack.puzzles.prefix(8).map { SessionItem(content: .drill($0.drill), role: .focus) }
        return SessionPlan(title: "Free piece", focus: nil, lesson: nil, items: items)
    }

    func testOnlyOpenPositionsOfThatKindCountTheOnesDueSoonestFirst() {
        let mistakes = [saved("late", dueIn: 5), saved("fork", skill: "forks"), saved("soon", dueIn: 1),
                        saved("done", dueIn: 0, fixed: true), saved("now", dueIn: 0)]
        XCTAssertEqual(SessionPlan.ownPositions(for: spot, in: mistakes).map(\.id), ["now", "soon", "late"])
    }

    func testPracticeStartsWithThePlayersOwnPositions() throws {
        let more = try more()
        let mistakes = (0..<7).map { saved("m\($0)", dueIn: Double($0)) } + [saved("fork", skill: "forks")]
        let plan = try XCTUnwrap(SessionPlan.practice(spot, mistakes: mistakes, more: more))
        XCTAssertEqual(plan.items.count, SessionPlan.weakSpotLength)
        // The five due soonest, as reviews...
        let own = plan.items.prefix(SessionPlan.ownPositionLimit)
        XCTAssertEqual(own.map(\.id), (0..<5).map { "m-m\($0)" })
        XCTAssertTrue(own.allSatisfy { $0.role == .review })
        // ...then the end of the run of puzzles, which keeps its easy finish.
        XCTAssertEqual(plan.items.suffix(3).map(\.id), more.items.suffix(3).map(\.id))
        XCTAssertEqual(plan.title, "Free pieces left on the board")
        XCTAssertEqual(plan.headline, "Free pieces left on the board")
        XCTAssertEqual(plan.reason, "Your own positions first, then puzzles of the same kind.")
    }

    func testFewOwnPositionsLeaveMoreRoomForPuzzles() throws {
        let more = try more()
        let plan = try XCTUnwrap(SessionPlan.practice(spot, mistakes: [saved("one")], more: more))
        XCTAssertEqual(plan.items.count, 8)
        XCTAssertEqual(plan.items.first?.id, "m-one")
        XCTAssertEqual(plan.items.dropFirst().map(\.id), more.items.suffix(7).map(\.id))
    }

    func testWithNoneOfTheirOwnItIsThePuzzlesAlone() throws {
        let more = try more()
        let plan = SessionPlan.practice(spot, mistakes: [saved("fork", skill: "forks")], more: more)
        XCTAssertEqual(plan?.id, more.id)
        XCTAssertNil(SessionPlan.practice(spot, mistakes: [], more: nil))
    }

    func testTheirOwnPositionsAloneAreStillAPractice() throws {
        let plan = try XCTUnwrap(SessionPlan.practice(spot, mistakes: [saved("a"), saved("b", dueIn: 1)], more: nil))
        XCTAssertEqual(plan.items.map(\.id), ["m-a", "m-b"])
    }
}
