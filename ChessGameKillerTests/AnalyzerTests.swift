import ChessKit
import UIKit
import XCTest
@testable import ChessGameKiller

final class PositionDraftTests: XCTestCase {

    func testStandardPositionRoundTrips() {
        let draft = PositionDraft.standard
        XCTAssertEqual(draft.fen, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.pieces.count, 32)
    }

    func testReadsPlacementAndTurnFromFEN() {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1")
        XCTAssertEqual(draft?[.g8], .init(.king, .black))
        XCTAssertEqual(draft?[.a1], .init(.rook, .white))
        XCTAssertEqual(draft?.sideToMove, .black)
        XCTAssertNil(PositionDraft(fen: "8/8/8 w - - 0 1"))
        XCTAssertNil(PositionDraft(fen: "9/8/8/8/8/8/8/8 w - - 0 1"))
        XCTAssertNil(PositionDraft(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNX w - - 0 1"))
    }

    func testRowsFromAPictureTakenFromEitherSide() {
        let rows = ["......k.", ".....ppp", "........", "........",
                    "........", "........", "........", "R.....K."]
        let upright = PositionDraft(rows: rows, whiteSide: .bottom)
        XCTAssertEqual(upright?.placementFEN, "6k1/5ppp/8/8/8/8/8/R5K1")

        // The same picture, but taken from Black's side of the board.
        let turned = PositionDraft(rows: rows, whiteSide: .top)
        XCTAssertEqual(turned?[.b1], .init(.king, .black))
        XCTAssertEqual(turned?[.h8], .init(.rook, .white))

        XCTAssertNil(PositionDraft(rows: Array(rows.prefix(7)), whiteSide: .bottom))
        XCTAssertNil(PositionDraft(rows: rows.map { String($0.prefix(7)) }, whiteSide: .bottom))
    }

    func testRowsFromAPictureTakenFromTheSide() {
        // The starting position photographed with White on the left:
        // White's back rank is the left column, and the a-file runs along the top.
        let whiteLeft = ["RP....pr", "NP....pn", "BP....pb", "QP....pq", "KP....pk", "BP....pb", "NP....pn", "RP....pr"]
        XCTAssertEqual(PositionDraft(rows: whiteLeft, whiteSide: .left), .standard)
        // ...and with White on the right, the a-file runs along the bottom.
        let whiteRight = whiteLeft.reversed().map { String($0.reversed()) }
        XCTAssertEqual(PositionDraft(rows: whiteRight, whiteSide: .right), .standard)
    }

    func testRotateTurnsTheBoardAround() {
        var draft = PositionDraft.standard
        draft.rotate()
        XCTAssertEqual(draft[.d8], .init(.king, .white))
        XCTAssertEqual(draft[.d1], .init(.king, .black))
        draft.rotate()
        XCTAssertEqual(draft, .standard)
    }

    func testProblemsAreFound() {
        XCTAssertEqual(PositionDraft.empty.problems, [.missingKing(.white), .missingKing(.black)])
        // Side names can start with a vowel, so the message mustn't say "a Ice king".
        XCTAssertEqual(PositionDraft.Problem.missingKing(.white).message(white: "Ice", black: "Night"), "Add the Ice king.")
        XCTAssertEqual(PositionDraft.Problem.missingKing(.black).message(white: "Ice", black: "Night"), "Add the Night king.")

        var draft = PositionDraft(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")!
        XCTAssertTrue(draft.isValid)
        draft[.a1] = .init(.king, .white)
        XCTAssertEqual(draft.problems, [.extraKing(.white)])

        draft = PositionDraft(fen: "4k3/8/8/8/8/8/8/P3K3 w - - 0 1")!
        XCTAssertEqual(draft.problems, [.pawnOnEdgeRank])
    }

    func testTheWaitingSideCannotBeInCheck() {
        // The white rook gives check, so it can't be White's turn.
        var draft = PositionDraft(fen: "4k3/8/8/8/8/8/8/4RK2 w - - 0 1")!
        XCTAssertEqual(draft.problems, [.waitingSideInCheck(.black)])
        draft.sideToMove = .black
        XCTAssertTrue(draft.isValid)
    }

    func testAttacksFromEveryKindOfPiece() {
        let draft = PositionDraft(fen: "4k3/8/8/3p4/8/1N6/8/B3K2R w - - 0 1")!
        XCTAssertTrue(draft.isAttacked(.e4, by: .black), "pawn on d5 attacks e4")
        XCTAssertFalse(draft.isAttacked(.d4, by: .black), "pawns don't attack straight ahead")
        XCTAssertTrue(draft.isAttacked(.c5, by: .white), "knight on b3")
        XCTAssertTrue(draft.isAttacked(.d4, by: .white), "bishop on a1")
        XCTAssertTrue(draft.isAttacked(.e5, by: .white), "bishop on a1, further along the diagonal")
        XCTAssertFalse(draft.isAttacked(.b1, by: .white), "the rook on h1 is blocked by its own king")
        XCTAssertTrue(draft.isAttacked(.h8, by: .white), "rook on h1")
        XCTAssertTrue(draft.isAttacked(.f2, by: .white), "king on e1")
    }

    func testCastlingRightsFollowTheKingsAndRooks() {
        XCTAssertEqual(PositionDraft(fen: "r3k3/8/8/8/8/8/8/4K2R w - - 0 1")?.castlingFEN, "Kq")
        XCTAssertEqual(PositionDraft(fen: "r3k3/8/8/8/8/8/8/3K3R w - - 0 1")?.castlingFEN, "q")
        XCTAssertEqual(PositionDraft(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")?.castlingFEN, "-")
    }

    func testAGamesFENKeepsItsCastlingRightsAndEnPassantSquare() {
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        var draft = PositionDraft(fen: afterE4)!
        XCTAssertEqual(draft.fen, afterE4)
        XCTAssertEqual(draft.position?.fen, afterE4)

        // Rights the game has lost stay lost, even with king and rooks at home...
        let shuffled = PositionDraft(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1")!
        XCTAssertEqual(shuffled.castlingFEN, "KQkq")
        XCTAssertEqual(shuffled.fen, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1")
        // ...but a right the squares don't allow is never granted.
        XCTAssertEqual(PositionDraft(fen: "r3k3/8/8/8/8/8/8/4K2R w KQkq - 0 1")?.fen, "r3k3/8/8/8/8/8/8/4K2R w Kq - 0 1")
        // Odd en passant fields are dropped rather than passed on.
        XCTAssertEqual(PositionDraft(fen: "4k3/8/8/8/8/8/8/4K3 w - e4 0 1")?.fen, "4k3/8/8/8/8/8/8/4K3 w - - 0 1")

        // A FEN that says nothing new compares equal to the same position set up by hand.
        XCTAssertEqual(PositionDraft(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), .standard)

        // Changing the turn or the pieces goes back to what the squares say.
        draft.sideToMove = .white
        XCTAssertEqual(draft.fen, "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1")
        var edited = shuffled
        edited[.e4] = .init(.pawn, .white)
        XCTAssertEqual(edited.fen, "rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        var turned = shuffled
        turned.rotate()
        XCTAssertNil(turned.castling)
    }

    func testFinishedPositions() {
        let mated = PositionDraft(fen: "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1")!
        XCTAssertTrue(mated.isFinished)
        XCTAssertTrue(mated.isInCheck(.black))
        let stalemate = PositionDraft(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        XCTAssertTrue(stalemate.isFinished)
        XCTAssertFalse(stalemate.isInCheck(.black))
        XCTAssertFalse(PositionDraft.standard.isFinished)
    }
}

final class NotationLineTests: XCTestCase {

    func testEngineLineInStandardNotation() {
        let start = Position.standard.fen
        let line = Notation.sanLine(of: ["e2e4", "e7e5", "g1f3", "b8c6"], fen: start)
        XCTAssertEqual(line, ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertEqual(Notation.numbered(line, blackFirst: false), "1. e4 e5 2. Nf3 Nc6")
    }

    func testLineStartingWithBlack() {
        XCTAssertEqual(Notation.numbered(["e5", "Nf3", "Nc6"], blackFirst: true), "1... e5 2. Nf3 Nc6")
    }

    func testLineStopsAtAMoveThatDoesNotFit() {
        let line = Notation.sanLine(of: ["e2e4", "e2e4"], fen: Position.standard.fen)
        XCTAssertEqual(line, ["e4"])
    }
}

final class BoardReaderTests: XCTestCase {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testReadsTheServersAnswer() throws {
        let reading = try CloudBoardReader.reading(from: json("""
        {"found": true,
         "rows": ["......k.", ".....ppp", "........", "........", "........", "........", "........", "R.....K."],
         "white_side": "bottom", "side_to_move": "black", "confidence": "high"}
        """))
        XCTAssertEqual(reading.draft.placementFEN, "6k1/5ppp/8/8/8/8/8/R5K1")
        XCTAssertEqual(reading.draft.sideToMove, .black)
        XCTAssertTrue(reading.sureOfTurn)
        XCTAssertEqual(reading.confidence, .high)
    }

    func testUnknownTurnDefaultsToWhite() throws {
        let reading = try CloudBoardReader.reading(from: json("""
        {"found": true, "rows": ["....k...", "........", "........", "........", "........", "........", "........", "....K..."],
         "white_side": "top", "side_to_move": null}
        """))
        XCTAssertEqual(reading.draft.sideToMove, .white)
        XCTAssertFalse(reading.sureOfTurn)
        XCTAssertEqual(reading.whiteSide, .top)
        XCTAssertEqual(reading.draft[.d1], .init(.king, .black))
    }

    func testScanCountStartsAgainEachMonth() {
        let defaults = UserDefaults(suiteName: "ScanCountTests")!
        defaults.removePersistentDomain(forName: "ScanCountTests")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let november = Date(timeIntervalSince1970: 1_793_836_800) // 2026-11-05
        let december = Date(timeIntervalSince1970: 1_796_428_800) // 2026-12-05
        XCTAssertEqual(ScanCount.next(defaults: defaults, now: november, calendar: calendar), 1)
        XCTAssertEqual(ScanCount.next(defaults: defaults, now: november, calendar: calendar), 2)
        XCTAssertEqual(ScanCount.next(defaults: defaults, now: december, calendar: calendar), 1)
    }

    func testOnlyNetworkTroubleBlamesTheConnection() {
        XCTAssertEqual(CloudBoardReader.readerError(for: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(CloudBoardReader.readerError(for: URLError(.timedOut)), .offline)
        XCTAssertEqual(CloudBoardReader.readerError(for: URLError(.badServerResponse)), .failed)
        XCTAssertEqual(CloudBoardReader.readerError(for: URLError(.cancelled)), .failed)
        XCTAssertEqual(CloudBoardReader.readerError(for: BoardReaderError.noBoard), .failed)
        XCTAssertTrue(BoardReaderError.offline.errorDescription?.contains("connection") == true)
        XCTAssertFalse(BoardReaderError.failed.errorDescription?.contains("connection") == true)
    }

    func testNoBoardInThePicture() {
        XCTAssertThrowsError(try CloudBoardReader.reading(from: json(#"{"found": false}"#))) { error in
            XCTAssertEqual(error as? BoardReaderError, .noBoard)
        }
        XCTAssertThrowsError(try CloudBoardReader.reading(from: json("not json"))) { error in
            XCTAssertEqual(error as? BoardReaderError, .failed)
        }
    }

    func testPhotosAreShrunkBeforeSending() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let data = try XCTUnwrap(big.preparedForReading())
        let shrunk = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(shrunk.size.width * shrunk.scale, shrunk.size.height * shrunk.scale), 1568, accuracy: 1)
    }
}

/// A reader with a canned answer.
struct FakeBoardReader: BoardReader {
    var result: Result<BoardReading, BoardReaderError>

    func read(_ image: UIImage) async throws -> BoardReading {
        try result.get()
    }
}

/// A reader that takes a while to answer, like the real one.
struct SlowFakeBoardReader: BoardReader {
    var reading: BoardReading
    var delay: Duration = .milliseconds(200)

    func read(_ image: UIImage) async throws -> BoardReading {
        try await Task.sleep(for: delay)
        return reading
    }
}

@MainActor
final class ScanSessionTests: XCTestCase {

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<250 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    /// A photo goes from being read straight to its analysis, with no stop in the editor
    /// (Alex, 2026-11-06: "Skip the board read and adding pieces and go straight to analyze").
    func testAPhotoGoesStraightToItsAnalysis() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let reader = FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .high)
        ))
        let session = ScanSession(reader: reader)
        session.read(UIImage())
        XCTAssertEqual(session.path, [.reading])
        XCTAssertTrue(session.isReading)

        await waitUntil { !session.isReading }
        XCTAssertEqual(session.path, [.analysis])
        XCTAssertEqual(session.analyzed, draft)
        XCTAssertNotNil(session.photo, "kept, to compare with")
        XCTAssertFalse(session.readingFailed)
        // The analysis says what to check: here, whose turn it is.
        XCTAssertEqual(session.photoDoubts, "I guessed it's White's move.")
    }

    func testASureReadHasNothingToCheck() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1")!
        let session = ScanSession(reader: FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high)
        )))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        XCTAssertEqual(session.path, [.analysis])
        XCTAssertNil(session.photoDoubts)

        let blurry = ScanSession(reader: FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .low)
        )))
        blurry.read(UIImage())
        await waitUntil { !blurry.isReading }
        XCTAssertEqual(blurry.photoDoubts, "The picture was hard to read, so check the pieces. I guessed it's Black's move.")
    }

    /// From the photo's analysis, Edit pieces opens the editor on the board, and its Analyze
    /// comes back to a new analysis of the fixed position.
    func testFixingAPieceComesBackToTheAnalysis() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let session = ScanSession(reader: FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .high)
        )))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        let firstRun = session.analysisRun

        session.editPieces(session.analyzed)
        XCTAssertEqual(session.path, [.analysis, .editor])
        XCTAssertEqual(session.draft, draft)
        XCTAssertTrue(session.readingNote?.contains("tap Analyze") == true)

        // The reader missed a pawn.
        session.draft[.h2] = .init(.pawn, .white)
        session.analyzeDraft()
        XCTAssertEqual(session.path, [.analysis], "back on the analysis, not a second one on top")
        XCTAssertEqual(session.analyzed[.h2], .init(.pawn, .white))
        XCTAssertGreaterThan(session.analysisRun, firstRun, "the analysis starts over")
        XCTAssertNil(session.photoDoubts, "the pieces have been looked over")

        // Backing out of the editor leaves the analysis as it was.
        session.editPieces(session.analyzed)
        let run = session.analysisRun
        session.draft[.a1] = nil
        session.path.removeLast()
        XCTAssertEqual(session.analysisRun, run)
        XCTAssertEqual(session.analyzed[.a1], .init(.rook, .white))
    }

    /// Whose move it is can be switched on the analysis itself (Alex, 2026-11-07: "I can't switch
    /// from white to black"): the same pieces, the other side to move, a fresh analysis, and the
    /// reader's guess at the turn no longer flagged. A doubt about the pieces stays.
    func testTheTurnSwitchesOnTheAnalysis() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let session = ScanSession(reader: FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .low)
        )))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        let firstRun = session.analysisRun

        session.switchTurn(of: session.analyzed)
        XCTAssertEqual(session.path, [.analysis], "still the one analysis")
        XCTAssertEqual(session.analyzed.sideToMove, .black)
        XCTAssertEqual(session.analyzed.fen.split(separator: " ").first, draft.fen.split(separator: " ").first)
        XCTAssertGreaterThan(session.analysisRun, firstRun, "the analysis starts over")
        XCTAssertEqual(session.photoDoubts, "The picture was hard to read, so check the pieces.")
        XCTAssertEqual(session.draft.sideToMove, .black, "Edit pieces opens on the switched turn")

        session.switchTurn(of: session.analyzed)
        XCTAssertEqual(session.analyzed.sideToMove, .white, "and back")
    }

    /// Pieces read that can't be analyzed (here, no black king) open the editor instead,
    /// where what's wrong shows under the board.
    func testPiecesThatCantBeAnalyzedOpenTheEditor() async {
        let draft = PositionDraft(fen: "8/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        XCTAssertFalse(draft.isValid)
        let session = ScanSession(reader: FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high)
        )))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        XCTAssertEqual(session.path, [.editor])
        XCTAssertEqual(session.draft, draft)
        XCTAssertTrue(session.readingNote?.contains("marked below") == true)

        // Fixed, the editor's Analyze opens the analysis on top.
        session.draft[.g8] = .init(.king, .black)
        session.analyzeDraft()
        XCTAssertEqual(session.path, [.editor, .analysis])
        XCTAssertEqual(session.analyzed[.g8], .init(.king, .black))
    }

    func testAFailedReadLeavesAnEmptyBoardToFillIn() async {
        let session = ScanSession(reader: FakeBoardReader(result: .failure(.noBoard)))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        XCTAssertEqual(session.path, [.editor])
        XCTAssertTrue(session.readingFailed)
        XCTAssertTrue(session.draft.isEmpty)
        XCTAssertEqual(session.readingNote, BoardReaderError.noBoard.errorDescription)
    }

    func testStoppingASlowReadOpensTheEditor() {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let session = ScanSession(reader: SlowFakeBoardReader(
            reading: BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high)
        ))
        session.read(UIImage())
        session.stopReading()
        XCTAssertEqual(session.path, [.editor])
        XCTAssertFalse(session.isReading)
        XCTAssertNotNil(session.photo, "still there to copy from")
        XCTAssertTrue(session.readingNote?.contains("Stopped") == true)
    }

    /// Backing out to the start while the photo is read drops the read: its analysis doesn't
    /// open later out of nowhere.
    func testBackingOutWhileReadingDropsTheRead() async throws {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let session = ScanSession(reader: SlowFakeBoardReader(
            reading: BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high),
            delay: .milliseconds(100)
        ))
        session.read(UIImage())
        session.path = []
        session.leaveReading()
        XCTAssertFalse(session.isReading)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(session.path, [])
        XCTAssertNotEqual(session.analyzed, draft)
    }

    /// Closing Analyze and opening it again finds the same board, with the moves played on it.
    func testTheAnalysisBoardOutlivesTheSheet() {
        let session = ScanSession(reader: UnavailableBoardReader(), engine: FakeEngine())
        session.analyze(fen: PositionDraft.standard.fen)
        let board = session.analysis
        XCTAssertNotNil(board)
        board?.play("e2e4", fromLine: false)
        XCTAssertTrue(session.analysis === board)
        XCTAssertEqual(session.path, [.analysis])
        XCTAssertEqual(session.analysis?.cursor, 1)
    }

    /// Analyze closed while a photo is read: next time it opens on its first screen.
    func testClosingWhileReadingOpensOnTheStartNextTime() {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let session = ScanSession(reader: SlowFakeBoardReader(
            reading: BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high)
        ))
        session.read(UIImage())
        session.leaveReading()
        XCTAssertEqual(session.path, [])
    }

    func testANewerReadIsNotSpoiledByTheOneItReplaced() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let reader = SlowFakeBoardReader(reading: BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: true, confidence: .high))
        let session = ScanSession(reader: reader)
        session.read(UIImage())
        // Back out and pick another picture before the first one has been read.
        session.read(UIImage())
        XCTAssertTrue(session.isReading)

        await waitUntil { !session.isReading }
        XCTAssertFalse(session.readingFailed)
        XCTAssertEqual(session.draft, draft)
        XCTAssertEqual(session.analyzed, draft)
        XCTAssertEqual(session.path, [.analysis])
    }

    func testAPhotoThatWontOpenExplainsItself() {
        let session = ScanSession(reader: UnavailableBoardReader())
        session.failToLoadPhoto()
        XCTAssertEqual(session.path, [.editor])
        XCTAssertFalse(session.isReading)
        XCTAssertTrue(session.readingFailed)
        XCTAssertTrue(session.draft.isEmpty)
        XCTAssertTrue(session.readingNote?.contains("open that photo") == true)
    }

    func testAnalyzingTheCurrentGameSkipsTheEditor() {
        let session = ScanSession(reader: UnavailableBoardReader())
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        session.analyze(fen: fen)
        XCTAssertEqual(session.path, [.analysis])
        XCTAssertEqual(session.analyzed.sideToMove, .black)
        XCTAssertEqual(session.analyzed[.e4], .init(.pawn, .white))
        // The game's castling rights and en passant square go to Stockfish as they are.
        XCTAssertEqual(session.analyzed.fen, fen)
        XCTAssertNil(session.photo)
    }

    func testABoardSetUpByHandIsAnalyzedFromTheEditor() {
        let session = ScanSession(reader: UnavailableBoardReader())
        session.setUpByHand()
        XCTAssertEqual(session.path, [.editor])
        session.draft[.e2] = nil
        session.draft[.e4] = .init(.pawn, .white)
        session.analyzeDraft()
        XCTAssertEqual(session.path, [.editor, .analysis])
        XCTAssertEqual(session.analyzed[.e4], .init(.pawn, .white))
    }
}

@MainActor
final class AnalysisModelTests: XCTestCase {

    func testFindsTwoBestMovesWithArrows() async {
        let model = AnalysisModel(draft: .standard, engine: FakeEngine())
        await model.run()
        XCTAssertEqual(model.hints.count, 2)
        XCTAssertEqual(model.lines.count, 2)
        XCTAssertEqual(model.depth, 18)
        XCTAssertFalse(model.isThinking)
        XCTAssertFalse(model.failed)
    }

    /// The arrows show from the search's first useful depth, while it is still looking deeper.
    func testTheBestMovesShowBeforeTheSearchEnds() async {
        let engine = DeepeningEngine()
        let model = AnalysisModel(draft: .standard, engine: engine)
        let running = Task { await model.run() }
        for _ in 0..<100 where model.hints.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isThinking, "still looking deeper")
        XCTAssertEqual(model.hints.first?.uci, "d2d4")
        XCTAssertEqual(model.depth, 9)
        await running.value
        XCTAssertFalse(model.isThinking)
        XCTAssertEqual(model.hints.first?.uci, "e2e4")
        XCTAssertEqual(model.depth, AnalysisModel.fullDepth)
    }

    /// A search cut off by closing Analyze picks up again when it opens.
    func testASearchCutOffCarriesOnWhenOpenedAgain() async {
        let model = AnalysisModel(draft: .standard, engine: DeepeningEngine())
        let first = Task { await model.run() }
        for _ in 0..<100 where model.hints.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        first.cancel()
        await first.value
        XCTAssertFalse(model.isThinking)
        XCTAssertLessThan(model.depth, AnalysisModel.fullDepth)
        await model.run()
        XCTAssertEqual(model.depth, AnalysisModel.fullDepth)
        XCTAssertEqual(model.hints.first?.uci, "e2e4")
    }

    func testScoresAreShownFromWhitesSide() async {
        let draft = PositionDraft(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")!
        let engine = FakeEngine(scripted: [
            draft.fen: [EngineLine(moves: ["e7e5"], evaluation: .centipawns(-40))],
        ])
        let model = AnalysisModel(draft: draft, engine: engine)
        await model.run()
        XCTAssertEqual(model.evaluationForWhite, .centipawns(40))
        XCTAssertEqual(model.verdict(white: "Gold", black: "Violet"), "Gold is slightly better")
        XCTAssertEqual(model.readable(model.lines[0]), "1... e5")
    }

    func testMateIsNotAnalyzed() async {
        let mated = PositionDraft(fen: "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1")!
        let model = AnalysisModel(draft: mated, engine: FakeEngine())
        XCTAssertEqual(model.ending, "Checkmate")
        await model.run()
        XCTAssertTrue(model.lines.isEmpty)
    }

    func testAnInvalidPositionFailsInsteadOfThinkingForever() async {
        let pawnOnEdge = PositionDraft(fen: "4k3/8/8/8/8/8/8/P3K3 w - - 0 1")!
        let model = AnalysisModel(draft: pawnOnEdge, engine: FakeEngine())
        XCTAssertNil(model.ending)
        await model.run()
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.isThinking)
        XCTAssertTrue(model.lines.isEmpty)

        let noEngine = AnalysisModel(draft: .standard, engine: nil)
        await noEngine.run()
        XCTAssertTrue(noEngine.failed)
    }

    func testVerdicts() {
        let model = AnalysisModel(draft: .standard, engine: nil)
        XCTAssertEqual(model.verdict(white: "White", black: "Black"), "")
    }

    /// Waits for the analysis the board's last change started.
    private func settle(_ model: AnalysisModel) async {
        for _ in 0..<100 where model.isThinking || model.lines.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testAPieceCanBeMovedAndTheAnalysisFollows() async {
        let engine = FakeEngine()
        let model = AnalysisModel(draft: .standard, engine: engine)
        await model.run()
        model.tap(.e2)
        XCTAssertEqual(model.selected, .e2)
        XCTAssertEqual(model.targets, [.e3, .e4])
        model.tap(.e4)
        XCTAssertNil(model.selected)
        XCTAssertEqual(model.cursor, 1)
        XCTAssertEqual(model.draft.sideToMove, .black)
        XCTAssertEqual(model.draft[.e4], .init(.pawn, .white))
        XCTAssertEqual(model.movesMade.map { $0.label }, ["1. e4"])
        await settle(model)
        // Black's best answers now, from the new position.
        let analyzed = await engine.analyzed
        XCTAssertEqual(analyzed.last, model.draft.fen)
        XCTAssertFalse(model.hints.isEmpty)
        // A black piece can't be picked up on White's turn, and a white one can't now.
        model.tap(.d2)
        XCTAssertNil(model.selected)
    }

    func testStepsBackAndForwardThroughTheMoves() async {
        let model = AnalysisModel(draft: .standard, engine: FakeEngine())
        await model.run()
        XCTAssertTrue(model.play("e2e4", fromLine: false))
        XCTAssertTrue(model.play("e7e5", fromLine: false))
        XCTAssertTrue(model.play("g1f3", fromLine: false))
        XCTAssertEqual(model.movesMade.map { $0.label }, ["1. e4", "e5", "2. Nf3"])
        model.back()
        model.back()
        XCTAssertEqual(model.cursor, 1)
        XCTAssertEqual(model.draft.sideToMove, .black)
        // The moves ahead stay until a different one is played.
        XCTAssertEqual(model.steps.count, 3)
        model.forward()
        XCTAssertEqual(model.cursor, 2)
        XCTAssertNotNil(model.draft[.e5])
        model.jump(to: 2)
        XCTAssertEqual(model.cursor, 3)
        model.rewind()
        XCTAssertEqual(model.cursor, 0)
        XCTAssertEqual(model.draft.fen, PositionDraft.standard.fen)
        XCTAssertFalse(model.canGoBack)
        // Another first move replaces the old line.
        XCTAssertTrue(model.play("d2d4", fromLine: false))
        XCTAssertEqual(model.movesMade.map { $0.label }, ["1. d4"])
        XCTAssertFalse(model.play("d4d6", fromLine: false))
    }

    func testPlaysTheBestLineOutMoveByMove() async {
        let start = PositionDraft.standard
        let engine = FakeEngine(scripted: [
            start.fen: [EngineLine(moves: ["e2e4", "e7e5", "g1f3", "b8c6"], evaluation: .centipawns(30))],
        ])
        let model = AnalysisModel(draft: start, engine: engine, lineBeat: .milliseconds(10))
        await model.run()
        XCTAssertTrue(model.canPlayLine)
        model.playLine()
        XCTAssertTrue(model.isPlayingLine)
        for _ in 0..<100 where model.isPlayingLine {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isPlayingLine)
        XCTAssertEqual(model.movesMade.map { $0.label }, ["1. e4", "e5", "2. Nf3", "Nc6"])
        XCTAssertEqual(model.cursor, 4)
        XCTAssertTrue(model.steps.allSatisfy(\.fromLine))
        // Stepping back past the line keeps it to step through again.
        model.rewind()
        model.forward()
        XCTAssertEqual(model.cursor, 1)
        XCTAssertEqual(model.steps.count, 4)
    }

    func testForwardPlaysTheBestMoveWhenNothingIsAhead() async {
        let start = PositionDraft.standard
        let engine = FakeEngine(scripted: [
            start.fen: [EngineLine(moves: ["d2d4", "d7d5"], evaluation: .centipawns(20))],
        ])
        let model = AnalysisModel(draft: start, engine: engine)
        await model.run()
        XCTAssertTrue(model.canGoForward)
        model.forward()
        XCTAssertEqual(model.movesMade.map { $0.label }, ["1. d4"])
    }

    /// A pawn the person moves to the last rank asks what it becomes, and becomes that.
    func testAPromotionAsksWhichPiece() {
        let draft = PositionDraft(fen: "8/8/8/8/8/8/4p3/K6k b - - 0 1")!
        let model = AnalysisModel(draft: draft, engine: nil)
        model.tap(.e2)
        model.tap(.e1)
        XCTAssertEqual(model.promoting?.to, .e1)
        XCTAssertEqual(model.promoting?.color, .black)
        XCTAssertTrue(model.playedSteps.isEmpty, "nothing is played until a piece is chosen")
        XCTAssertEqual(model.draft[.e2], .init(.pawn, .black))

        model.cancelPromotion()
        XCTAssertNil(model.promoting)
        XCTAssertEqual(model.draft[.e2], .init(.pawn, .black), "a change of mind leaves the pawn")

        model.tap(.e2)
        model.tap(.e1)
        model.promote(to: .knight)
        XCTAssertNil(model.promoting)
        XCTAssertEqual(model.playedSteps.map(\.uci), ["e2e1n"])
        XCTAssertEqual(model.draft[.e1], .init(.knight, .black))
    }

    func testLinesAreNumberedFromThePositionOnTheBoard() async {
        let draft = PositionDraft(fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")!
        let engine = FakeEngine(scripted: [
            draft.fen: [EngineLine(moves: ["f1b5", "a7a6"], evaluation: .centipawns(30))],
        ])
        let model = AnalysisModel(draft: draft, engine: engine)
        await model.run()
        XCTAssertEqual(model.readable(model.lines[0]), "3. Bb5 a6")
        // The moves made are numbered from there too.
        XCTAssertTrue(model.play("f1b5", fromLine: false))
        XCTAssertEqual(model.movesMade.map { $0.label }, ["3. Bb5"])
        XCTAssertEqual(TrainingChess.moveNumber(model.draft.fen), 3)
    }

    func testAGamesFENKeepsItsMoveNumberUntilThePiecesAreEdited() {
        let middle = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
        var draft = PositionDraft(fen: middle)!
        XCTAssertEqual(draft.fen, middle)
        draft[.a2] = nil
        XCTAssertTrue(draft.fen.hasSuffix(" - 0 1"))
        var turned = PositionDraft(fen: middle)!
        turned.sideToMove = .black
        XCTAssertTrue(turned.fen.hasSuffix(" - 0 1"))
    }
}

@MainActor
final class PlayFromPositionTests: XCTestCase {

    func testAGameCanStartFromASetUpPosition() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping(from: draft.position!)
        XCTAssertEqual(match.game.fen, draft.position!.fen)
        match.tap(.a1)
        match.tap(.a8)
        XCTAssertEqual(match.game.winner, .white)
    }
}

/// Reports a shallow depth that is too noisy to show, then one worth showing, then answers
/// deeper a little later with another move.
private final class DeepeningEngine: ChessEngine, @unchecked Sendable {
    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        [EngineLine(moves: ["e2e4"], evaluation: .centipawns(30))]
    }

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?,
                 progress: @escaping @Sendable ([EngineLine], Int) -> Void) async -> [EngineLine] {
        progress([EngineLine(moves: ["a2a3"], evaluation: .centipawns(0))], 3)
        progress([EngineLine(moves: ["d2d4"], evaluation: .centipawns(25))], 9)
        try? await Task.sleep(for: .milliseconds(400))
        return await analyze(fen: fen, depth: depth, lines: lines, maxTimeMs: maxTimeMs)
    }

    func chooseMove(fen: String, skill: Int, depth: Int?, thinkTimeMs: Int) async -> String? { nil }
}
