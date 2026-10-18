import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class ChessClockTests: XCTestCase {

    func testTimeControlsDescribeThemselves() {
        XCTAssertEqual(TimeControl.blitz3Plus2.initial, .seconds(180))
        XCTAssertEqual(TimeControl.blitz3Plus2.increment, .seconds(2))
        XCTAssertEqual(TimeControl.rapid10.initial, .seconds(600))
        XCTAssertEqual(TimeControl.rapid10.increment, .zero)
        XCTAssertEqual(TimeControl.rapid15Plus10.name, "15+10")
        XCTAssertEqual(TimeControl.unlimited.name, "No clock")
        XCTAssertFalse(TimeControl.unlimited.isTimed)
        XCTAssertTrue(TimeControl.blitz5.isTimed)
    }

    func testOnlyTheRunningSideLosesTime() {
        let clock = ChessClock(initial: .seconds(60))
        let t0 = ContinuousClock.now
        XCTAssertNil(clock.running)
        XCTAssertEqual(clock.remaining(for: .white, at: t0), .seconds(60))

        clock.start(.white, at: t0)
        XCTAssertEqual(clock.running, .white)
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(10)), .seconds(50))
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(10)), .seconds(60))
        clock.pause(at: t0 + .seconds(10))
    }

    func testMovingAddsTheIncrementAndSwitchesSides() {
        let clock = ChessClock(initial: .seconds(60), increment: .seconds(2))
        let t0 = ContinuousClock.now
        clock.start(.white, at: t0)
        clock.moved(by: .white, at: t0 + .seconds(10))

        XCTAssertEqual(clock.running, .black)
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(30)), .seconds(52))
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(15)), .seconds(55))

        clock.moved(by: .black, at: t0 + .seconds(15))
        XCTAssertEqual(clock.running, .white)
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(40)), .seconds(57))
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(17)), .seconds(50))
        clock.pause(at: t0 + .seconds(17))
    }

    func testPauseFreezesBothSides() {
        let clock = ChessClock(initial: .seconds(60))
        let t0 = ContinuousClock.now
        clock.start(.black, at: t0)
        clock.pause(at: t0 + .seconds(5))

        XCTAssertNil(clock.running)
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(50)), .seconds(55))
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(50)), .seconds(60))

        clock.start(.black, at: t0 + .seconds(50))
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(51)), .seconds(54))
        clock.pause(at: t0 + .seconds(51))
    }

    func testTimeNeverGoesBelowZero() {
        let clock = ChessClock(initial: .seconds(5))
        let t0 = ContinuousClock.now
        clock.start(.white, at: t0)
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(100)), .zero)
        clock.pause(at: t0)
    }

    func testFlagFallsWhenTimeRunsOut() async {
        let clock = ChessClock(initial: .milliseconds(80))
        var flagged: Piece.Color?
        clock.onFlag = { flagged = $0 }
        clock.start(.black)

        let deadline = ContinuousClock.now + .seconds(5)
        while flagged == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(flagged, .black)
        XCTAssertEqual(clock.flagged, .black)
        XCTAssertNil(clock.running)
        XCTAssertEqual(clock.remaining(for: .black), .zero)

        // Once a flag has fallen the clock is over for good.
        clock.start(.white)
        XCTAssertNil(clock.running)
    }

    func testClockLabels() {
        XCTAssertEqual(Duration.seconds(291).clockLabel, "4:51")
        XCTAssertEqual(Duration.seconds(600).clockLabel, "10:00")
        XCTAssertEqual(Duration.milliseconds(60500).clockLabel, "1:01")
        XCTAssertEqual(Duration.milliseconds(9400).clockLabel, "0:09.4")
        XCTAssertEqual(Duration.zero.clockLabel, "0:00.0")
    }
}
