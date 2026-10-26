import ChessKit
import SceneKit
import UIKit

/// The Crystal set, for the flat board seen from above: each piece is a glass tile with the
/// piece etched inside. White is clear glass with the piece inked dark on top; black is smoked
/// glass with the piece glowing gold inside. A gold plate sits under each tile.
///
/// Sizes are in squares, the tile's foot at the origin, y up, the top of the etching toward -z
/// (away from White), like the carved sets.
enum SculptedCrystal {
    /// Width and height of a tile: the pawn's is smaller.
    static func size(of kind: Piece.Kind) -> (width: CGFloat, height: CGFloat) {
        kind == .pawn ? (0.62, 0.2) : (0.78, 0.26)
    }

    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode {
        let (width, height) = size(of: kind)
        let node = SCNNode()

        let tile = SCNNode(geometry: SCNBox(width: width, height: height, length: width, chamferRadius: 0.07))
        tile.geometry?.materials = [glass(color)]
        tile.position = SCNVector3(0, Float(height / 2), 0)
        // Drawn after the etching, so the glass is seen over it.
        tile.renderingOrder = 12

        let plane = SCNPlane(width: width, height: width)
        plane.materials = [etching(kind, color: color)]
        let etch = SCNNode(geometry: plane)
        etch.eulerAngles.x = -.pi / 2
        // White's ink sits on the top face; black's glows from inside the smoke.
        etch.position = SCNVector3(0, Float(color == .white ? height + 0.002 : height * 0.55), 0)
        etch.renderingOrder = color == .white ? 14 : 10
        etch.castsShadow = false

        let plate = SCNNode(geometry: SCNBox(width: width - 0.02, height: 0.012, length: width - 0.02, chamferRadius: 0.05))
        plate.geometry?.materials = [SculptedAssets.shared.material(.metal, for: .black, look: look)]
        plate.position = SCNVector3(0, 0.006, 0)

        for part in [plate, etch, tile] {
            part.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(part)
        }
        return node
    }

    private static var glasses: [Piece.Color: SCNMaterial] = [:]
    private static var etchings: [String: SCNMaterial] = [:]

    private static func glass(_ color: Piece.Color) -> SCNMaterial {
        if let made = glasses[color] { return made }
        let material = SculptedAssets.pbr(
            color == .white ? UIColor(white: 0.97, alpha: 1) : UIColor(red: 0.2, green: 0.185, blue: 0.17, alpha: 1),
            roughness: 0.06, coat: 1, coatRoughness: 0.03)
        material.transparency = color == .white ? 0.72 : 0.86
        material.transparencyMode = .dualLayer
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        glasses[color] = material
        return material
    }

    private static func etching(_ kind: Piece.Kind, color: Piece.Color) -> SCNMaterial {
        let key = "\(color.rawValue)\(kind)"
        if let made = etchings[key] { return made }
        let mask = UIImage(named: "crystal-\(kind.crystalLetter)")
        let material: SCNMaterial
        if color == .white {
            material = SculptedAssets.pbr(UIColor(red: 0.118, green: 0.086, blue: 0.07, alpha: 1), roughness: 0.6)
        } else {
            let gold = UIColor(red: 0.95, green: 0.78, blue: 0.47, alpha: 1)
            material = SculptedAssets.pbr(gold, roughness: 0.3, metalness: 1)
            material.emission.contents = gold
            material.emission.intensity = 0.7
        }
        material.transparent.contents = mask
        material.transparencyMode = .aOne
        material.isDoubleSided = false
        etchings[key] = material
        return material
    }
}

private extension Piece.Kind {
    /// The letter the etching pictures are named by.
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
