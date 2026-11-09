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

    /// A photo straight after it's read: its analysis, with the photo, what to check and Edit
    /// pieces over the board. Before that, the photo while the reader checks every square.
    func testAPhotosAnalysis() async throws {
        let theme = BoardTheme.named(.gilded)
        let draft = try XCTUnwrap(PositionDraft(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"))
        let photo = Self.boardPhoto()

        let session = ScanSession(reader: SlowFakeBoardReader(
            reading: BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .high),
            delay: .seconds(30)
        ))
        session.read(photo)
        let reading = try show(NavigationStack {
            PhotoReadingView(session: session, theme: theme)
        }
        .background { TrainingBackdrop(theme: theme) }
        .screenScheme(theme))
        try save(reading, "zz-analyze-0-reading")
        reading.isHidden = true
        session.leaveReading()

        let engine = FakeEngine(scripted: [
            draft.fen: [
                EngineLine(moves: ["h5f7"], evaluation: .mate(1)),
                EngineLine(moves: ["c4f7", "e8e7"], evaluation: .centipawns(180)),
            ],
        ])
        let model = AnalysisModel(draft: draft, engine: engine)
        await model.run()
        XCTAssertEqual(model.lines.first?.firstMove, "h5f7")
        let window = try show(NavigationStack {
            AnalysisView(model: model, theme: theme, photo: photo, photoDoubts: "I guessed it's White's move.",
                         onEditPieces: { _ in })
        }
        .background { TrainingBackdrop(theme: theme) }
        .screenScheme(theme))
        try save(window, "zz-analyze-3-photo")
        window.isHidden = true

        // Edit pieces: the same 3D board and pieces as the analysis, with the palette under it.
        session.draft = draft
        let editor = try show(NavigationStack {
            BoardEditorView(session: session, theme: theme)
        }
        .background { TrainingBackdrop(theme: theme) }
        .screenScheme(theme))
        try save(editor, "zz-analyze-4-editor")
        editor.isHidden = true
    }

    /// A stand-in for a photo of a board: light and dark squares.
    private static func boardPhoto() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 480), format: format).image { context in
            for index in 0..<64 {
                let light = (index / 8 + index % 8) % 2 == 0
                UIColor(white: light ? 0.86 : 0.42, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat(index % 8) * 60, y: CGFloat(index / 8) * 60, width: 60, height: 60))
            }
        }
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
