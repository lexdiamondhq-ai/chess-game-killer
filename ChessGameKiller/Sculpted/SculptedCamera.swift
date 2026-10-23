import ChessKit
import CoreGraphics
import simd

/// Where the 3D board's camera stands and how it sees, worked out the same way SceneKit
/// does, so taps, name tags and VoiceOver frames line up with the picture without asking
/// the renderer.
///
/// The board lies on y = 0, one unit per square, a1 at (-3.5, 0, 3.5) and h8 at (3.5, 0, -3.5).
/// White's camera looks from +z; flipped, it stands on black's side.
struct SculptedCamera: Equatable {
    /// Height above the board, as an angle: 90 degrees would look straight down.
    var elevation: Float = 50 * .pi / 180
    /// Across the view, like a short telephoto lens, so far squares shrink only a little.
    var fieldOfView: Float = 22 * .pi / 180
    /// 0 with White at the bottom, pi with Black.
    var azimuth: Float = 0
    var distance: Float = 24
    /// The point looked at, measured as if White were at the bottom.
    var focus = SIMD3<Float>(0, 0, 0)
    /// Width over height of the view.
    var aspect: Float = 1

    static let up = SIMD3<Float>(0, 1, 0)

    /// The look point turned to the camera's side of the board.
    var target: SIMD3<Float> {
        SIMD3(focus.x * cos(azimuth) + focus.z * sin(azimuth), focus.y, focus.z * cos(azimuth) - focus.x * sin(azimuth))
    }

    var eye: SIMD3<Float> {
        target + distance * SIMD3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
    }

    private var basis: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, Self.up))
        return (right, simd_cross(right, forward), forward)
    }

    private var halfWidth: Float { tan(fieldOfView / 2) }
    private var halfHeight: Float { halfWidth / max(aspect, 0.01) }

    /// A point in the scene on the view, from -1 to 1 both ways, y up.
    func normalized(_ point: SIMD3<Float>) -> SIMD2<Float> {
        let (right, up, forward) = basis
        let v = point - eye
        let depth = max(simd_dot(v, forward), 0.001)
        return SIMD2(simd_dot(v, right) / (depth * halfWidth), simd_dot(v, up) / (depth * halfHeight))
    }

    /// A point in the scene on a view of `size`, in points from the top left.
    func screenPoint(_ point: SIMD3<Float>, in size: CGSize) -> CGPoint {
        let n = normalized(point)
        return CGPoint(x: CGFloat((n.x + 1) / 2) * size.width, y: CGFloat((1 - n.y) / 2) * size.height)
    }

    /// Where the line of sight through a point of the view meets the board's surface
    /// (or a level `height` above it).
    func boardPoint(at point: CGPoint, in size: CGSize, height: Float = 0) -> SIMD3<Float>? {
        guard size.width > 0, size.height > 0 else { return nil }
        let nx = Float(point.x / size.width) * 2 - 1
        let ny = 1 - Float(point.y / size.height) * 2
        let (right, up, forward) = basis
        let ray = simd_normalize(forward + nx * halfWidth * right + ny * halfHeight * up)
        guard ray.y < -0.0001 else { return nil }
        let t = (height - eye.y) / ray.y
        return eye + t * ray
    }

    /// The square under a point of the view, if the line of sight lands on one.
    func square(at point: CGPoint, in size: CGSize) -> Square? {
        boardPoint(at: point, in: size).flatMap(Self.square(at:))
    }

    /// The square's outline on the view, as the smallest rectangle around it.
    func frame(of square: Square, in size: CGSize) -> CGRect {
        let center = Self.position(of: square)
        let corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { dx, dz in
            screenPoint(center + SIMD3(Float(dx), 0, Float(dz)), in: size)
        }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    // MARK: The board

    /// The center of a square on the board's surface.
    static func position(of square: Square) -> SIMD3<Float> {
        SIMD3(Float(square.fileIndex) - 3.5, 0, 3.5 - Float(square.rankIndex))
    }

    static func square(at point: SIMD3<Float>) -> Square? {
        let file = Int((point.x + 4).rounded(.down))
        let rank = Int((4 - point.z).rounded(.down))
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return Square(file: file, rank: rank)
    }

    /// Half the board's width including its frame.
    static let boardHalfWidth: Float = 4.55
    /// The tallest piece, the king, with its cross.
    static let tallest: Float = 1.47

    /// What must stay in the picture: the frame's corners (its top and the bottom of its
    /// near face) and the tops of the tallest pieces on the far rank.
    static var keyPoints: [SIMD3<Float>] {
        let w = boardHalfWidth
        var points: [SIMD3<Float>] = []
        for x in [-w, w] {
            for z in [-w, w] {
                points.append(SIMD3(x, 0.005, z))
                points.append(SIMD3(x, -0.135, z))
            }
        }
        for x: Float in [-3.5, 0, 3.5] {
            points.append(SIMD3(x, tallest, -3.5))
        }
        return points
    }

    // MARK: Framing

    /// The camera for a view of this shape: the board as wide as the view allows, the
    /// picture centered top to bottom. Flipping turns the same framing to black's side.
    static func fitted(aspect: Float, flipped: Bool) -> SculptedCamera {
        var camera = SculptedCamera()
        camera.aspect = aspect
        // Find the look point that centers the picture, then the distance that fits it.
        var low: Float = -3
        var high: Float = 3
        for _ in 0..<28 {
            let mid = (low + high) / 2
            camera.focus = SIMD3(0, 0, mid)
            camera.distance = camera.fittingDistance()
            let offset = camera.verticalOffset()
            // Looking farther back moves the board down the view.
            if offset > 0 { high = mid } else { low = mid }
        }
        camera.focus = SIMD3(0, 0, (low + high) / 2)
        camera.distance = camera.fittingDistance()
        camera.azimuth = flipped ? .pi : 0
        return camera
    }

    private static let margin = SIMD2<Float>(0.012, 0.035)

    /// The nearest distance at which every key point is inside the view's margins.
    private func fittingDistance() -> Float {
        var near: Float = 4
        var far: Float = 120
        var probe = self
        for _ in 0..<32 {
            let mid = (near + far) / 2
            probe.distance = mid
            if probe.fits() { far = mid } else { near = mid }
        }
        return far
    }

    private func fits() -> Bool {
        Self.keyPoints.allSatisfy { point in
            let n = normalized(point)
            return abs(n.x) <= 1 - Self.margin.x && abs(n.y) <= 1 - Self.margin.y
        }
    }

    /// How far the picture's middle sits above the view's middle, from -1 to 1.
    private func verticalOffset() -> Float {
        let ys = Self.keyPoints.map { normalized($0).y }
        return (ys.max()! + ys.min()!) / 2
    }
}
