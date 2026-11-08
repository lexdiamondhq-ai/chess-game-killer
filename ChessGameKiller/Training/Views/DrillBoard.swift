import ChessKit
import SwiftUI

/// A puzzle's board, as in a game: the real 3D board, tilted with the pieces standing or flat
/// from above, when the look has one and 3D pieces are on; otherwise the flat board. Under it,
/// whose move it is, and the Tilted / Flat switch the game has beside its moves.
struct DrillBoard: View {
    let runner: DrillRunner
    let theme: BoardTheme
    /// How wide the screen makes the flat board, which is as tall, keeping `TrainingBoardView.sideRoom`
    /// beside it. The 3D board takes that room too, edge to edge as in a game, and is a little
    /// less tall, being seen at an angle.
    let side: CGFloat
    /// Whose move it is, while there is one to find.
    var showsTurn = true

    @AppStorage("sculpted3D") private var sculpted3D = true

    private var threeD: Bool { BoardView.playsIn3D(theme, setting: sculpted3D) }

    var body: some View {
        TrainerBoard(game: runner.game, theme: theme, side: side, flipped: runner.learner == .black,
                     arrows: runner.arrows, marks: runner.marks, labels: runner.labels,
                     onTap: runner.acceptsTaps ? { (square: Square) in runner.tap(square) } : nil,
                     turn: runner.learner, showsTurn: showsTurn)
            // A screen that keeps its board for the next puzzle hands it another drill.
            .onChange(of: SoundTiming(drill: ObjectIdentifier(runner), threeD: threeD), initial: true) { _, timing in
                Self.timeSounds(of: runner, threeD: timing.threeD)
            }
    }

    /// What the timing of the move sounds hangs on: the drill, and whether its board is the 3D one.
    private struct SoundTiming: Equatable {
        let drill: ObjectIdentifier
        let threeD: Bool
    }

    /// The 3D board's width: the flat board's and the room beside it, as the game's board runs
    /// edge to edge with its frame going off the sides.
    static func width3D(side: CGFloat) -> CGFloat {
        side + TrainingBoardView.sideRoom
    }

    /// The 3D board's height at this width: standing, its tallest shape, so the camera looks
    /// down as steeply as the game's does on a tall phone; flat from above, nearly square.
    static func height3D(side: CGFloat, framing: SculptedCamera.Framing) -> CGFloat {
        let aspect = framing == .standing ? CGFloat(SculptedCamera.standingAspects.lowerBound) : framing.aspect
        return (side / max(aspect, 0.01)).rounded()
    }

    /// A move's sound is heard as its piece touches down: on the 3D board it glides there
    /// first, as in a game.
    static func timeSounds(of runner: DrillRunner, threeD: Bool) {
        if threeD {
            runner.landingDelay = { [weak runner] move in
                guard let runner else { return 0 }
                return SculptedBoardScene.landingDelay(for: move, in: runner.game)
            }
        } else {
            runner.landingDelay = { _ in 0 }
        }
    }
}
