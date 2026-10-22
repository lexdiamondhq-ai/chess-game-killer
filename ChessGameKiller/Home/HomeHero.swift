import ChessKit
import SwiftUI
import UIKit

/// The board at the top of the home screen: the real 3D set seen low and from the corner,
/// like a photograph of a real board, lit by the board's own studio. As the page scrolls
/// the camera walks around the board and moves in on White's king and queen; pulled down
/// past the top, it rises and steps back to take in the whole board.
enum HomeHeroCamera {
    /// Low and from White's left corner, close enough that the board runs off the sides
    /// and White's pieces stand large in front, Black's in the distance.
    static func camera(aspect: Float) -> SculptedCamera {
        camera(aspect: aspect, progress: 0, pull: 0)
    }

    /// `progress`: 0 at rest, 1 once the page has scrolled the hero away.
    /// `pull`: 0 at rest, 1 when the page is pulled well down past the top.
    static func camera(aspect: Float, progress: Float, pull: Float) -> SculptedCamera {
        let t = Ease.smooth(progress)
        let lift = Ease.slowEnd(pull)
        var camera = SculptedCamera()
        camera.elevation = (mix(20, 12, t) + 16 * lift) * .pi / 180
        camera.azimuth = (mix(-24, 36, t) + 8 * lift) * .pi / 180
        camera.fieldOfView = mix(32, 30, t) * .pi / 180
        camera.distance = mix(11, 6, t) + 3 * lift
        // The look point, measured as if White sat at the bottom: the board's near half
        // at rest, the king's side of White's back rank at the end of the walk.
        camera.focus = SIMD3(mix(0, -1.52, t), mix(0, 0.3, t), mix(1.6, 2.6, t) - 0.8 * lift)
        camera.aspect = aspect
        return camera
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}

/// The live board for the hero: no taps, just the pieces and a camera the page moves.
struct HomeHeroBoard: UIViewRepresentable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let camera: SculptedCamera

    func makeUIView(context: Context) -> SculptedSceneKitView {
        let scene = stage.scene(for: look)
        scene.apply(state, animated: false)
        scene.heldCamera = camera
        return scene.view
    }

    func updateUIView(_ view: SculptedSceneKitView, context: Context) {
        let scene = stage.scene(for: look)
        scene.apply(state, animated: true)
        if scene.heldCamera != camera { scene.heldCamera = camera }
    }

    private var state: SculptedBoardState {
        SculptedBoardState(pieces: pieces.map { PlacedPiece(id: 0, piece: $0) }, matchesPieces: true)
    }
}

/// The hero: the board over a warm studio glow, sinking into the page below.
/// `offset` is how far the page has scrolled (negative when pulled down past the top).
struct HomeHero: View {
    let look: SculptedLook
    let pieces: [Piece]
    let height: CGFloat
    let offset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = SculptedStage()
    @State private var breathe = false
    @State private var shown = false

    /// How far the page scrolls while the camera walks around: a little over half the hero.
    private var walk: CGFloat { height * 0.62 }
    /// 0 at rest, 1 once the walk is over.
    private var progress: CGFloat { min(max(offset / walk, 0), 1) }
    /// 0 at rest, 1 when pulled well down past the top.
    private var pull: CGFloat { min(max(-offset / 150, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = height + max(-offset, 0)
            ZStack(alignment: .top) {
                studio
                if SculptedAssets.shared.isLoaded {
                    HomeHeroBoard(stage: stage, look: look, pieces: pieces,
                                  camera: HomeHeroCamera.camera(aspect: Float(width / max(height, 1)),
                                                                progress: Float(reduceMotion ? 0 : progress),
                                                                pull: Float(reduceMotion ? 0 : pull)))
                        .id(look.name)
                        .frame(width: width, height: height)
                        .scaleEffect(breathe ? 1.035 : 1, anchor: .center)
                        .opacity(shown ? 1 : 0)
                }
                // The board sinks into the page: clear at the top, the page color at the foot.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.52),
                    .init(color: HomePalette.background.opacity(0.55), location: 0.76),
                    .init(color: HomePalette.background, location: 1.0),
                ], startPoint: .top, endPoint: .bottom)
                // The status bar stays readable over the far side of the board.
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: height * 0.3)
                    .frame(maxHeight: .infinity, alignment: .top)
                // Darkens once the camera has come close, as the cards cover it.
                HomePalette.background.opacity(Double(max(progress - 0.45, 0) / 0.55) * 0.88)
            }
            .frame(width: width, height: total)
            .clipped()
            // Moves up at half the page's speed, so it lingers behind the cards.
            .offset(y: offset > 0 ? offset * 0.5 : offset)
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    /// A pool of warm light where the board sits, falling off to near black.
    private var studio: some View {
        ZStack {
            HomePalette.background
            RadialGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.17).opacity(0.85),
                                    Color(red: 0.14, green: 0.11, blue: 0.09).opacity(0.7), .clear],
                           center: UnitPoint(x: 0.55, y: 0.5), startRadius: 10, endRadius: height * 0.75)
            RadialGradient(colors: [HomePalette.amber.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.2, y: 0.12), startRadius: 0, endRadius: height * 0.5)
        }
    }
}
