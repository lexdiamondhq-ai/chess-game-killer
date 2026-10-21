import ChessKit
import SwiftUI
import UIKit

/// The picture at the top of the home screen: the 3D board seen low and from the corner,
/// like a photograph of a real set, lit by the board's own studio. It is drawn once as a
/// still, so the scroll can fade, lift and darken it like any image.
enum HomeHeroCamera {
    /// Low and from White's left corner, close enough that the board runs off the sides.
    static func camera(aspect: Float) -> SculptedCamera {
        var camera = SculptedCamera()
        camera.elevation = 34 * .pi / 180
        camera.azimuth = -30 * .pi / 180
        camera.fieldOfView = 30 * .pi / 180
        camera.distance = 15
        camera.focus = SIMD3(0, 0, -0.8)
        camera.aspect = aspect
        return camera
    }
}

@MainActor
enum HomeHeroRenderer {
    private static var cache: [String: UIImage] = [:]

    /// The board in `look` with these pieces, at `size` points.
    static func image(look: SculptedLook, pieces: [Piece], size: CGSize, scale: CGFloat) -> UIImage? {
        let key = "\(look.name)|\(Int(size.width))x\(Int(size.height))@\(scale)|" +
            pieces.map { "\($0.color == .white ? "w" : "b")\($0.kind)\($0.square)" }.sorted().joined()
        if let made = cache[key] { return made }
        guard SculptedAssets.shared.isLoaded else { return nil }
        let scene = SculptedBoardScene(look: look)
        scene.apply(SculptedBoardState(pieces: pieces.map { PlacedPiece(id: 0, piece: $0) }, matchesPieces: true),
                    animated: false)
        let camera = HomeHeroCamera.camera(aspect: Float(size.width / max(size.height, 1)))
        guard let image = scene.still(from: camera, size: size, scale: scale) else { return nil }
        // One board at a time is plenty; a new position replaces the old picture.
        cache = [key: image]
        return image
    }
}

/// The hero: the board picture over a warm studio glow, sinking into the page below.
/// `offset` is how far the page has scrolled (negative when pulled down past the top).
struct HomeHero: View {
    let look: SculptedLook
    let pieces: [Piece]
    let height: CGFloat
    let offset: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var breathe = false

    /// 0 at rest, 1 once the hero has scrolled out of sight.
    private var progress: CGFloat { min(max(offset / (height * 0.8), 0), 1) }
    /// Pulling down past the top stretches the picture.
    private var stretch: CGFloat { max(-offset, 0) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .top) {
                studio
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height + stretch)
                        .scaleEffect(breathe ? 1.045 : 1, anchor: .center)
                        .clipped()
                        .transition(.opacity)
                } else {
                    Color.clear.frame(width: width, height: height + stretch)
                }
                // The picture sinks into the page: clear at the top, the page color at the foot.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.52),
                    .init(color: HomePalette.background.opacity(0.55), location: 0.76),
                    .init(color: HomePalette.background, location: 1.0),
                ], startPoint: .top, endPoint: .bottom)
                // The status bar stays readable over the far side of the board.
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: height * 0.32)
                    .frame(maxHeight: .infinity, alignment: .top)
                // Darkens as it scrolls away.
                HomePalette.background.opacity(Double(progress) * 0.85)
            }
            .frame(width: width, height: height + stretch)
            .clipped()
            // Moves up at half the page's speed, so it lingers behind the cards.
            .offset(y: offset > 0 ? offset * 0.5 : -stretch)
            .task(id: renderKey(width: width)) { await render(width: width) }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
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

    private func renderKey(width: CGFloat) -> String {
        "\(look.name)|\(Int(width))|" + pieces.map { "\($0.kind)\($0.color)\($0.square)" }.joined()
    }

    @MainActor
    private func render(width: CGFloat) async {
        guard width > 1 else { return }
        // Let the page appear first; the picture fades in a moment later.
        if image == nil { try? await Task.sleep(for: .milliseconds(30)) }
        let made = HomeHeroRenderer.image(look: look, pieces: pieces, size: CGSize(width: width, height: height),
                                          scale: min(displayScale, 3))
        withAnimation(.easeOut(duration: 0.5)) { image = made }
    }
}
