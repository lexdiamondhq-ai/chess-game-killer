import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The game on the Lock Screen and in the Dynamic Island: what it says after each kind of move,
/// what the app sends it from a real game, and its faces. Pictures go to SNAPSHOT_DIR as zz-live-*.png.
@MainActor
final class LiveGameTests: XCTestCase {
    private typealias LiveState = LiveGameAttributes.ContentState

    private let pulse = LiveGameAttributes(rival: "Pulse", lightHex: 0x2FA8FF, glow: "rival-pulse-glow",
                                           youAreWhite: true, clock: "5+0")

    // MARK: What it says

    func testTheHeadlineSaysWhoseMoveItIs() {
        let replied = LiveState(fen: "", lastMove: "Nf6", lastMoveByRival: true, yourMove: true, moveNumber: 2)
        XCTAssertEqual(replied.headline(rival: "Pulse"), "Your move")
        XCTAssertEqual(replied.detail(rival: "Pulse"), "Pulse played Nf6 · move 2")
        XCTAssertEqual(replied.alertTitle(rival: "Pulse"), "Pulse played Nf6")
        let played = LiveState(fen: "", lastMove: "e4", lastMoveByRival: false, yourMove: false, moveNumber: 1)
        XCTAssertEqual(played.headline(rival: "Pulse"), "Pulse is thinking")
        XCTAssertEqual(played.detail(rival: "Pulse"), "You played e4 · move 1")
        XCTAssertNil(played.alertTitle(rival: "Pulse"))
        let opening = LiveState(fen: "", yourMove: true, moveNumber: 1)
        XCTAssertEqual(opening.headline(rival: "Pulse"), "Your move")
        XCTAssertEqual(opening.detail(rival: "Pulse"), "Move 1")
        XCTAssertNil(opening.alertTitle(rival: "Pulse"))
        var over = replied
        over.result = "You won"
        over.moveNumber = 14
        XCTAssertEqual(over.headline(rival: "Pulse"), "You won")
        XCTAssertEqual(over.detail(rival: "Pulse"), "In 14 moves")
        XCTAssertNil(over.alertTitle(rival: "Pulse"))
    }

    func testTheClockReadsShort() {
        let timed = LiveState(fen: "", yourMove: true, moveNumber: 14, yourSeconds: 251)
        XCTAssertEqual(timed.shortStatus, "4:11")
        let untimed = LiveState(fen: "", yourMove: true, moveNumber: 14)
        XCTAssertEqual(untimed.shortStatus, "Your move")
        var waiting = untimed
        waiting.yourMove = false
        XCTAssertEqual(waiting.shortStatus, "Their move")
        var over = untimed
        over.result = "Draw"
        XCTAssertEqual(over.shortStatus, "Over")
        XCTAssertEqual(LiveState.clockText(42), "0:42")
        XCTAssertEqual(LiveState.clockText(725), "12:05")
        XCTAssertEqual(LiveState.clockText(-3), "0:00")
    }

    func testTheBoardMarksTheLastMove() {
        // Rank 8 first: a8 is 0, h1 is 63.
        XCTAssertEqual(LiveGameBoard.marked("e2e4"), [52, 36])
        XCTAssertEqual(LiveGameBoard.marked("g8f6"), [6, 21])
        XCTAssertEqual(LiveGameBoard.marked("e7e8q"), [12, 4])
        XCTAssertEqual(LiveGameBoard.marked(nil), [])
        XCTAssertEqual(LiveGameBoard.marked("zz"), [])
    }

    func testThePortraitIsTheRivalsOwn() {
        XCTAssertEqual(pulse.portrait, "rival-pulse")
        for rival in Rival.all {
            XCTAssertNotNil(UIImage(named: rival.portraitName), "\(rival.portraitName) is missing")
        }
        for piece in ["wK", "wQ", "wR", "wB", "wN", "wP", "bK", "bQ", "bR", "bB", "bN", "bP"] {
            XCTAssertNotNil(UIImage(named: "flat-" + piece), "flat-\(piece) is missing")
        }
    }

    // MARK: Today's Move

    func testTodaysMoveShowsUntilItIsDone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
        let puzzle = try XCTUnwrap(DailyMoves.puzzle(for: now, calendar: calendar))

        let plan = try XCTUnwrap(DailyActivityKeeper.plan(puzzle: puzzle, done: false, streak: 27, gameShowing: false,
                                                          now: now, calendar: calendar))
        XCTAssertEqual(plan.state.streak, 27)
        XCTAssertEqual(plan.puzzle.number, puzzle.number)
        XCTAssertEqual(plan.puzzle.fen, puzzle.shownFEN)
        XCTAssertEqual(plan.puzzle.side, puzzle.solverIsWhite ? "White to play" : "Black to play")
        XCTAssertEqual(plan.puzzle.resets, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))

        XCTAssertNil(DailyActivityKeeper.plan(puzzle: puzzle, done: true, streak: 27, gameShowing: false, now: now, calendar: calendar))
        XCTAssertNil(DailyActivityKeeper.plan(puzzle: puzzle, done: false, streak: 27, gameShowing: true, now: now, calendar: calendar))
        XCTAssertNil(DailyActivityKeeper.plan(puzzle: nil, done: false, streak: 0, gameShowing: false, now: now, calendar: calendar))
    }

    func testTodaysMoveTitle() {
        let mate = DailyPuzzle(number: 3, id: "x", fen: "", moves: [], rating: 1500, themes: ["mateIn2"], shownFEN: "8/8/8/8/8/8/8/8 b - - 0 1")
        let title = DailyActivityAttributes(puzzle: mate, resets: .now)
        XCTAssertEqual(title.title, "Mate in two")
        XCTAssertEqual(title.side, "Black to play")
        XCTAssertFalse(title.solverIsWhite)
        let win = DailyPuzzle(number: 4, id: "y", fen: "", moves: [], rating: 1500, themes: ["fork"], shownFEN: "8/8/8/8/8/8/8/8 w - - 0 1")
        XCTAssertEqual(DailyActivityAttributes(puzzle: win, resets: .now).title, "Find the win")
    }

    func testTheLinkOpensTheGame() throws {
        XCTAssertTrue(LiveGameLink.matches(LiveGameLink.url))
        XCTAssertTrue(LiveGameLink.matches(try XCTUnwrap(URL(string: "ChessGameKiller://game"))))
        XCTAssertFalse(LiveGameLink.matches(try XCTUnwrap(URL(string: "chessgamekiller://daily"))))
        XCTAssertFalse(LiveGameLink.matches(try XCTUnwrap(URL(string: "https://example.com/game"))))
    }

    /// A timed game against Pulse, playing Black, with Black to move: the Lock Screen gets
    /// the rival, its light, your side and your clock.
    func testTheAppSendsTheGameAsItStands() throws {
        let match = MatchController(engine: nil, sounds: nil)
        let position = try XCTUnwrap(Position(fen: HomeSample.italianFEN))
        match.start(MatchController.Setup(playerColor: .black, level: .club, timeControl: .blitz5), from: position)
        match.suspend()

        let game = LiveGameKeeper.attributes(of: match)
        XCTAssertEqual(game.rival, "Pulse")
        XCTAssertEqual(game.glow, "rival-pulse-glow")
        XCTAssertEqual(game.lightHex, MatchController.Level.club.rival.lightHex)
        XCTAssertFalse(game.youAreWhite)
        XCTAssertEqual(game.clock, TimeControl.blitz5.name)

        let state = LiveGameKeeper.state(of: match, opening: "Italian Game")
        XCTAssertTrue(state.yourMove)
        XCTAssertEqual(state.moveNumber, 5)
        XCTAssertEqual(state.opening, "Italian Game")
        XCTAssertNil(state.result)
        let seconds = try XCTUnwrap(state.yourSeconds)
        XCTAssertGreaterThan(seconds, 280)
        XCTAssertLessThanOrEqual(seconds, 300)
        XCTAssertEqual(state.headline(rival: game.rival), "Your move")
        XCTAssertEqual(state.lastMoveUCI, match.game.lastPlayed?.uci)
    }

    func testEveryRivalsGlowIsInTheAppsCatalog() {
        for rival in Rival.all {
            XCTAssertNotNil(UIImage(named: rival.glowName), "\(rival.glowName) is missing from the app's catalog")
        }
    }

    // MARK: The faces

    /// The Lock Screen card on a dark wallpaper, timed and untimed; the Dynamic Island held open;
    /// and folded around the camera.
    func testTheFaces() throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 1 5"
        let timed = LiveState(fen: fen, lastMove: "Nf6", lastMoveByRival: true, lastMoveUCI: "g8f6", yourMove: true,
                              moveNumber: 5, yourSeconds: 251, opening: "Italian Game")
        var waiting = timed
        waiting.lastMove = "d3"
        waiting.lastMoveByRival = false
        waiting.lastMoveUCI = "d2d3"
        waiting.yourMove = false
        var won = timed
        won.result = "You won"
        won.moveNumber = 31

        for (name, state) in [("timed", timed), ("waiting", waiting), ("won", won)] {
            try render(lockScreen(state), "zz-live-lock-\(name)")
        }
        try render(island(timed), "zz-live-island")
        try render(compact(timed), "zz-live-island-compact")

        let puzzle = DailyActivityAttributes(number: 32, fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", solverIsWhite: true,
                                             title: "Mate in one", side: "White to play",
                                             resets: Date.now.addingTimeInterval(6 * 3600 + 42 * 60))
        try render(card(DailyActivityLockView(puzzle: puzzle, state: .init(streak: 27))), "zz-live-daily")
    }

    private func lockScreen(_ state: LiveState) -> some View {
        card(LiveGameLockView(game: pulse, state: state))
    }

    /// A Lock Screen card on a dark wallpaper, 371 points wide as on a 393-point iPhone.
    private func card(_ face: some View) -> some View {
        face
            .background(LiveGamePalette.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(width: 371)
            .padding(14)
            .background(LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.05), Color(red: 0.2, green: 0.15, blue: 0.09)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
    }

    /// As iOS lays the regions out: the leading and trailing either side of the camera, the
    /// bottom across, on the island's black.
    private func island(_ state: LiveState) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                LiveGameIsland.Leading(game: pulse, state: state)
                Spacer(minLength: 0)
                LiveGameIsland.Trailing(game: pulse, state: state)
            }
            LiveGameIsland.Bottom(game: pulse, state: state)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 371)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .padding(12)
        .background(Color(white: 0.92))
        .environment(\.colorScheme, .dark)
    }

    /// Folded around the camera (the gap between them), with the widget's margins.
    private func compact(_ state: LiveState) -> some View {
        HStack(spacing: 0) {
            LiveGameIsland.CompactLeading(game: pulse)
            Spacer(minLength: 0)
            LiveGameIsland.CompactTrailing(game: pulse, state: state)
        }
        .padding(.horizontal, LiveGameIsland.endMargin)
        .frame(width: 250, height: 37)
        .background(Color.black, in: Capsule())
        .padding(12)
        .background(Color(white: 0.92))
        .environment(\.colorScheme, .dark)
    }

    private func render(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "\(name) did not draw")
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
