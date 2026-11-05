import ChessKit
import SceneKit
import UIKit
import simd

/// The pieces for the flat board, seen from straight above: glass tiles with the piece etched
/// into them, as in the concept render Alex picked (design/flat-pieces/crystal.jpg). White is
/// milky glass with the piece inked dark on top; Black is smoked glass with the piece glowing gold
/// inside; a gold foot under both.
///
/// SceneKit can't draw glass like that: tried as see-through glass it came out plain white. So
/// each tile shows the render's own glass: a picture of it drawn in Cycles from the flat view's
/// angle (scripts/sculpted/flat/glass.py), laid on a plain tile that casts the shadow, and lit to
/// follow the board's light (`light`).
///
/// Sizes are in squares, the tile's foot at the origin, y up, the top of the piece toward -z
/// (away from White), like the carved sets.
enum SculptedFlatSet {
    /// Width and height of a tile: the pawn's is smaller.
    static func size(of kind: Piece.Kind) -> (width: CGFloat, height: CGFloat) {
        kind == .pawn ? (0.62, 0.2) : (0.78, 0.26)
    }

    /// The tile's rounded corners, seen from above, as in the pictures.
    static let corner: CGFloat = 0.08

    /// How far the picture reaches past the tile's top toward the player: the sliver of its near
    /// side the flat view sees, from 80 degrees up, as the pictures are drawn.
    static func reach(of kind: Piece.Kind) -> CGFloat {
        let elevation = CGFloat(SculptedCamera.Framing.seated.elevation)
        return size(of: kind).height / tan(elevation)
    }

    /// How far the tile reaches from its square's center across the board, and how tall it is,
    /// in squares.
    static func extent(of kind: Piece.Kind) -> (reach: Float, height: Float) {
        let tile = size(of: kind)
        return (Float(tile.width) / 2, Float(tile.height))
    }

    /// The picture's name in the asset catalog.
    static func pictureName(_ kind: Piece.Kind, color: Piece.Color) -> String {
        "glass-\(color == .white ? "w" : "b")\(kind.glassLetter)"
    }

    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode {
        let (width, height) = size(of: kind)
        let reach = Self.reach(of: kind)
        let node = SCNNode()

        // The plain tile: it casts the shadow and hides under the picture, but for a sliver of its
        // near side on the far ranks, which the camera sees from a little lower.
        let body = SCNNode(geometry: SCNBox(width: width, height: height, length: width, chamferRadius: corner))
        body.geometry?.materials = [side(color)]
        body.position = SCNVector3(0, Float(height / 2), 0)

        // The picture, on the tile's top: from its far edge to the near side's foot, as the flat
        // view sees the tile.
        let plane = SCNPlane(width: width, height: width + reach)
        plane.cornerRadius = corner
        plane.materials = [picture(kind, color: color, look: look)]
        let top = SCNNode(geometry: plane)
        top.eulerAngles.x = -.pi / 2
        top.position = SCNVector3(0, Float(height) + 0.0015, Float(reach / 2))
        top.castsShadow = false

        for part in [body, top] {
            part.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(part)
        }
        return node
    }

    /// Dims the pictures with the studio for the finale (`SculptedBoardScene.dim`): they light
    /// themselves, so they follow by hand, about as much as the board does.
    static func dim(_ dimmed: Bool) {
        for material in pictures.values {
            material.emission.intensity = dimmed ? 0.53 : 1
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
    private static var sides: [Piece.Color: SCNMaterial] = [:]

    private static func picture(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let name = pictureName(kind, color: color)
        let key = "\(look.name)-\(name)"
        if let made = pictures[key] { return made }
        let material = SCNMaterial()
        // The picture carries its own light, so it glows as it is drawn, over a black that takes
        // no light (lambert has no shine), then is brightened or dimmed with the board's light
        // where the tile stands.
        material.lightingModel = .lambert
        material.diffuse.contents = UIColor.black
        material.emission.contents = UIImage(named: name)
        material.emission.mipFilter = .linear
        if let spot = look.spot {
            material.shaderModifiers = [.fragment: light(spot)]
        }
        pictures[key] = material
        return material
    }

    /// The tile's sides, where they show below the picture: the glass's color there.
    private static func side(_ color: Piece.Color) -> SCNMaterial {
        if let made = sides[color] { return made }
        let made = color == .white
            ? SculptedAssets.pbr(UIColor(red: 0.6, green: 0.58, blue: 0.56, alpha: 1), roughness: 0.3, coat: 1, coatRoughness: 0.03)
            : SculptedAssets.pbr(UIColor(red: 0.2, green: 0.12, blue: 0.06, alpha: 1), roughness: 0.3, coat: 1, coatRoughness: 0.03)
        sides[color] = made
        return made
    }

    /// The board's light where the tile stands, relative to the middle of the board, where the
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
        float4x4 glassCamera = scn_frame.inverseViewTransform;
        float3 glassPoint = (glassCamera * float4(_surface.position, 1.0)).xyz;
        float2 glassSide = glassCamera[2].xz;
        glassSide = length(glassSide) > 0.0001 ? normalize(glassSide) : float2(0.0, 1.0);
        float3 glassKey = float3(\(key.x) * glassSide.y + \(key.z) * glassSide.x, \(key.y),
                                 \(-key.x) * glassSide.x + \(key.z) * glassSide.y);
        float3 glassToKey = glassKey - glassPoint;
        float glassDistance2 = dot(glassToKey, glassToKey);
        float3 glassL = glassToKey * rsqrt(glassDistance2);
        float glassCone = saturate((dot(-glassL, normalize(-glassKey)) - \(outer)) / \(inner - outer));
        float glassLight = \(even) + \(strength) * max(glassL.y, 0.0) * glassCone / glassDistance2;
        _output.color.rgb *= glassLight / \(middle);
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
    var glassLetter: String {
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
