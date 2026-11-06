import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The analysis board part way through a line: the Opera Game's finish, two moves played,
/// the best line on from there, and then a piece picked up with the squares it can reach.
/// When SNAPSHOT_DIR is set the pictures are saved there.
@MainActor
final class AnalyzeSnapshotTests: XCTestCase {

    func testTheAnalysisBoard() async throws {
        let opera = try XCTUnwrap(GrandmasterContent.shared.games.first { $0.id == "opera" })
        let masterpiece = try XCTUnwrap(HomeMasterpiece(opera))
        let start = try XCTUnwrap(PositionDraft(fen: masterpiece.frames[0]))
        let later = try XCTUnwrap(PositionDraft(fen: masterpiece.frames[2]))
        let moves = masterpiece.moves
        let engine = FakeEngine(scripted: [
            start.fen: [EngineLine(moves: moves, evaluation: .mate((moves.count + 1) / 2))],
            later.fen: [EngineLine(moves: Array(moves.dropFirst(2)), evaluation: .mate((moves.count - 1) / 2))],
        ])
        let model = AnalysisModel(draft: start, engine: engine)
        await model.run()
        XCTAssertTrue(model.play(moves[0], fromLine: true))
        XCTAssertTrue(model.play(moves[1], fromLine: true))
        for _ in 0..<150 where model.isThinking || model.lines.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.draft.fen, later.fen)
        XCTAssertEqual(model.lines.first?.moves.first, moves[2])
        // Numbered as the game was: the Opera Game's finish starts on move 13 or later.
        XCTAssertGreaterThan(TrainingChess.moveNumber(model.draft.fen), 12)

        let theme = BoardTheme.named(.gilded)
        let window = try show(NavigationStack {
            AnalysisView(model: model, theme: theme)
        }
        .background { TrainingBackdrop(theme: theme) }
        .screenScheme(theme))
        try save(window, "zz-analyze-1-line")

        // A piece picked up: its squares, and the arrows step aside.
        let piece = try XCTUnwrap(Notation.squares(of: moves[2])).from
        model.tap(piece)
        XCTAssertEqual(model.selected, piece)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        try save(window, "zz-analyze-2-picked")
        window.isHidden = true
    }

    private func show(_ view: some View, wait: TimeInterval = 2.5) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
