import ChessKit
import Observation
import SwiftUI
import UIKit

/// How far the home page has scrolled; below zero while the page is pulled down.
/// Only the board window, the top edge and the pull cue read it, so the page itself is not
/// redrawn as it scrolls.
@Observable
final class HomeScroll {
    var y: CGFloat = 0
}

/// The camera on the home's board: the real 3D set seen low and from the corner, like a
/// photograph of a real board. Along its walk it goes around the board and in on your king;
/// pulled up and back, it rises and steps away.
///
/// `anchor` tilts it so the look point sits higher or lower in the view (the board window
/// stands the pieces in its top and leaves its foot for words). The walk ends looking at the
/// king's crown. Playing Black, the same walk happens on Black's side and ends on Black's king.
enum HomeHeroCamera {
    /// The lens: the game board's own, a short telephoto, so the pieces keep their shape up close.
    static let fieldOfView: Float = 22 * .pi / 180

    /// At rest, with the look point in the middle of the view.
    static func camera(aspect: Float) -> SculptedCamera {
        camera(aspect: aspect, progress: 0, pull: 0)
    }

    /// - Parameters:
    ///   - aspect: width over height of the view.
    ///   - anchor: where the look point sits in the view, from -1 (bottom) to 1 (top).
    ///   - progress: 0 at rest, 1 once the page has scrolled the walk away.
    ///   - pull: 0 at rest, 1 when the page is pulled well down past the top.
    ///   - black: the player's side is Black.
    ///   - widthScale: above 1 on a wide screen, where the board keeps a phone's size with more room around it.
    static func camera(aspect: Float, anchor: Float = 0, progress: Float, pull: Float,
                       black: Bool = false, widthScale: Float = 1) -> SculptedCamera {
        let t = Ease.smooth(progress)
        let lift = Ease.slowEnd(pull)
        var camera = SculptedCamera()
        camera.elevation = (mix(20, 12, t) + 16 * lift) * .pi / 180
        camera.azimuth = (mix(-24, 36, t) + 8 * lift) * .pi / 180
        var fieldOfView = Self.fieldOfView
        if widthScale > 1 {
            fieldOfView = 2 * atan(tan(fieldOfView / 2) * widthScale)
        }
        camera.fieldOfView = fieldOfView
        camera.distance = mix(11, 8, t) + 3 * lift
        // The look point, measured as if White sat at the bottom: the board's near half
        // at rest, the king's head (crown and cross) at the end of the walk.
        camera.focus = SIMD3(mix(0, -1.66, t), mix(0, 1.0, t), mix(1.6, 2.6, t) - 0.8 * lift)
        camera.aspect = aspect
        if black {
            // The board seen in a mirror across its middle: Black's corner, ending on Black's king.
            camera.azimuth = .pi - camera.azimuth
            camera.focus.x = -camera.focus.x
        }
        return tilted(camera, anchor: anchor)
    }

    /// The same eye, looking a little lower, so the old look point sits at `anchor` in the view.
    static func tilted(_ camera: SculptedCamera, anchor: Float) -> SculptedCamera {
        guard anchor != 0 else { return camera }
        let halfHeight = tan(camera.fieldOfView / 2) / max(camera.aspect, 0.01)
        let eye = camera.eye
        var turned = camera
        turned.elevation = camera.elevation + atan(anchor * halfHeight)
        let a = camera.azimuth
        let e = turned.elevation
        let target = eye - camera.distance * SIMD3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
        turned.focus = SIMD3(target.x * cos(a) - target.z * sin(a), target.y, target.z * cos(a) + target.x * sin(a))
        return turned
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}

/// The live board in the home's window: no taps, just the pieces and a camera the page moves.
struct HomeHeroBoard: UIViewRepresentable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let camera: SculptedCamera

    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true

    final class Coordinator {
        var pieces: [Piece] = []
        var showsCoordinates = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SculptedSceneKitView {
        let scene = stage.scene(for: look)
        scene.apply(state, animated: false)
        context.coordinator.pieces = pieces
        context.coordinator.showsCoordinates = showsCoordinates
        scene.heldCamera = camera
        return scene.view
    }

    func updateUIView(_ view: SculptedSceneKitView, context: Context) {
        let scene = stage.scene(for: look)
        // The page redraws this every frame it scrolls: only a real change touches the pieces.
        if context.coordinator.pieces != pieces || context.coordinator.showsCoordinates != showsCoordinates {
            context.coordinator.pieces = pieces
            context.coordinator.showsCoordinates = showsCoordinates
            scene.apply(state, animated: true)
        }
        if scene.heldCamera != camera { scene.heldCamera = camera }
    }

    private var state: SculptedBoardState {
        var state = SculptedBoardState(pieces: pieces.map { PlacedPiece(id: 0, piece: $0) }, matchesPieces: true)
        state.showsCoordinates = showsCoordinates
        return state
    }
}
