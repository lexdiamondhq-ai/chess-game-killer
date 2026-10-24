import ChessKit
import SceneKit
import UIKit

/// The Heirloom Set on the 3D board: a piece's history on the carved piece itself. The seams and
/// the patina are painted into the body's own surface by a shader, so they follow every curve;
/// the collar and the notches are small gold parts added to the piece.
extension SculptedAssets {
    /// Satin gold, with a faint glow so it reads in the dark studio.
    static let heirloomGold = UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 1)

    /// The body's finish with the piece's patina and seams worked in. Made once per look, side,
    /// kind and history, then shared.
    func heirloomMaterial(_ heirloom: Heirloom, kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let patina = (heirloom.patina * 10).rounded() / 10
        let key = "\(look.name)-heirloom-\(color.rawValue)\(kind)-\(heirloom.seams)-\(heirloom.seed)-\(patina)"
        if let cached = heirloomMaterials[key] { return cached }
        let body = material(.body, for: color, look: look)
        guard let made = body.copy() as? SCNMaterial else { return body }
        let existing = body.shaderModifiers?[.surface] ?? ""
        made.shaderModifiers = [.surface: existing + "\n" + Self.heirloomShader(heirloom, height: height(of: kind),
                                                                                  ivory: color == .white, patina: patina)]
        heirloomMaterials[key] = made
        return made
    }

    /// Metal for the surface: the patina, then each seam: a crack that winds down the body,
    /// worked out from the point's height and angle around the piece in its own coordinates.
    static func heirloomShader(_ heirloom: Heirloom, height: Float, ivory: Bool, patina: Double) -> String {
        var random = SeededRandom(seed: UInt64(heirloom.seed * 7919 + 17))
        var seams = ""
        for index in 0..<heirloom.seams {
            let phase = Float(index) * 2.1 + Float(random.next()) * 0.9 - 0.45
            let s1 = Float(random.next()) * 6.28, s2 = Float(random.next()) * 6.28
            let y0 = height * Float(0.12 + random.next() * 0.1)
            let y1 = height * Float(0.6 + random.next() * 0.15)
            seams += """
            {
                float c = \(phase) + 0.45 * sin(hp.y * 9.0 + \(s1)) + 0.18 * sin(hp.y * 23.0 + \(s2));
                float d = abs(atan2(sin(th - c), cos(th - c))) * rr;
                float inside = smoothstep(\(y0), \(y0 + 0.04), hp.y) * (1.0 - smoothstep(\(y1 - 0.04), \(y1), hp.y));
                seam = max(seam, inside * (1.0 - smoothstep(0.0045, 0.0085, d)));
            }

            """
        }
        let tint = ivory ? "float3(1.0, \(1 - 0.1 * patina), \(1 - 0.24 * patina))" : "float3(1.0)"
        let sheen = ivory ? "float3(0.0)" : "float3(\(0.05 * patina), \(0.03 * patina), \(0.012 * patina))"
        return """
        float3 hp = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        float th = atan2(hp.x, hp.z);
        float rr = length(hp.xz);
        float seam = 0.0;
        \(seams)
        _surface.diffuse.rgb = _surface.diffuse.rgb * \(tint) + \(sheen);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(1.0, 0.78, 0.4), seam);
        _surface.metalness = mix(_surface.metalness, 1.0, seam);
        _surface.roughness = mix(_surface.roughness, 0.28, seam);
        _surface.emission.rgb += float3(0.35, 0.24, 0.08) * seam;
        """
    }

    /// The widest the body is between two heights (the base's rim near the floor), and the height
    /// where it is narrowest between two others (a pawn's neck), read from the mesh once.
    func silhouette(of kind: Piece.Kind, look: SculptedLook) -> PieceSilhouette {
        let key = "\(look.pieces)-\(kind)"
        if let known = silhouettes[key] { return known }
        var points: [SIMD3<Float>] = []
        for part in parts(for: look)[kind] ?? [] where part.finish == .body {
            points += Self.vertices(of: part.geometry)
        }
        let height = height(of: kind)
        func radius(_ p: SIMD3<Float>) -> Float { (p.x * p.x + p.z * p.z).squareRoot() }
        let base = points.filter { $0.y > 0.02 && $0.y < 0.05 }.map(radius).max() ?? 0.3
        var neck = (y: height * 0.6, r: Float(0.1))
        let bands = 40
        for band in 0..<bands {
            let y = height * (0.5 + 0.18 * Float(band) / Float(bands))
            let near = points.filter { abs($0.y - y) < height / 120 }
            guard let widest = near.map(radius).max() else { continue }
            if widest < neck.r || band == 0 { neck = (y: y, r: widest) }
        }
        let made = PieceSilhouette(baseRadius: base, neckHeight: neck.y, neckRadius: neck.r)
        silhouettes[key] = made
        return made
    }

    private static func vertices(of geometry: SCNGeometry) -> [SIMD3<Float>] {
        guard let source = geometry.sources(for: .vertex).first, source.usesFloatComponents,
              source.bytesPerComponent == 4, source.componentsPerVector >= 3 else { return [] }
        let count = source.vectorCount, start = source.dataOffset, stride = source.dataStride
        return source.data.withUnsafeBytes { raw -> [SIMD3<Float>] in
            (0..<count).map { index in
                let offset = start + index * stride
                return SIMD3<Float>(raw.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                    raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                    raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
            }
        }
    }

    /// A gold collar for a promoted pawn's neck, and gold notches along the front of the base.
    func heirloomParts(_ heirloom: Heirloom, kind: Piece.Kind, look: SculptedLook) -> [SCNNode] {
        let shape = silhouette(of: kind, look: look)
        let gold = Self.pbr(Self.heirloomGold, roughness: 0.28, metalness: 1)
        gold.emission.contents = UIColor(red: 0.3, green: 0.2, blue: 0.06, alpha: 1)
        var made: [SCNNode] = []
        if heirloom.collar {
            let ring = SCNTorus(ringRadius: CGFloat(shape.neckRadius + 0.004), pipeRadius: 0.014)
            ring.ringSegmentCount = 64
            ring.pipeSegmentCount = 16
            ring.materials = [gold]
            let node = SCNNode(geometry: ring)
            node.simdPosition = SIMD3(0, shape.neckHeight, 0)
            made.append(node)
        }
        if heirloom.notches > 0 {
            let stud = SCNSphere(radius: 0.012)
            stud.segmentCount = 16
            stud.materials = [gold]
            let step: Float = 0.17
            for index in 0..<heirloom.notches {
                // Around the front of the base (+z faces the player), spread evenly about the middle.
                let angle = (Float(index) - Float(heirloom.notches - 1) / 2) * step
                let node = SCNNode(geometry: stud)
                let r = shape.baseRadius - 0.002
                node.simdPosition = SIMD3(r * sin(angle), 0.034, r * cos(angle))
                node.simdScale = SIMD3(0.8, 1.5, 0.8)
                made.append(node)
            }
        }
        for node in made {
            node.categoryBitMask = SculptedBoardScene.pieceCategory
            node.name = "heirloom"
        }
        return made
    }
}

/// The few measurements of a carved piece that the Heirloom parts are placed by.
struct PieceSilhouette {
    let baseRadius: Float
    let neckHeight: Float
    let neckRadius: Float
}
