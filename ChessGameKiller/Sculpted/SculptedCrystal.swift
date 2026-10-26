import ChessKit
import SceneKit
import UIKit

/// The Crystal set, for the flat board seen from above: each piece is a glass tile with the
/// piece etched into its top. White is clear glass with the piece inked dark; black is smoked
/// glass with the piece glowing gold. A gold plate sits under each tile.
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

        // Rounded well over: the bevels catch the light like cut glass.
        let tile = SCNNode(geometry: SCNBox(width: width, height: height, length: width, chamferRadius: 0.09))
        (tile.geometry as? SCNBox)?.chamferSegmentCount = 8
        tile.geometry?.materials = [glass(color)]
        tile.position = SCNVector3(0, Float(height / 2), 0)
        // Drawn after the etching, so the glass is seen over it.
        tile.renderingOrder = 12

        let plane = SCNPlane(width: width, height: width)
        plane.materials = [etching(kind, color: color)]
        let etch = SCNNode(geometry: plane)
        etch.eulerAngles.x = -.pi / 2
        // White's piece is inked into the top face. Black's glows from inside the smoked glass:
        // drawn after the glass, halfway down, so it shifts a little under the top as the board turns.
        etch.position = SCNVector3(0, Float(color == .white ? height + 0.002 : height * 0.5), 0)
        etch.renderingOrder = 14
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
            color == .white ? UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1) : UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1),
            roughness: 0.02, coat: 1, coatRoughness: 0.01)
        // See-through enough that the square shows under it, like glass.
        material.transparency = color == .white ? 0.45 : 0.72
        // Glass brightens and turns opaque toward its edges (Fresnel), which is what makes it read
        // as glass from above: bright rims and bevels round a clear middle.
        material.shaderModifiers = [.fragment: color == .white ? edgeLight(0.85, opacity: 0.9) : edgeLight(0.55, opacity: 0.95)]
        material.transparencyMode = .dualLayer
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        glasses[color] = material
        return material
    }

    /// Fresnel for the glass: toward grazing angles, the color lifts toward white and turns opaque.
    private static func edgeLight(_ strength: Double, opacity: Double) -> String {
        """
        float3 crystalN = normalize(_surface.normal);
        float3 crystalV = normalize(-_surface.position);
        float crystalEdge = pow(1.0 - saturate(abs(dot(crystalN, crystalV))), 2.5);
        float crystalLift = crystalEdge * \(strength);
        _output.color.rgb = _output.color.rgb + float3(crystalLift) * \(opacity);
        _output.color.a = max(_output.color.a, crystalEdge * \(opacity));
        """
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
            material.emission.intensity = 1.4
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
