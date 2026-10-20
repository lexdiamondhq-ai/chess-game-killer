import ChessKit
import XCTest
@testable import ChessGameKiller

@MainActor
final class ChessClockTests: XCTestCase {

    func testTimeControlsNameTheirKind() {
        XCTAssertNil(TimeControl.unlimited.kind)
        XCTAssertEqual(TimeControl.blitz5.kind, "Blitz")
        XCTAssertEqual(TimeControl.rapid15Plus10.kind, "Rapid")
    }

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

    func testClockLabelsRoundUpOnBothSidesOfTenSeconds() {
        XCTAssertEqual(Duration.milliseconds(10400).clockLabel, "0:11")
        XCTAssertEqual(Duration.milliseconds(9960).clockLabel, "0:10.0")
        XCTAssertEqual(Duration.milliseconds(9900).clockLabel, "0:09.9")
        XCTAssertEqual(Duration.milliseconds(40).clockLabel, "0:00.1")
    }

    func testTakingBackAMoveRemovesItsIncrement() {
        let clock = ChessClock(initial: .seconds(60), increment: .seconds(2))
        let t0 = ContinuousClock.now
        clock.start(.white, at: t0)
        clock.moved(by: .white, at: t0 + .seconds(10))
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(15)), .seconds(52))

        clock.tookBack(moveBy: .white, at: t0 + .seconds(15))
        XCTAssertNil(clock.running)
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(20)), .seconds(50))
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(20)), .seconds(55))

        // Never below zero, even when more than the increment has gone since the move.
        let short = ChessClock(initial: .seconds(1), increment: .seconds(5))
        short.start(.black, at: t0)
        short.moved(by: .black, at: t0 + .milliseconds(500))
        short.moved(by: .white, at: t0 + .milliseconds(600))
        short.tookBack(moveBy: .white, at: t0 + .seconds(6))
        short.tookBack(moveBy: .black, at: t0 + .seconds(6))
        XCTAssertEqual(short.remaining(for: .black, at: t0 + .seconds(6)), .zero)
        XCTAssertEqual(short.remaining(for: .white, at: t0 + .seconds(6)), .milliseconds(900))
        clock.pause(at: t0 + .seconds(20))
        short.pause(at: t0 + .seconds(6))
    }

    func testAHeldClockIgnoresStartsUntilReleased() {
        let clock = ChessClock(initial: .seconds(60), increment: .seconds(2))
        let t0 = ContinuousClock.now
        clock.start(.white, at: t0)
        clock.hold(at: t0 + .seconds(5))
        XCTAssertTrue(clock.held)
        XCTAssertNil(clock.running)

        // A move landing while held still earns its increment, but starts nobody.
        clock.moved(by: .white, at: t0 + .seconds(6))
        XCTAssertNil(clock.running)
        XCTAssertEqual(clock.remaining(for: .white, at: t0 + .seconds(30)), .seconds(57))
        clock.start(.black, at: t0 + .seconds(7))
        XCTAssertNil(clock.running)

        clock.release(.black, at: t0 + .seconds(10))
        XCTAssertFalse(clock.held)
        XCTAssertEqual(clock.running, .black)
        XCTAssertEqual(clock.remaining(for: .black, at: t0 + .seconds(11)), .seconds(59))
        clock.pause(at: t0 + .seconds(11))
    }
}
