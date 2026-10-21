import ChessKit
import SceneKit
import UIKit

/// The sculpted set made in Blender: six meshes, their finishes, the stone squares and the
/// studio light. Loaded once and shared by every 3D board.
///
/// The meshes come from `sculpted-pieces` in the asset catalog, written by the Blender export
/// script in scripts/sculpted. Sizes are in squares,
/// with y up, the piece's foot at the origin and black's side of the board toward -z.
final class SculptedAssets {
    static let shared = SculptedAssets()

    /// What a part of a piece is made of.
    enum Finish: UInt8 {
        case body = 0, metal = 1, gem = 2, pearl = 3
    }

    struct Part {
        let finish: Finish
        let geometry: SCNGeometry
    }

    /// Each kind's parts: the turned body, then its platinum, sapphires and pearls.
    let parts: [Piece.Kind: [Part]]
    /// How tall each kind stands, in squares.
    let heights: [Piece.Kind: Float]

    private var templates: [String: SCNNode] = [:]
    private var materials: [String: SCNMaterial] = [:]

    init(assetName: String = "sculpted-pieces") {
        parts = Self.loadMeshes(named: assetName) ?? [:]
        var heights: [Piece.Kind: Float] = [:]
        for (kind, list) in parts {
            heights[kind] = list.map { Float($0.geometry.boundingBox.max.y) }.max() ?? 1
        }
        self.heights = heights
    }

    /// True when all six pieces loaded. The board falls back to the flat look otherwise.
    var isLoaded: Bool { parts.count == 6 }

    func height(of kind: Piece.Kind) -> Float {
        heights[kind] ?? 1
    }

    /// A new piece: one child node per part, sharing geometry and materials with every
    /// other piece of the same kind and color.
    func makePiece(_ kind: Piece.Kind, color: Piece.Color) -> SCNNode {
        let key = "\(color.rawValue)\(kind)"
        if let template = templates[key] { return template.clone() }
        let node = SCNNode()
        for part in parts[kind] ?? [] {
            guard let geometry = part.geometry.copy() as? SCNGeometry else { continue }
            geometry.materials = [material(part.finish, for: color)]
            let child = SCNNode(geometry: geometry)
            child.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(child)
        }
        templates[key] = node
        return node.clone()
    }

    // MARK: Finishes

    /// Ivory or ebony for the body; platinum, sapphire and pearl are the same on both sides.
    func material(_ finish: Finish, for color: Piece.Color) -> SCNMaterial {
        let key = finish == .body ? "body-\(color.rawValue)" : "\(finish)"
        if let cached = materials[key] { return cached }
        let look = SculptedLook.current
        let made: SCNMaterial
        switch finish {
        case .body where color == .white:
            made = Self.pbr(look.ivory, roughness: 0.34, coat: 0.35, coatRoughness: 0.08)
        case .body:
            made = Self.pbr(look.ebony, roughness: 0.36, coat: 0.45, coatRoughness: 0.2)
        case .metal:
            made = Self.pbr(look.platinum, roughness: 0.16, metalness: 1)
        case .gem:
            made = Self.pbr(look.sapphire, roughness: 0.06, metalness: 0.35, coat: 1, coatRoughness: 0.02)
        case .pearl:
            made = Self.pbr(look.pearl, roughness: 0.2, coat: 1, coatRoughness: 0.05)
        }
        materials[key] = made
        return made
    }

    /// The stone squares: the baked marble with a polished coat.
    func squaresMaterial() -> SCNMaterial {
        let material = Self.pbr(.white, roughness: 0.24, coat: 0.45, coatRoughness: 0.05)
        material.diffuse.contents = UIImage(named: "sculpted-squares") ?? UIColor(white: 0.45, alpha: 1)
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 8
        return material
    }

    /// The black lacquered frame.
    func frameMaterial() -> SCNMaterial {
        Self.pbr(SculptedLook.current.lacquer, roughness: 0.42, coat: 0.18, coatRoughness: 0.12)
    }

    /// The studio light the pieces reflect: a soft light tent, the same from every side.
    var environment: UIImage? { UIImage(named: "sculpted-env") }

    static func pbr(
        _ color: UIColor, roughness: CGFloat, metalness: CGFloat = 0, coat: CGFloat = 0, coatRoughness: CGFloat = 0.05
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = NSNumber(value: Double(roughness))
        material.metalness.contents = NSNumber(value: Double(metalness))
        if coat > 0 {
            material.clearCoat.contents = NSNumber(value: Double(coat))
            material.clearCoatRoughness.contents = NSNumber(value: Double(coatRoughness))
        }
        return material
    }

    // MARK: Loading

    /// Reads the export: "SCLP", version 1, the number of pieces; for each piece its letter and
    /// part count; for each part its finish, vertex and index counts, then positions, normals
    /// (three floats each) and triangle indices (UInt32). The whole file is raw-deflated.
    static func loadMeshes(named name: String) -> [Piece.Kind: [Part]]? {
        guard let asset = NSDataAsset(name: name),
              let data = try? (asset.data as NSData).decompressed(using: .zlib) as Data
        else { return nil }
        var reader = ByteReader(data: data)
        guard reader.bytes(4) == Data("SCLP".utf8), reader.uint32() == 1 else { return nil }
        let count = Int(reader.uint32())
        var result: [Piece.Kind: [Part]] = [:]
        for _ in 0..<count {
            let letter = reader.uint8()
            let partCount = Int(reader.uint8())
            reader.skip(2)
            var list: [Part] = []
            for _ in 0..<partCount {
                let finish = Finish(rawValue: reader.uint8()) ?? .body
                reader.skip(3)
                let vertexCount = Int(reader.uint32())
                let indexCount = Int(reader.uint32())
                let positions = reader.bytes(vertexCount * 12)
                let normals = reader.bytes(vertexCount * 12)
                let indices = reader.bytes(indexCount * 4)
                guard !reader.overran, vertexCount > 0, indexCount >= 3 else { return nil }
                let geometry = SCNGeometry(
                    sources: [
                        SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: vertexCount,
                                          usesFloatComponents: true, componentsPerVector: 3,
                                          bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                        SCNGeometrySource(data: normals, semantic: .normal, vectorCount: vertexCount,
                                          usesFloatComponents: true, componentsPerVector: 3,
                                          bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                    ],
                    elements: [
                        SCNGeometryElement(data: indices, primitiveType: .triangles,
                                           primitiveCount: indexCount / 3, bytesPerIndex: 4),
                    ]
                )
                list.append(Part(finish: finish, geometry: geometry))
            }
            if let kind = kind(letter: letter) { result[kind] = list }
        }
        return result
    }

    private static func kind(letter: UInt8) -> Piece.Kind? {
        switch letter {
        case UInt8(ascii: "K"): return .king
        case UInt8(ascii: "Q"): return .queen
        case UInt8(ascii: "R"): return .rook
        case UInt8(ascii: "B"): return .bishop
        case UInt8(ascii: "N"): return .knight
        case UInt8(ascii: "P"): return .pawn
        default: return nil
        }
    }
}

/// Reads little-endian numbers and byte runs from the front of a buffer.
private struct ByteReader {
    let data: Data
    private var offset = 0
    private(set) var overran = false

    init(data: Data) {
        self.data = data
    }

    mutating func bytes(_ count: Int) -> Data {
        guard count >= 0, offset + count <= data.count else {
            overran = true
            return Data()
        }
        let start = data.startIndex + offset
        offset += count
        return data.subdata(in: start..<(start + count))
    }

    mutating func skip(_ count: Int) {
        _ = bytes(count)
    }

    mutating func uint8() -> UInt8 {
        bytes(1).first ?? 0
    }

    mutating func uint32() -> UInt32 {
        let run = bytes(4)
        guard run.count == 4 else { return 0 }
        return run.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }
}

/// The colors and light levels of the sculpted board. One place, so the look is tuned together.
struct SculptedLook {
    static var current = SculptedLook()

    var ivory = UIColor(red: 0.925, green: 0.9, blue: 0.85, alpha: 1)
    var ebony = UIColor(red: 0.15, green: 0.143, blue: 0.138, alpha: 1)
    var platinum = UIColor(red: 0.93, green: 0.93, blue: 0.945, alpha: 1)
    var sapphire = UIColor(red: 0.12, green: 0.26, blue: 0.8, alpha: 1)
    var pearl = UIColor(red: 0.965, green: 0.95, blue: 0.93, alpha: 1)
    var lacquer = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)

    /// How bright the studio tent is, and the key light that casts the shadows.
    var environment: CGFloat = 1.5
    var key: CGFloat = 900
    var rim: CGFloat = 250

    /// The marks drawn on the stone: legal moves, best-move arrows.
    var accent = UIColor(red: 0.37, green: 0.56, blue: 1.0, alpha: 1)
    var check = UIColor(red: 1.0, green: 0.23, blue: 0.3, alpha: 1)
    var platinumMark = UIColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1)
}
