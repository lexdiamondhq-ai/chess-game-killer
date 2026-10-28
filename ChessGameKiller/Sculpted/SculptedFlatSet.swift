import ChessKit
import SceneKit

/// The pieces for the flat board, seen from straight above: the familiar shapes cut solid from
/// the look's stone, on a fine foot of its metal, with their inner lines drawn on top (dark on
/// the ivory, metal on the ebony). Meshes made in Blender (scripts/sculpted/flat/build.py), read
/// like the carved sets.
enum SculptedFlatSet {
    /// The meshes' asset name.
    static let assetName = "flat-icon"

    /// A new piece in the look's finishes, or nil if the meshes are missing.
    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode? {
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
        var reach: Float = 0, height: Float = 0
        for part in meshes?[kind] ?? [] {
            let (low, high) = part.geometry.boundingBox
            reach = max(reach, abs(low.x), abs(high.x), abs(low.z), abs(high.z))
            height = max(height, high.y)
        }
        return (reach, height)
    }

    private static var loaded: [Piece.Kind: [SculptedAssets.Part]]?
    private static var templates: [String: SCNNode] = [:]

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
        case .metal:
            return assets.material(.metal, for: color, look: look)
        case .gem:
            return color == .white
                ? assets.material(.body, for: .black, look: look)
                : assets.material(.metal, for: .black, look: look)
        default:
            return assets.material(.body, for: color, look: look)
        }
    }
}
