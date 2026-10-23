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

    func testReadingAPhotoFillsTheEditor() async {
        let draft = PositionDraft(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        let reader = FakeBoardReader(result: .success(
            BoardReading(draft: draft, whiteSide: .bottom, sureOfTurn: false, confidence: .high)
        ))
        let session = ScanSession(reader: reader)
        session.read(UIImage())
        XCTAssertEqual(session.path, [.editor])
        XCTAssertTrue(session.isReading)

        await waitUntil { !session.isReading }
        XCTAssertEqual(session.draft, draft)
        XCTAssertFalse(session.readingFailed)
        XCTAssertTrue(session.readingNote?.contains("whose turn") == true)
    }

    func testAFailedReadLeavesAnEmptyBoardToFillIn() async {
        let session = ScanSession(reader: FakeBoardReader(result: .failure(.noBoard)))
        session.read(UIImage())
        await waitUntil { !session.isReading }
        XCTAssertTrue(session.readingFailed)
        XCTAssertTrue(session.draft.isEmpty)
        XCTAssertEqual(session.readingNote, BoardReaderError.noBoard.errorDescription)
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
        XCTAssertEqual(session.draft.sideToMove, .black)
        XCTAssertEqual(session.draft[.e4], .init(.pawn, .white))
        // The game's castling rights and en passant square go to Stockfish as they are.
        XCTAssertEqual(session.draft.fen, fen)
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
