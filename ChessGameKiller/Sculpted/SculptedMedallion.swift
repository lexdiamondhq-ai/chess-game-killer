import ChessKit
import SceneKit
import UIKit

/// The Medallion set, for the flat board seen from above: each piece is a thick coin with a
/// gold rim and the piece raised in relief on its face. White's coins are ivory with the piece
/// in dark brown; Black's are ebony with the piece in gold.
///
/// Sizes are in squares, the coin's foot at the origin, y up, the top of the picture toward -z
/// (away from White), like the carved sets.
enum SculptedMedallion {
    /// The coin's radius and thickness: the king's is the largest, the pawn's the smallest.
    static func size(of kind: Piece.Kind) -> (radius: CGFloat, height: CGFloat) {
        switch kind {
        case .king: return (0.40, 0.13)
        case .queen: return (0.39, 0.13)
        case .rook, .bishop, .knight: return (0.36, 0.13)
        case .pawn: return (0.31, 0.10)
        }
    }

    static let rimWidth: CGFloat = 0.04

    static func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode {
        let (radius, height) = size(of: kind)
        let gold = SculptedAssets.shared.material(.metal, for: .black, look: look)
        let node = SCNNode()

        let coin = SCNNode(geometry: SCNCylinder(radius: radius, height: height))
        coin.geometry?.materials = [body(color)]
        coin.position = SCNVector3(0, Float(height / 2), 0)

        let rim = SCNNode(geometry: SCNTube(innerRadius: radius - rimWidth, outerRadius: radius + 0.004, height: 0.026))
        rim.geometry?.materials = [gold]
        rim.position = SCNVector3(0, Float(height + 0.004), 0)

        let side = 2 * (radius - rimWidth)
        let plane = SCNPlane(width: side, height: side)
        plane.cornerRadius = side / 2
        plane.materials = [face(kind, color: color)]
        let face = SCNNode(geometry: plane)
        face.eulerAngles.x = -.pi / 2
        face.position = SCNVector3(0, Float(height + 0.001), 0)

        for part in [coin, rim, face] {
            part.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(part)
        }
        return node
    }

    private static var bodies: [Piece.Color: SCNMaterial] = [:]
    private static var faces: [String: SCNMaterial] = [:]

    private static let ivory = UIColor(red: 0.957, green: 0.925, blue: 0.867, alpha: 1)
    private static let ebony = UIColor(red: 0.09, green: 0.075, blue: 0.06, alpha: 1)
    private static let brownInk = UIColor(red: 0.165, green: 0.114, blue: 0.078, alpha: 1)
    private static let goldInk = UIColor(red: 0.886, green: 0.714, blue: 0.361, alpha: 1)

    private static func body(_ color: Piece.Color) -> SCNMaterial {
        if let made = bodies[color] { return made }
        let material = SculptedAssets.pbr(color == .white ? ivory : ebony,
                                          roughness: color == .white ? 0.3 : 0.28, coat: 0.6, coatRoughness: 0.12)
        bodies[color] = material
        return material
    }

    /// The coin's face: the piece in ink on the body color, raised by a normal map; Black's ink is metal.
    private static func face(_ kind: Piece.Kind, color: Piece.Color) -> SCNMaterial {
        let key = "\(color.rawValue)\(kind)"
        if let made = faces[key] { return made }
        let letter = kind.medallionLetter
        let mask = UIImage(named: "medallion-mask-\(letter)")
        let base = color == .white ? ivory : ebony
        let ink = color == .white ? brownInk : goldInk
        let material = SculptedAssets.pbr(base, roughness: 0.3, coat: 0.6, coatRoughness: 0.12)
        material.diffuse.contents = mask.map { painted($0, base: base, ink: ink) } ?? base
        material.normal.contents = UIImage(named: "medallion-normal-\(letter)")
        // Black's piece is gold metal; the ebony around it is not.
        if color == .black, let mask { material.metalness.contents = painted(mask, base: .black, ink: .white) }
        faces[key] = material
        return material
    }

    /// The body color with the ink laid where the mask is drawn.
    private static func painted(_ mask: UIImage, base: UIColor, ink: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rect = CGRect(origin: .zero, size: mask.size)
        return UIGraphicsImageRenderer(size: mask.size, format: format).image { _ in
            base.setFill()
            UIRectFill(rect)
            mask.withTintColor(ink, renderingMode: .alwaysOriginal).draw(in: rect)
        }
    }
}

private extension Piece.Kind {
    /// The letter the face pictures are named by.
    var medallionLetter: String {
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
