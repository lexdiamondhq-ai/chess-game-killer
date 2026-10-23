import ChessKit
import CoreImage
import Observation
import SwiftUI
import UIKit

/// How far the home page has scrolled; below zero while the board is pulled down.
/// Only the board behind the page and the top edge read it, so the page itself is not
/// redrawn as it scrolls.
@Observable
final class HomeScroll {
    var y: CGFloat = 0
}

/// The camera on the board behind the home page: the real 3D set seen low and from the
/// corner, like a photograph of a real board. As the page scrolls the camera walks around
/// the board and moves in on your king; pulled down past the top, it rises and steps back.
///
/// The board fills the whole screen behind the page, so the camera is tilted down a little
/// (`anchor`) to stand the board in the top of the screen, where the page leaves it showing.
/// Playing Black, the same walk happens on Black's side and ends on Black's king.
enum HomeHeroCamera {
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
        var fieldOfView = mix(32, 30, t) * .pi / 180
        if widthScale > 1 {
            fieldOfView = 2 * atan(tan(fieldOfView / 2) * widthScale)
        }
        camera.fieldOfView = fieldOfView
        camera.distance = mix(11, 6, t) + 3 * lift
        // The look point, measured as if White sat at the bottom: the board's near half
        // at rest, the king's side of the back rank at the end of the walk.
        camera.focus = SIMD3(mix(0, -1.52, t), mix(0, 0.3, t), mix(1.6, 2.6, t) - 0.8 * lift)
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

/// The live board behind the page: no taps, just the pieces and a camera the page moves.
struct HomeHeroBoard: UIViewRepresentable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let camera: SculptedCamera

    final class Coordinator {
        var pieces: [Piece] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SculptedSceneKitView {
        let scene = stage.scene(for: look)
        scene.apply(state, animated: false)
        context.coordinator.pieces = pieces
        scene.heldCamera = camera
        return scene.view
    }

    func updateUIView(_ view: SculptedSceneKitView, context: Context) {
        let scene = stage.scene(for: look)
        // The page redraws this every frame it scrolls: only a real change touches the pieces.
        if context.coordinator.pieces != pieces {
            context.coordinator.pieces = pieces
            scene.apply(state, animated: true)
        }
        if scene.heldCamera != camera { scene.heldCamera = camera }
    }

    private var state: SculptedBoardState {
        SculptedBoardState(pieces: pieces.map { PlacedPiece(id: 0, piece: $0) }, matchesPieces: true)
    }
}

/// The world behind the home page: the board standing in a pool of light in a dark room.
/// It never scrolls away. As the page rises over it the camera walks in on your king, and the
/// picture slips softly out of focus and darkens, so the glass cards float over it.
struct HomeWorld: View {
    let scroll: HomeScroll
    let look: SculptedLook
    let tone: HomeTone
    let pieces: [Piece]
    let black: Bool
    /// Where the board's look point sits on the screen at rest, in points from the top.
    let center: CGFloat
    /// How far the page scrolls while the camera walks in.
    let walk: CGFloat
    /// Where the board fades into the room, at the top of the clock card.
    let foot: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = SculptedStage()
    @State private var shown = false
    /// The end of the walk, out of focus: what the page scrolls over.
    @State private var soft: UIImage?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let y = scroll.y
            let scrolled = min(max(y / max(walk, 1), 0), 1)
            let progress = reduceMotion ? 0 : scrolled
            let pull = reduceMotion ? 0 : min(max(-y / 150, 0), 1)
            // Out of focus over the last part of the walk.
            let frost = Self.smoothstep(0.4, 1, scrolled)
            ZStack(alignment: .top) {
                room(size)
                if SculptedAssets.shared.isLoaded {
                    HomeHeroBoard(stage: stage, look: look, pieces: pieces,
                                  camera: camera(size, progress: progress, pull: pull))
                        .id(look.name)
                        .frame(width: size.width, height: size.height)
                        .opacity(shown ? 1 : 0)
                }
                if let soft {
                    Image(uiImage: soft)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .opacity(frost)
                }
                // The board sinks into the room toward the foot of the screen.
                LinearGradient(stops: [
                    .init(color: tone.canvas.opacity(0), location: 0),
                    .init(color: tone.canvas.opacity(0.55), location: 0.55),
                    .init(color: tone.canvas.opacity(0.92), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(size.height - foot + 60, 0))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                // Darker as the page covers it, so titles read over it.
                tone.canvas.opacity(0.5 * frost)
                // The status bar stays readable over the far side of the board.
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
            }
            .frame(width: size.width, height: size.height)
            .task(id: softKey(size)) { await renderSoft(size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
        }
    }

    /// The room: its own dark, and the pool of light the board stands in.
    private func room(_ size: CGSize) -> some View {
        ZStack {
            tone.canvas
            RadialGradient(colors: [tone.pool.opacity(0.9), tone.pool.opacity(0.28), tone.canvas.opacity(0)],
                           center: UnitPoint(x: 0.55, y: center / max(size.height, 1)),
                           startRadius: 10, endRadius: max(size.width, 320) * 0.95)
        }
    }

    private func camera(_ size: CGSize, progress: CGFloat, pull: CGFloat) -> SculptedCamera {
        let height = max(size.height, 1)
        return HomeHeroCamera.camera(
            aspect: Float(size.width / height),
            anchor: Float(1 - 2 * center / height),
            progress: Float(progress), pull: Float(pull), black: black,
            widthScale: Float(max(size.width / 440, 1))
        )
    }

    // MARK: Out of focus

    private func softKey(_ size: CGSize) -> String {
        let place = pieces.map { "\($0.color == .white ? "w" : "b")\($0.kind.rawValue)\($0.square)" }.joined()
        return "\(look.name) \(black) \(Int(size.width))x\(Int(size.height)) \(Int(center)) \(reduceMotion) \(place)"
    }

    /// Draws the end of the walk once, a moment after the page appears, and blurs it.
    @MainActor
    private func renderSoft(_ size: CGSize) async {
        guard SculptedAssets.shared.isLoaded, size.width > 1, size.height > 1 else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        let end = camera(size, progress: reduceMotion ? 0 : 1, pull: 0)
        let scene = stage.scene(for: look)
        guard let still = scene.still(from: end, size: size, scale: 1) else { return }
        soft = Self.blurred(still)
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func blurred(_ image: UIImage, sigma: Double = 16) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        guard let result = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    static func smoothstep(_ low: CGFloat, _ high: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
