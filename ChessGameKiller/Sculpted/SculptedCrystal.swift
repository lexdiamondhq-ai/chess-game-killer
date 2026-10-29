import ChessKit
import SceneKit
import UIKit
import simd

/// The Crystal set, for the flat board seen from above: each piece a glass tile with the piece
/// etched into it. White is milky glass with the piece inked dark on top; Black is smoked glass
/// with the piece glowing gold inside; a gold foot under both.
///
/// SceneKit can't draw glass like the concept render Alex picked (design/flat-pieces/crystal.jpg):
/// tried as see-through glass it came out plain white. So each tile shows that render's own glass:
/// a picture of it drawn in Cycles from the flat view's angle (scripts/sculpted/flat/glass.py),
/// laid on a plain tile that casts the shadow, and lit to follow the board's light (`light`).
///
/// Shown in place of the Icon pieces only when the "flatPieces" default is "glass"
/// (`-flatPieces glass` on the command line), while the two are compared.
///
/// Sizes are in squares, the tile's foot at the origin, y up, the top of the piece toward -z
/// (away from White), like the carved sets.
enum SculptedCrystal {
    /// Shown in place of the Icon pieces.
    static var isOn: Bool { UserDefaults.standard.string(forKey: "flatPieces") == "glass" }

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

    /// The picture's name in the asset catalog.
    static func pictureName(_ kind: Piece.Kind, color: Piece.Color) -> String {
        "glass-\(color == .white ? "w" : "b")\(kind.crystalLetter)"
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
        float4x4 crystalCamera = scn_frame.inverseViewTransform;
        float3 crystalPoint = (crystalCamera * float4(_surface.position, 1.0)).xyz;
        float2 crystalSide = crystalCamera[2].xz;
        crystalSide = length(crystalSide) > 0.0001 ? normalize(crystalSide) : float2(0.0, 1.0);
        float3 crystalKey = float3(\(key.x) * crystalSide.y + \(key.z) * crystalSide.x, \(key.y),
                                   \(-key.x) * crystalSide.x + \(key.z) * crystalSide.y);
        float3 crystalToKey = crystalKey - crystalPoint;
        float crystalDistance2 = dot(crystalToKey, crystalToKey);
        float3 crystalL = crystalToKey * rsqrt(crystalDistance2);
        float crystalCone = saturate((dot(-crystalL, normalize(-crystalKey)) - \(outer)) / \(inner - outer));
        float crystalLight = \(even) + \(strength) * max(crystalL.y, 0.0) * crystalCone / crystalDistance2;
        _output.color.rgb *= crystalLight / \(middle);
        """
    }
}

private extension Piece.Kind {
    /// The letter the pictures are named by.
    var crystalLetter: String {
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
