import ChessKit
import XCTest
@testable import ChessGameKiller

/// The Heirloom Set: what each piece's record leaves on the piece.
final class HeirloomTests: XCTestCase {

    private func record(escapes: Int = 0, revenge: Set<Int> = [], promotions: Int = 0,
                        captures: Int = 0, games: Int = 0) -> PieceRecord {
        var record = PieceRecord()
        record.escapes = escapes
        record.revenge = revenge
        record.promotions = promotions
        record.captures = captures
        record.games = games
        return record
    }

    func testNothingShowsOnAFreshPiece() {
        XCTAssertTrue(Heirloom(record: PieceRecord(), slot: .queen).isEmpty)
    }

    func testSeamsCountComebacks() {
        let heirloom = Heirloom(record: record(escapes: 1, revenge: [2, 4]), slot: .queen)
        XCTAssertEqual(heirloom.seams, 3)
    }

    func testSeamsAreCappedAtThree() {
        let heirloom = Heirloom(record: record(escapes: 3, revenge: [0, 1, 2, 3]), slot: .queen)
        XCTAssertEqual(heirloom.seams, Heirloom.maxSeams)
    }

    func testOnlyAPromotedPawnWearsTheCollar() {
        XCTAssertTrue(Heirloom(record: record(promotions: 1), slot: .aPawn).collar)
        // A back-rank piece never promotes, so no collar even with the count set.
        XCTAssertFalse(Heirloom(record: record(promotions: 1), slot: .queensRook).collar)
        XCTAssertFalse(Heirloom(record: record(promotions: 0), slot: .aPawn).collar)
    }

    func testNotchesAreOnePerFiveCaptures() {
        XCTAssertEqual(Heirloom(record: record(captures: 4), slot: .queen).notches, 0)
        XCTAssertEqual(Heirloom(record: record(captures: 12), slot: .queen).notches, 2)
        XCTAssertEqual(Heirloom(record: record(captures: 100), slot: .queen).notches, Heirloom.maxNotches)
    }

    func testPatinaDeepensOverTheFirstGames() {
        XCTAssertEqual(Heirloom(record: record(games: 0), slot: .queen).patina, 0, accuracy: 0.001)
        XCTAssertEqual(Heirloom(record: record(games: 60), slot: .queen).patina, 0.5, accuracy: 0.01)
        XCTAssertEqual(Heirloom(record: record(games: 500), slot: .queen).patina, 1, accuracy: 0.001)
    }

    func testEachPieceKeepsItsOwnSeamPattern() {
        let a = Heirloom(record: record(escapes: 1), slot: .aPawn)
        let b = Heirloom(record: record(escapes: 1), slot: .hPawn)
        XCTAssertNotEqual(a.seed, b.seed)
    }

    func testTheStoryNamesEveryMark() {
        let rec = record(escapes: 1, revenge: [2], promotions: 1, captures: 10, games: 30)
        let lines = Heirloom(record: rec, slot: .aPawn).story(for: rec)
        XCTAssertTrue(lines.contains { $0.contains("seam") })
        XCTAssertTrue(lines.contains { $0.contains("collar") })
        XCTAssertTrue(lines.contains { $0.contains("notch") })
        XCTAssertTrue(lines.contains { $0.contains("Patina") })
    }

    @MainActor
    func testTheStoreReadsTheHeirloomFromTheRecord() {
        var army = ArmyStore.Army()
        army.records[.queen] = record(captures: 10)
        let store = ArmyStore(army: army)
        XCTAssertEqual(store.heirloom(for: .queen).notches, 2)
    }

    func testSeededRandomIsRepeatable() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        XCTAssertEqual(a.next(), b.next())
        XCTAssertTrue((0..<1000).allSatisfy { _ in let v = a.next(); return v >= 0 && v < 1 })
    }
}
