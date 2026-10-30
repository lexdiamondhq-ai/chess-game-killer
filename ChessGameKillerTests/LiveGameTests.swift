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

    func testTheHeadlineSaysWhatJustHappened() {
        let replied = LiveState(fen: "", lastMove: "Nf6", lastMoveByRival: true, yourMove: true, moveNumber: 2)
        XCTAssertEqual(replied.headline(rival: "Pulse"), "Pulse played Nf6")
        let played = LiveState(fen: "", lastMove: "e4", lastMoveByRival: false, yourMove: false, moveNumber: 1)
        XCTAssertEqual(played.headline(rival: "Pulse"), "You played e4")
        let opening = LiveState(fen: "", yourMove: true, moveNumber: 1)
        XCTAssertEqual(opening.headline(rival: "Pulse"), "Your move")
        let waiting = LiveState(fen: "", yourMove: false, moveNumber: 1)
        XCTAssertEqual(waiting.headline(rival: "Pulse"), "Pulse to move")
        var over = replied
        over.result = "You won"
        XCTAssertEqual(over.headline(rival: "Pulse"), "You won")
    }

    func testTheDetailCarriesYourClock() {
        let timed = LiveState(fen: "", lastMove: "Nf6", lastMoveByRival: true, yourMove: true, moveNumber: 14, yourSeconds: 251)
        XCTAssertEqual(timed.detail(rival: "Pulse"), "4:11 on your clock")
        XCTAssertEqual(timed.shortStatus, "4:11")
        var theirs = timed
        theirs.yourMove = false
        XCTAssertEqual(theirs.detail(rival: "Pulse"), "Pulse to move · 4:11 on your clock")
        let untimed = LiveState(fen: "", yourMove: true, moveNumber: 14)
        XCTAssertEqual(untimed.detail(rival: "Pulse"), "Your move · Move 14")
        XCTAssertEqual(untimed.shortStatus, "Your move")
        var over = untimed
        over.result = "Draw"
        XCTAssertEqual(over.detail(rival: "Pulse"), "In 14 moves")
        XCTAssertEqual(over.shortStatus, "Over")
        XCTAssertEqual(LiveState.clockText(42), "0:42")
        XCTAssertEqual(LiveState.clockText(725), "12:05")
        XCTAssertEqual(LiveState.clockText(-3), "0:00")
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
    }

    func testEveryRivalsGlowIsInBothCatalogs() {
        for rival in Rival.all {
            XCTAssertNotNil(UIImage(named: rival.glowName), "\(rival.glowName) is missing from the app's catalog")
        }
    }

    // MARK: The faces

    /// The Lock Screen card on a dark wallpaper, timed and untimed; the Dynamic Island held open;
    /// and folded around the camera.
    func testTheFaces() throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 1 5"
        let timed = LiveState(fen: fen, lastMove: "Nf6", lastMoveByRival: true, yourMove: true, moveNumber: 5,
                          yourSeconds: 251, opening: "Italian Game")
        let waiting = LiveState(fen: fen, lastMove: "d3", lastMoveByRival: false, yourMove: false, moveNumber: 5)
        var won = timed
        won.result = "You won"
        won.moveNumber = 31

        for (name, state) in [("timed", timed), ("waiting", waiting), ("won", won)] {
            try render(lockScreen(state), "zz-live-lock-\(name)")
        }
        try render(island(timed), "zz-live-island")
        try render(compact(timed), "zz-live-island-compact")
    }

    private func lockScreen(_ state: LiveState) -> some View {
        LiveGameLockView(game: pulse, state: state)
            .background(LiveGamePalette.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(width: 364)
            .padding(14)
            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.34), Color(red: 0.32, green: 0.2, blue: 0.3)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
    }

    /// As iOS lays the regions out: the leading and trailing either side of the camera, the
    /// bottom across, on the island's black.
    private func island(_ state: LiveState) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                LiveGameIsland.Leading(game: pulse)
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
