import XCTest

/// The Trophy Hall, opened by real taps from Rooms, measured on the simulator.
///
/// Alex, 2026-11-27: the five rival coins grew bigger rival by rival, two names ran together
/// ("BerserkerLionheart"), and the six record cards were uneven heights in crooked rows.
/// These tests fail unless every coin is the same size on one line and every card is the same size.
final class TrophyHallLayoutTests: TapTestCase {
    /// Home, Rooms, Trophy Hall, with the room's film already seen.
    private func openTrophyHall() {
        launch(["-rooms.filmsSeen", "(trophies)"])
        tap(buttons("Rooms"), "The Rooms tab on Home", scrolls: false)
        tap(buttons("Trophy Hall"), "Trophy Hall in Rooms")
        expect(anything(labeled: "Every rival you beat stands here in gold."),
               "Tapping Trophy Hall did not open the hall")
    }

    private func frames(_ identifier: String) -> [CGRect] {
        app.descendants(matching: .any).matching(identifier: identifier)
            .allElementsBoundByIndex.map(\.frame)
    }

    /// One point of slack for the simulator's rounding.
    private func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1 }

    func testEveryRivalOnTheShelfIsTheSameSize() {
        openTrophyHall()
        let rivals = frames("trophy-hall.rival")
        XCTAssertEqual(rivals.count, 5, "The shelf should hold the five rivals")
        guard let first = rivals.first else { return }
        // A rival's frame is its coin and name together, as wide as the wider of the two
        // ("Berserker" is a little wider than its coin), so the width check is that each holds a full coin.
        for (index, frame) in rivals.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.width, 49, "Rival \(index + 1) is only \(frame.width) wide")
            XCTAssertTrue(same(frame.height, first.height), "Rival \(index + 1) is \(frame.height) tall, the first is \(first.height)")
            XCTAssertTrue(same(frame.minY, first.minY), "Rival \(index + 1) is not on the same line as the first")
        }
        // Evenly spaced: the same distance from each rival's middle to the next.
        let middles = rivals.map(\.midX)
        let gaps = zip(middles, middles.dropFirst()).map { $1 - $0 }
        for gap in gaps {
            XCTAssertTrue(same(gap, gaps[0]), "The rivals are not evenly spaced: \(gaps)")
        }
        // Side by side, never overlapping (the names ran into each other).
        for (left, right) in zip(rivals, rivals.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX + 0.5, "Two rivals on the shelf overlap")
        }
    }

    func testEveryRecordCardIsTheSameSize() {
        openTrophyHall()
        app.swipeUp()
        let cards = frames("trophy-hall.record")
        XCTAssertEqual(cards.count, 6, "Records should show six cards")
        guard let first = cards.first else { return }
        for (index, frame) in cards.enumerated() {
            XCTAssertTrue(same(frame.width, first.width), "Card \(index + 1) is \(frame.width) wide, the first is \(first.width)")
            XCTAssertTrue(same(frame.height, first.height), "Card \(index + 1) is \(frame.height) tall, the first is \(first.height)")
        }
        // Two clean rows of three: tops line up along each row, and the columns line up down the grid.
        if cards.count == 6 {
            for column in 0..<3 {
                XCTAssertTrue(same(cards[column].minY, first.minY), "Card \(column + 1) is not on the first row's line")
                XCTAssertTrue(same(cards[column + 3].minY, cards[3].minY), "Card \(column + 4) is not on the second row's line")
                XCTAssertTrue(same(cards[column].minX, cards[column + 3].minX), "Column \(column + 1) is crooked")
            }
        }
    }
}
