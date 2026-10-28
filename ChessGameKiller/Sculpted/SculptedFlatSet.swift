import ChessKit
import SceneKit
import UIKit

/// The piece designs for the flat board, seen from straight above. Crystal is built in code
/// (SculptedCrystal.swift); the others are meshes made in Blender (scripts/sculpted/flat),
/// read like the carved sets and dressed in the look's own stone and metal.
enum FlatPieceStyle: String, CaseIterable, Identifiable {
    /// Glass tiles with the piece etched in them.
    case crystal
    /// The familiar piece, cut solid from the look's stone on a fine metal foot.
    case icon
    /// Each piece as its emblem: a cross, a coronet, a tower, a mitre, a horseshoe, an orb.
    case regalia
    /// Each piece a different cut of jewel, set in metal.
    case gem
    /// Domed stones with metal rays for the way each piece moves.
    case rose

    static let storageKey = "flatPieces"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crystal: return "Crystal"
        case .icon: return "Icon"
        case .regalia: return "Regalia"
        case .gem: return "Gem Cut"
        case .rose: return "Compass Rose"
        }
    }

    /// The meshes' asset name; Crystal has none.
    var assetName: String? { self == .crystal ? nil : "flat-\(rawValue)" }
}

enum SculptedFlatSet {
    /// A new piece in `style`: Crystal's tile, or the style's mesh in the look's finishes.
    /// A style whose meshes are missing falls back to Crystal.
    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook, style: FlatPieceStyle) -> SCNNode {
        guard let parts = meshes(style)?[kind] else {
            return SculptedCrystal.makePiece(kind, color: color, look: look)
        }
        let key = "\(style.rawValue)-\(look.name)-\(color.rawValue)\(kind)"
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
    /// is, in squares.
    static func extent(of kind: Piece.Kind, style: FlatPieceStyle) -> (reach: Float, height: Float) {
        guard let parts = meshes(style)?[kind] else {
            let (width, height) = SculptedCrystal.size(of: kind)
            return (Float(width) / 2, Float(height))
        }
        var reach: Float = 0, height: Float = 0
        for part in parts {
            let (low, high) = part.geometry.boundingBox
            reach = max(reach, abs(low.x), abs(high.x), abs(low.z), abs(high.z))
            height = max(height, high.y)
        }
        return (reach, height)
    }

    private static var sets: [FlatPieceStyle: [Piece.Kind: [SculptedAssets.Part]]] = [:]
    private static var templates: [String: SCNNode] = [:]
    private static var jewels: [Piece.Color: SCNMaterial] = [:]

    private static func meshes(_ style: FlatPieceStyle) -> [Piece.Kind: [SculptedAssets.Part]]? {
        if let set = sets[style] { return set }
        guard let name = style.assetName, let set = SculptedAssets.loadMeshes(named: name), set.count == 6 else {
            return nil
        }
        sets[style] = set
        return set
    }

    /// The meshes name each part by a finish, read here as its role: the stone is the look's
    /// ivory or ebony and the metal its metal; "gem" is a line drawn on the piece (dark on
    /// ivory, metal on ebony) and "pearl" a cut jewel.
    private static func material(_ finish: SculptedAssets.Finish, color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let assets = SculptedAssets.shared
        switch finish {
        case .metal:
            return assets.material(.metal, for: color, look: look)
        case .gem:
            return color == .white
                ? assets.material(.body, for: .black, look: look)
                : assets.material(.metal, for: .black, look: look)
        case .pearl:
            return jewel(color)
        default:
            return assets.material(.body, for: color, look: look)
        }
    }

    /// Polished facets: a bright white stone and a black one. Each facet catches a different
    /// part of the studio, which is what makes a cut stone sparkle without any refraction.
    private static func jewel(_ color: Piece.Color) -> SCNMaterial {
        if let made = jewels[color] { return made }
        let made = color == .white
            ? SculptedAssets.pbr(UIColor(white: 0.94, alpha: 1), roughness: 0.03, metalness: 0.3, coat: 1, coatRoughness: 0.01)
            : SculptedAssets.pbr(UIColor(white: 0.035, alpha: 1), roughness: 0.03, metalness: 0.45, coat: 1, coatRoughness: 0.01)
        jewels[color] = made
        return made
    }
}
