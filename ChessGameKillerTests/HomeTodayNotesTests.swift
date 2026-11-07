import XCTest
@testable import ChessGameKiller

/// Leo's note and the finest move of the week on Today.
final class HomeTodayNotesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    // MARK: Leo's note

    func testTheGreetingFollowsTheClockAndTheName() {
        XCTAssertEqual(HomeLeoNote.greeting(name: "Alex", hour: 8), "Good morning, Alex")
        XCTAssertEqual(HomeLeoNote.greeting(name: "", hour: 13), "Good afternoon")
        XCTAssertEqual(HomeLeoNote.greeting(name: "  ", hour: 21), "Good evening")
    }

    func testWithNoGamesLeoGivesTheDaysWisdomAndItChangesTomorrow() {
        let today = HomeLeoNote.make(report: nil, name: "Alex", now: date("2026-11-07T09:00:00Z"), calendar: calendar)
        let tomorrow = HomeLeoNote.make(report: nil, name: "Alex", now: date("2026-11-08T09:00:00Z"), calendar: calendar)
        XCTAssertTrue(HomeLeoNote.daily.contains(today.line))
        XCTAssertNil(today.evidence)
        XCTAssertNotEqual(today.line, tomorrow.line)
        XCTAssertEqual(today.greeting, "Good morning, Alex")
    }

    func testTheNoteAimsAtTheLeakAndKeepsTheCountsInWriting() {
        let leak = CoachReport.Leak(area: .safety, headline: "Loose pieces",
                                    detail: "You left a piece hanging twice in your last 6 games. Before you let go of a piece, ask: can they take it for free?",
                                    skill: "safety", action: "Practice safe moves")
        let report = CoachReport(gamesRead: 6, scores: [], leak: leak)
        let note = HomeLeoNote.make(report: report, name: "", now: date("2026-11-07T18:00:00Z"), calendar: calendar)
        XCTAssertTrue(HomeLeoNote.loosePieces.contains(note.line))
        XCTAssertEqual(note.evidence, "You left a piece hanging twice in your last 6 games.")
        XCTAssertEqual(note.greeting, "Good evening")
    }

    func testEveryLeakHasLinesAndEveryLineCanBeRecorded() {
        for area in CoachReport.Area.allCases {
            let leak = CoachReport.Leak(area: area, headline: "", detail: "", skill: nil, action: "")
            XCTAssertFalse(HomeLeoNote.advice(for: leak).isEmpty)
        }
        XCTAssertEqual(HomeLeoNote.advice(for: .init(area: .safety, headline: "Missed threats", detail: "", skill: nil, action: "")),
                       HomeLeoNote.threats)
        // Fixed lines only: no names, no counts, so each can be recorded once in Leo's voice.
        XCTAssertEqual(Set(HomeLeoNote.allLines).count, HomeLeoNote.allLines.count)
        for line in HomeLeoNote.allLines {
            XCTAssertNil(line.rangeOfCharacter(from: .decimalDigits), line)
            XCTAssertFalse(line.contains("Alex"), line)
        }
    }

    // MARK: The finest move

    func testTheFinestMoveIsTheWeeksBiggestGain() {
        let now = date("2026-11-07T18:00:00Z")
        let game = RewindSample.game(date: date("2026-11-05T12:00:00Z"))
        let finest = HomeFinestMove.pick(games: [game], now: now, calendar: calendar)
        // Ng5 gained the most of the strong moves in the sample game.
        XCTAssertEqual(finest?.gameID, game.id)
        XCTAssertEqual(finest?.uci, "f3g5")
        XCTAssertEqual(finest?.move, "4. Ng5!")
        XCTAssertEqual(finest?.detail, "Against Pulse, Thursday. Stockfish's top choice.")
        XCTAssertEqual(finest?.flipped, false)
        XCTAssertEqual(finest?.squares?.from.file, 5)
        XCTAssertEqual(finest?.squares?.from.rank, 2)
        XCTAssertEqual(finest?.squares?.to.file, 6)
        XCTAssertEqual(finest?.squares?.to.rank, 4)
    }

    func testOldGamesAndFriendGamesDontCount() {
        let now = date("2026-11-07T18:00:00Z")
        let old = RewindSample.game(date: date("2026-10-25T12:00:00Z"))
        XCTAssertNil(HomeFinestMove.pick(games: [old], now: now, calendar: calendar))
        let recent = RewindSample.game(date: date("2026-11-06T12:00:00Z"))
        let friend = SavedGame(id: UUID(), date: recent.date, opponent: "Friend", level: nil, playerIsWhite: true,
                               result: recent.result, accuracy: nil, positions: recent.positions, moves: recent.moves,
                               moments: recent.moments)
        XCTAssertNil(HomeFinestMove.pick(games: [friend], now: now, calendar: calendar))
    }

    func testWhenReadsLikeSpeech() {
        let now = date("2026-11-07T18:00:00Z")
        XCTAssertEqual(HomeFinestMove.when(date("2026-11-07T08:00:00Z"), now: now, calendar: calendar), "today")
        XCTAssertEqual(HomeFinestMove.when(date("2026-11-06T08:00:00Z"), now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(HomeFinestMove.when(date("2026-11-03T08:00:00Z"), now: now, calendar: calendar), "Tuesday")
    }
}
