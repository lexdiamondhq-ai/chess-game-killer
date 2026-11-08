import ChessKit
import SceneKit
import UIKit
import simd

/// The pieces for the flat board, seen from straight above: Floating Cut-outs, Alex's pick of
/// the bold looks (2026-11-07). Each piece is a bold paper-cut shape that hovers a little above
/// its square and casts a long soft shadow off to the side, so it reads as standing up even from
/// straight above, and the square's color shows all round it. White is warm paper with dark
/// lines; Black is near-black with gold detail and a thin gold edge, so it reads on a dark square.
///
/// Each piece is two pictures (scripts/sculpted/flat/cutouts.js) on planes: the shape, lit to
/// follow the board's light (`light`), and under it its shadow, set off toward the player's right.
/// The shape's clear pixels are cut away, so the board's marks show through them and an arrow on
/// the stone still passes under the piece.
///
/// Sizes are in squares, the piece's square at the origin, y up, the top of the piece toward -z
/// (away from White), like the carved sets.
enum SculptedFlatSet {
    /// How far across a square the pictures reach: the 45-unit box the pieces are drawn in.
    static let span: CGFloat = 0.92

    /// How high the shape hovers over the stone.
    static let hover: Float = 0.05

    /// Where the shadow falls from under the shape: toward the player's right and toward them.
    static let shadowOffset = SIMD2<Float>(0.075, 0.1)

    /// How far each shape reaches from its square's center, gold edge and all, read off its
    /// picture at `span`.
    static func half(of kind: Piece.Kind) -> Float {
        switch kind {
        case .king: return 0.376
        case .queen: return 0.403
        case .rook: return 0.363
        case .bishop: return 0.372
        case .knight: return 0.363
        case .pawn: return 0.372
        }
    }

    /// How far the piece reaches from its square's center across the board, and how high it
    /// hovers, in squares.
    static func extent(of kind: Piece.Kind) -> (reach: Float, height: Float) {
        (half(of: kind), hover)
    }

    /// The shape's picture's name in the asset catalog.
    static func pictureName(_ kind: Piece.Kind, color: Piece.Color) -> String {
        "cutout-\(color == .white ? "w" : "b")\(kind.letter)"
    }

    /// The shadow's picture's name: one for both colors.
    static func shadowName(_ kind: Piece.Kind) -> String {
        "cutout-shadow-\(kind.letter)"
    }

    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode {
        let node = SCNNode()

        let shadow = SCNNode(geometry: SCNPlane(width: span, height: span))
        shadow.geometry?.materials = [shadowMaterial(kind)]
        shadow.eulerAngles.x = -.pi / 2
        shadow.position = SCNVector3(shadowOffset.x, 0.0018, shadowOffset.y)
        // With the contact shadows: under the board's marks and every piece.
        shadow.renderingOrder = 5

        let shape = SCNNode(geometry: SCNPlane(width: span, height: span))
        shape.geometry?.materials = [picture(kind, color: color, look: look)]
        shape.eulerAngles.x = -.pi / 2
        shape.position = SCNVector3(0, hover, 0)
        // Over the board's marks, which show through its clear pixels, and under the arrows.
        shape.renderingOrder = 14

        for part in [shadow, shape] {
            part.castsShadow = false
            part.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(part)
        }
        return node
    }

    /// Dims the pictures with the studio for the finale (`SculptedBoardScene.dim`): they light
    /// themselves, so they follow by hand, about as much as the board does.
    static func dim(_ dimmed: Bool) {
        for material in pictures.values {
            material.multiply.contents = UIColor(white: dimmed ? 0.53 : 1, alpha: 1)
        }
    }

    /// The glow of the fine line round the squares in the flat view. From straight above the line
    /// faces the studio's dark ceiling (`SculptedLook.studioAbove`) and reflects little, so a
    /// brighter glow than the tilted view's keeps it gold, or platinum, rather than a dull brown
    /// or grey.
    static func glow(_ look: SculptedLook) -> UIColor {
        guard let glow = look.metalGlow else { return scaled(look.platinum, by: 0.5) }
        return scaled(glow, by: 1.6)
    }

    private static var pictures: [String: SCNMaterial] = [:]
    private static var shadows: [Piece.Kind: SCNMaterial] = [:]

    private static func picture(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let name = pictureName(kind, color: color)
        let key = "\(look.name)-\(name)"
        if let made = pictures[key] { return made }
        let material = SCNMaterial()
        // The picture is drawn as it is, then brightened or dimmed with the board's light where
        // the piece stands. Its clear pixels are cut away, so they hide nothing beneath.
        material.lightingModel = .constant
        material.diffuse.contents = UIImage(named: name)
        material.diffuse.mipFilter = .linear
        material.blendMode = .alpha
        var fragment = cut
        if let spot = look.spot { fragment += light(spot) }
        material.shaderModifiers = [.fragment: fragment]
        pictures[key] = material
        return material
    }

    /// Drops the shape's clear pixels, so they write no depth and the marks under them show.
    private static let cut = """
    if (_output.color.a < 0.04) { discard_fragment(); }

    """

    private static func shadowMaterial(_ kind: Piece.Kind) -> SCNMaterial {
        if let made = shadows[kind] { return made }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIImage(named: shadowName(kind))
        material.diffuse.mipFilter = .linear
        material.blendMode = .alpha
        material.transparency = 0.42
        material.writesToDepthBuffer = false
        shadows[kind] = material
        return material
    }

    /// The board's light where the piece stands, relative to the middle of the board, where the
    /// pictures look as drawn. The looks with a spot key light the board in a pool, brightest
    /// toward the player's left: the light the squares take there is the key's (falling off with
    /// distance and toward the rim of its cone) plus an even share from the studio and the rim
    /// light. Its strengths were read off the Gilded board's squares in the app, which they match
    /// within 1%; every look with a spot key has the same lights. The key turns with the camera,
    /// so it is placed from the side the camera looks from.
    private static func light(_ spot: (inner: CGFloat, outer: CGFloat)) -> String {
        let key = SculptedBoardScene.keyPosition
        let inner = cos(Double(spot.inner) / 2 * .pi / 180)
        let outer = cos(Double(spot.outer) / 2 * .pi / 180)
        let even = 0.501
        let strength = 115.6
        // At the middle of the board, the key shines straight down its cone.
        let middle = even + strength * Double(key.y) / Double(simd_length_squared(key)) / Double(simd_length(key))
        return """
        float4x4 flatCamera = scn_frame.inverseViewTransform;
        float3 flatPoint = (flatCamera * float4(_surface.position, 1.0)).xyz;
        float2 flatSide = flatCamera[2].xz;
        flatSide = length(flatSide) > 0.0001 ? normalize(flatSide) : float2(0.0, 1.0);
        float3 flatKey = float3(\(key.x) * flatSide.y + \(key.z) * flatSide.x, \(key.y),
                                 \(-key.x) * flatSide.x + \(key.z) * flatSide.y);
        float3 flatToKey = flatKey - flatPoint;
        float flatDistance2 = dot(flatToKey, flatToKey);
        float3 flatL = flatToKey * rsqrt(flatDistance2);
        float flatCone = saturate((dot(-flatL, normalize(-flatKey)) - \(outer)) / \(inner - outer));
        float flatLight = \(even) + \(strength) * max(flatL.y, 0.0) * flatCone / flatDistance2;
        _output.color.rgb *= flatLight / \(middle);
        """
    }

    private static func scaled(_ color: UIColor, by factor: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: min(red * factor, 1), green: min(green * factor, 1), blue: min(blue * factor, 1), alpha: alpha)
    }
}

private extension Piece.Kind {
    /// The letter the pictures are named by.
    var letter: String {
        switch self {
        case .king: return "K"
        case .queen: return "Q"
        case .rook: return "R"
        case .bishop: return "B"
        case .knight: return "N"
        case .pawn: return "P"
        }
    }
}
