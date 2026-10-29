import ChessKit
import SceneKit
import UIKit

/// The pieces for the flat board, seen from straight above: the familiar shapes cut solid from
/// the look's stone, on a fine foot of its metal, with their inner lines drawn on top (dark on
/// the ivory, metal on the ebony). Meshes made in Blender (scripts/sculpted/flat/build.py), read
/// like the carved sets.
enum SculptedFlatSet {
    /// The meshes' asset name.
    static let assetName = "flat-icon"

    /// A new piece in the look's finishes, or nil if the meshes are missing. A glass tile while
    /// the Crystal tiles are being compared (`SculptedCrystal.isOn`).
    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode? {
        if SculptedCrystal.isOn { return SculptedCrystal.makePiece(kind, color: color, look: look) }
        guard let parts = meshes?[kind] else { return nil }
        let key = "\(look.name)-\(color.rawValue)\(kind)"
        if let template = templates[key] { return template.clone() }
        let node = SCNNode()
        for part in parts {
            let geometry = part.geometry.copy() as? SCNGeometry ?? part.geometry
            geometry.materials = [material(part.finish, color: color, look: look)]
            let child = SCNNode(geometry: geometry)
            child.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(child)
        }
        templates[key] = node
        return node.clone()
    }

    /// How far the piece reaches from its square's center across the board, and how tall it
    /// is, in squares. Zero if the meshes are missing.
    static func extent(of kind: Piece.Kind) -> (reach: Float, height: Float) {
        if SculptedCrystal.isOn {
            let tile = SculptedCrystal.size(of: kind)
            return (Float(tile.width) / 2, Float(tile.height))
        }
        var reach: Float = 0, height: Float = 0
        for part in meshes?[kind] ?? [] {
            let (low, high) = part.geometry.boundingBox
            reach = max(reach, abs(low.x), abs(high.x), abs(low.z), abs(high.z))
            height = max(height, high.y)
        }
        return (reach, height)
    }

    /// The glow of the flat pieces' metal, which the fine line round the squares takes too in the
    /// flat view. From straight above the flat tops face the studio's dark ceiling
    /// (`SculptedLook.studioAbove`) and reflect little, so a brighter glow than the carved pieces'
    /// keeps the feet and lines gold, or platinum, rather than a dull brown or grey.
    static func glow(_ look: SculptedLook) -> UIColor {
        guard let glow = look.metalGlow else { return scaled(look.platinum, by: 0.5) }
        return scaled(glow, by: 1.6)
    }

    private static var loaded: [Piece.Kind: [SculptedAssets.Part]]?
    private static var templates: [String: SCNNode] = [:]
    private static var metals: [String: SCNMaterial] = [:]

    private static var meshes: [Piece.Kind: [SculptedAssets.Part]]? {
        if let set = loaded { return set }
        guard let set = SculptedAssets.loadMeshes(named: assetName), set.count == 6 else { return nil }
        loaded = set
        return set
    }

    /// The meshes name each part by a finish, read here as its role: the stone is the look's
    /// ivory or ebony and the metal its metal; "gem" is a line drawn on the piece, dark on the
    /// ivory and metal on the ebony.
    private static func material(_ finish: SculptedAssets.Finish, color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let assets = SculptedAssets.shared
        switch finish {
        case .metal where color == .white && look.ivoryMetal != nil:
            // The look marks its ivory pieces in a dark metal: so does the ivory's foot.
            return assets.material(.metal, for: .white, look: look)
        case .metal:
            return metal(look)
        case .gem:
            return color == .white ? assets.material(.body, for: .black, look: look) : metal(look)
        default:
            return assets.material(.body, for: color, look: look)
        }
    }

    /// The look's metal with the flat set's brighter glow.
    private static func metal(_ look: SculptedLook) -> SCNMaterial {
        if let made = metals[look.name] { return made }
        let made = SculptedAssets.pbr(look.platinum, roughness: look.metalRoughness, metalness: 1)
        made.emission.contents = glow(look)
        metals[look.name] = made
        return made
    }

    private static func scaled(_ color: UIColor, by factor: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: min(red * factor, 1), green: min(green * factor, 1), blue: min(blue * factor, 1), alpha: alpha)
    }
}
