import ChessKit
import SceneKit
import UIKit

/// The Crystal set, for the flat board seen from above: each piece is a glass tile with the
/// piece etched into its top. White is clear glass with the piece inked dark; black is smoked
/// glass with the piece glowing gold. A gold plate sits under each tile.
///
/// Brought back to compare with the Icon pieces under the flat view's new studio, whose dark
/// ceiling no longer turns the glass milky: shown only when the "flatPieces" default is "glass"
/// (`-flatPieces glass` on the command line), in the style "glassStyle" names (`Glass`).
///
/// Sizes are in squares, the tile's foot at the origin, y up, the top of the etching toward -z
/// (away from White), like the carved sets.
enum SculptedCrystal {
    /// Shown in place of the Icon pieces.
    static var isOn: Bool { UserDefaults.standard.string(forKey: "flatPieces") == "glass" }

    /// The glass style being compared: "a", "b" (the default) or "c" (`Glass.named`).
    private static var style: String { UserDefaults.standard.string(forKey: "glassStyle") ?? "b" }

    /// How a tile's glass is made: its body, how much of the square shows through, and the light
    /// its edges take on toward grazing angles (Fresnel), which is what reads as glass from above.
    private struct Glass {
        var body: UIColor
        var opacity: CGFloat
        var rim: Double
        var rimOpacity: Double
        var tint: SIMD3<Double> = SIMD3(1, 1, 1)
        /// A gold plate under the tile, as the first tiles had.
        var plate = false

        /// "a": the tiles as they were. "b": clear cool glass for White and amber glass for Black,
        /// like the render Alex first picked. "c": the same, a little more frosted.
        static func named(_ style: String, for color: Piece.Color) -> Glass {
            let white = color == .white
            let amber = SIMD3<Double>(1, 0.62, 0.25)
            switch style {
            case "a":
                return white
                    ? Glass(body: UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1), opacity: 0.45, rim: 0.85, rimOpacity: 0.9, plate: true)
                    : Glass(body: UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1), opacity: 0.72, rim: 0.55, rimOpacity: 0.95, plate: true)
            case "c":
                return white
                    ? Glass(body: UIColor(red: 0.88, green: 0.9, blue: 0.92, alpha: 1), opacity: 0.5, rim: 0.6, rimOpacity: 0.85)
                    : Glass(body: UIColor(red: 0.36, green: 0.2, blue: 0.07, alpha: 1), opacity: 0.72, rim: 0.45, rimOpacity: 0.9, tint: amber)
            default:
                return white
                    ? Glass(body: UIColor(red: 0.8, green: 0.82, blue: 0.85, alpha: 1), opacity: 0.3, rim: 0.5, rimOpacity: 0.85)
                    : Glass(body: UIColor(red: 0.32, green: 0.18, blue: 0.07, alpha: 1), opacity: 0.62, rim: 0.35, rimOpacity: 0.9, tint: amber)
            }
        }
    }

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

        var parts = [etch, tile]
        if Glass.named(style, for: color).plate {
            let plate = SCNNode(geometry: SCNBox(width: width - 0.02, height: 0.012, length: width - 0.02, chamferRadius: 0.05))
            plate.geometry?.materials = [SculptedAssets.shared.material(.metal, for: .black, look: look)]
            plate.position = SCNVector3(0, 0.006, 0)
            parts.insert(plate, at: 0)
        }
        for part in parts {
            part.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(part)
        }
        return node
    }

    private static var glasses: [String: SCNMaterial] = [:]
    private static var etchings: [String: SCNMaterial] = [:]

    private static func glass(_ color: Piece.Color) -> SCNMaterial {
        let chosen = style
        let key = "\(color.rawValue)\(chosen)"
        if let made = glasses[key] { return made }
        let recipe = Glass.named(chosen, for: color)
        let material = SculptedAssets.pbr(recipe.body, roughness: 0.02, coat: 1, coatRoughness: 0.01)
        // See-through enough that the square shows under it, like glass.
        material.transparency = recipe.opacity
        // Glass brightens and turns opaque toward its edges (Fresnel), which is what makes it read
        // as glass from above: bright rims and bevels round a clear middle.
        material.shaderModifiers = [.fragment: edgeLight(recipe.rim, opacity: recipe.rimOpacity, tint: recipe.tint)]
        material.transparencyMode = .dualLayer
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        glasses[key] = material
        return material
    }

    /// Fresnel for the glass: toward grazing angles, the color lifts toward the tint and turns opaque.
    private static func edgeLight(_ strength: Double, opacity: Double, tint: SIMD3<Double>) -> String {
        """
        float3 crystalN = normalize(_surface.normal);
        float3 crystalV = normalize(-_surface.position);
        float crystalEdge = pow(1.0 - saturate(abs(dot(crystalN, crystalV))), 2.5);
        float crystalLift = crystalEdge * \(strength);
        _output.color.rgb = _output.color.rgb + float3(\(tint.x), \(tint.y), \(tint.z)) * crystalLift * \(opacity);
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
