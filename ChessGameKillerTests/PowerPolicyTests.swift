import SceneKit
import XCTest
@testable import ChessGameKiller

/// What the app holds back on a hot phone or in Low Power Mode, and what it leaves alone.
@MainActor
final class PowerPolicyTests: XCTestCase {

    func testOnlySeriousHeatOrLowPowerModeHoldsBack() {
        XCTAssertFalse(PowerPolicy.constrained(thermal: .nominal, lowPower: false))
        XCTAssertFalse(PowerPolicy.constrained(thermal: .fair, lowPower: false), "A warm phone is normal in a game")
        XCTAssertTrue(PowerPolicy.constrained(thermal: .serious, lowPower: false), "iOS is already slowing the phone down")
        XCTAssertTrue(PowerPolicy.constrained(thermal: .critical, lowPower: false))
        XCTAssertTrue(PowerPolicy.constrained(thermal: .nominal, lowPower: true), "Low Power Mode is the person asking")
    }

    func testThePolicyFollowsTheReadings() {
        let policy = PowerPolicy()
        XCTAssertFalse(policy.isConstrained)
        XCTAssertEqual(policy.engineBudget, .full)
        XCTAssertEqual(policy.framesPerSecond, 60)

        policy.update(thermal: .serious, lowPower: false)
        XCTAssertTrue(policy.isConstrained)
        XCTAssertEqual(policy.engineBudget, .light)
        XCTAssertEqual(policy.framesPerSecond, 30)

        policy.update(thermal: .nominal, lowPower: true)
        XCTAssertEqual(policy.engineBudget, .light)

        policy.update(thermal: .nominal, lowPower: false)
        XCTAssertEqual(policy.engineBudget, .full, "Everything comes back as the phone cools down")
        XCTAssertEqual(policy.framesPerSecond, 60)
    }

    /// The light budget is about a third of the work, and still enough to grade a move and
    /// light the best one.
    func testTheLightBudgetAsksForLessEverywhere() {
        let full = EngineBudget.full
        let light = EngineBudget.light
        XCTAssertLessThan(light.lookaheadDepth, full.lookaheadDepth)
        XCTAssertLessThan(light.lookaheadMs, full.lookaheadMs)
        XCTAssertLessThanOrEqual(light.gradeDepth, full.gradeDepth)
        XCTAssertLessThan(light.gradeBeforeMs, full.gradeBeforeMs)
        XCTAssertLessThan(light.gradeAfterMs, full.gradeAfterMs)
        XCTAssertGreaterThanOrEqual(light.gradeDepth, 8, "Deep enough to tell a blunder from a mistake")
        XCTAssertGreaterThanOrEqual(light.lookaheadDepth, 8, "Deep enough for a hint worth lighting")
        let fullMs = full.lookaheadMs + full.gradeBeforeMs + full.gradeAfterMs
        let lightMs = light.lookaheadMs + light.gradeBeforeMs + light.gradeAfterMs
        XCTAssertLessThanOrEqual(lightMs * 2, fullMs, "At most half the engine time a turn")
    }

    /// The 3D board draws at 60 frames a second with 4x smoothing, and at 30 with 2x when
    /// the phone should hold back.
    func testThe3DBoardDrawsLighterWhenHoldingBack() {
        let scene = SculptedBoardScene()
        scene.applyPower(constrained: false)
        XCTAssertEqual(scene.view.preferredFramesPerSecond, 60)
        XCTAssertEqual(scene.view.antialiasingMode, .multisampling4X)

        scene.applyPower(constrained: true)
        XCTAssertEqual(scene.view.preferredFramesPerSecond, 30)
        XCTAssertEqual(scene.view.antialiasingMode, .multisampling2X)

        scene.applyPower(constrained: false)
        XCTAssertEqual(scene.view.preferredFramesPerSecond, 60, "Back to full speed as soon as the phone allows")
        XCTAssertEqual(scene.view.antialiasingMode, .multisampling4X)
    }

    func testFramesPerSecondByState() {
        XCTAssertEqual(PowerPolicy.framesPerSecond(constrained: false), 60)
        XCTAssertEqual(PowerPolicy.framesPerSecond(constrained: true), 30)
    }
}
