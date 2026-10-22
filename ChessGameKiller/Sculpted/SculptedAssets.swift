import ChessKit
import SceneKit
import UIKit

/// The sets made in Blender: six meshes each, their finishes, the stone squares and the
/// studio light. Loaded once and shared by every 3D board; each look's finishes are made the
/// first time a board in that look is drawn.
///
/// The meshes come from the asset catalog, written by the Blender export script in
/// scripts/sculpted: `sculpted-pieces` is the classic carved set, and a look can name another
/// (the black-and-gold gilded set), loaded the first time a board in that look is drawn. Sizes are in squares,
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

    /// Each kind's parts in the classic set: the turned body, then its platinum, sapphires and pearls.
    let parts: [Piece.Kind: [Part]]
    /// How tall each kind stands, in squares. The sets share their heights.
    let heights: [Piece.Kind: Float]

    /// Every set loaded so far, by asset name.
    private var sets: [String: [Piece.Kind: [Part]]] = [:]
    private var templates: [String: SCNNode] = [:]
    private var materials: [String: SCNMaterial] = [:]

    init(assetName: String = "sculpted-pieces") {
        let parts = Self.loadMeshes(named: assetName) ?? [:]
        var heights: [Piece.Kind: Float] = [:]
        for (kind, list) in parts {
            heights[kind] = list.map { Float($0.geometry.boundingBox.max.y) }.max() ?? 1
        }
        self.parts = parts
        self.heights = heights
        sets[assetName] = parts
    }

    /// True when all six pieces loaded. The board falls back to the flat look otherwise.
    var isLoaded: Bool { parts.count == 6 }

    /// The set a look plays with. A set that is missing or incomplete falls back to the classic one.
    func parts(for look: SculptedLook) -> [Piece.Kind: [Part]] {
        if let set = sets[look.pieces] { return set }
        let loaded = Self.loadMeshes(named: look.pieces).flatMap { $0.count == 6 ? $0 : nil } ?? parts
        sets[look.pieces] = loaded
        return loaded
    }

    func height(of kind: Piece.Kind) -> Float {
        heights[kind] ?? 1
    }

    /// A new piece: one child node per part, sharing geometry and materials with every
    /// other piece of the same kind, color and look.
    func makePiece(_ kind: Piece.Kind, color: Piece.Color, look: SculptedLook) -> SCNNode {
        let key = "\(look.name)-\(color.rawValue)\(kind)"
        if let template = templates[key] { return template.clone() }
        let node = SCNNode()
        for part in parts(for: look)[kind] ?? [] {
            guard let geometry = part.geometry.copy() as? SCNGeometry else { continue }
            geometry.materials = [material(part.finish, for: color, look: look)]
            let child = SCNNode(geometry: geometry)
            child.categoryBitMask = SculptedBoardScene.pieceCategory
            node.addChildNode(child)
        }
        templates[key] = node
        return node.clone()
    }

    // MARK: Finishes

    /// Ivory or ebony for the body; the metal, gems and pearls are the same on both sides.
    func material(_ finish: Finish, for color: Piece.Color, look: SculptedLook) -> SCNMaterial {
        let key = "\(look.name)-" + (finish == .body ? "body-\(color.rawValue)" : "\(finish)")
        if let cached = materials[key] { return cached }
        let made: SCNMaterial
        switch finish {
        case .body where color == .white:
            made = Self.pbr(look.ivory, polish: look.ivoryPolish)
        case .body:
            made = Self.pbr(look.ebony, polish: look.ebonyPolish)
        case .metal:
            made = Self.pbr(look.platinum, roughness: look.metalRoughness, metalness: 1)
        case .gem:
            made = Self.pbr(look.sapphire, roughness: 0.06, metalness: 0.35, coat: 1, coatRoughness: 0.02)
            if let glow = look.gemGlow { made.emission.contents = glow }
        case .pearl:
            made = Self.pbr(look.pearl, roughness: 0.2, coat: 1, coatRoughness: 0.05)
        }
        materials[key] = made
        return made
    }

    /// The stone squares: the baked marble with a polished coat.
    func squaresMaterial(_ look: SculptedLook) -> SCNMaterial {
        let material = Self.pbr(.white, roughness: look.stoneRoughness, coat: look.stoneCoat, coatRoughness: 0.05)
        material.diffuse.contents = UIImage(named: look.squares) ?? UIColor(white: 0.45, alpha: 1)
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 8
        return material
    }

    /// The black lacquered frame.
    func frameMaterial(_ look: SculptedLook) -> SCNMaterial {
        return Self.pbr(look.lacquer, roughness: look.lacquerRoughness, coat: look.lacquerCoat, coatRoughness: 0.08)
    }

    /// The fine metal line around the squares: platinum, or the look's own metal.
    func inlayMaterial(_ look: SculptedLook) -> SCNMaterial {
        guard let inlay = look.inlay else { return material(.metal, for: .white, look: look) }
        return Self.pbr(inlay, roughness: 0.2, metalness: 1)
    }

    /// The studio light the pieces reflect, the same from every side.
    func environment(_ look: SculptedLook) -> UIImage? { UIImage(named: look.studio) }

    static func pbr(_ color: UIColor, polish: SculptedLook.Polish) -> SCNMaterial {
        pbr(color, roughness: polish.roughness, coat: polish.coat, coatRoughness: polish.coatRoughness)
    }

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
    /// How a stone is finished: its roughness, and the clear coat over it.
    struct Polish {
        var roughness: CGFloat
        var coat: CGFloat
        var coatRoughness: CGFloat
    }

    /// Also the key its finishes are cached under, so every look needs its own.
    var name = "Sculpted"
    /// The piece meshes in the asset catalog: the classic carved set unless the look has its own.
    var pieces = "sculpted-pieces"
    /// The baked stone squares in the asset catalog.
    var squares = "sculpted-squares"
    var stoneRoughness: CGFloat = 0.24
    var stoneCoat: CGFloat = 0.45

    var ivory = UIColor(red: 0.925, green: 0.9, blue: 0.85, alpha: 1)
    var ebony = UIColor(red: 0.15, green: 0.143, blue: 0.138, alpha: 1)
    var ivoryPolish = Polish(roughness: 0.34, coat: 0.35, coatRoughness: 0.08)
    var ebonyPolish = Polish(roughness: 0.36, coat: 0.45, coatRoughness: 0.2)
    /// The pieces' metal: platinum on most looks, gold on the gilded set.
    var platinum = UIColor(red: 0.93, green: 0.93, blue: 0.945, alpha: 1)
    var metalRoughness: CGFloat = 0.16
    var sapphire = UIColor(red: 0.12, green: 0.26, blue: 0.8, alpha: 1)
    /// A glow of the gems' own, such as the gilded knight's amber eyes; nil for none.
    var gemGlow: UIColor?
    var pearl = UIColor(red: 0.965, green: 0.95, blue: 0.93, alpha: 1)
    var lacquer = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    var lacquerRoughness: CGFloat = 0.42
    var lacquerCoat: CGFloat = 0.18
    /// The line around the squares; nil is platinum.
    var inlay: UIColor?

    /// The studio the pieces reflect: a soft light tent, or a dark room with a few soft boxes.
    var studio = "sculpted-env"
    /// How bright the studio is, and the key light that casts the shadows.
    var environment: CGFloat = 2.0
    var key: CGFloat = 1100
    var rim: CGFloat = 300
    var keyColor = UIColor.white
    var rimColor = UIColor(red: 0.9, green: 0.94, blue: 1, alpha: 1)
    /// A key that falls as a pool of light, brightest in the middle of the board, rather than
    /// lighting it evenly. The angles are where the pool starts to fade and where it ends, in degrees.
    var spot: (inner: CGFloat, outer: CGFloat)?

    /// The marks drawn on the stone: legal moves, best-move arrows.
    var accent = UIColor(red: 0.37, green: 0.56, blue: 1.0, alpha: 1)
    var check = UIColor(red: 1.0, green: 0.23, blue: 0.3, alpha: 1)
    var platinumMark = UIColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1)
    var lastMove = UIColor.white
    var lastMoveAlpha: CGFloat = 0.13
}

extension SculptedLook {
    /// The first 3D look: grey and black marble under an even light tent.
    static let classic = SculptedLook()

    /// Every look a theme can play in.
    static let all: [SculptedLook] = [.gilded, .noir, .classic, .bordeaux, .midnight]

    /// A dark studio, a warm key falling as a pool of light and a cool rim: deep color and crisp
    /// highlights. Spot lights come out about pi times brighter than directional ones in SceneKit,
    /// so the key is set to light the middle of the board about 1.5 times its stone color.
    private static func lit(_ look: SculptedLook) -> SculptedLook {
        var look = look
        look.studio = "sculpted-env-studio"
        look.environment = 1.2
        look.key = 410
        look.rim = 540
        look.keyColor = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
        look.rimColor = UIColor(red: 0.8, green: 0.87, blue: 1, alpha: 1)
        look.spot = (inner: 36, outer: 110)
        // A warm ivory a step deeper than the light squares, so the white pieces keep their shape on them.
        look.ivory = UIColor(red: 0.8, green: 0.75, blue: 0.665, alpha: 1)
        look.ebony = UIColor(red: 0.1, green: 0.095, blue: 0.09, alpha: 1)
        look.stoneRoughness = 0.22
        look.stoneCoat = 0.5
        look.lacquerRoughness = 0.28
        look.lacquerCoat = 0.7
        look.lastMoveAlpha = 0.15
        return look
    }

    /// The default: polished onyx and cream ivory with gold bands and crowns, and a knight with
    /// a striped gold mane and a glowing amber eye, on cream Calacatta and black Portoro marble
    /// with fine gold veins, ruled in gold.
    static let gilded: SculptedLook = {
        var look = lit(SculptedLook())
        look.name = "Gilded"
        look.pieces = "gilded-pieces"
        look.squares = "sculpted-squares-gilded"
        look.lacquer = UIColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)
        // Cream, so the white pieces stand apart from the white marble; onyx polished to a mirror.
        look.ivory = UIColor(red: 0.74, green: 0.67, blue: 0.56, alpha: 1)
        look.ebony = UIColor(red: 0.06, green: 0.06, blue: 0.066, alpha: 1)
        look.ivoryPolish = Polish(roughness: 0.3, coat: 0.6, coatRoughness: 0.05)
        look.ebonyPolish = Polish(roughness: 0.22, coat: 1, coatRoughness: 0.04)
        look.platinum = UIColor(red: 1, green: 0.8, blue: 0.55, alpha: 1)
        look.metalRoughness = 0.2
        look.sapphire = UIColor(red: 1, green: 0.62, blue: 0.22, alpha: 1)
        look.gemGlow = UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
        look.pearl = look.platinum
        look.inlay = UIColor(red: 0.95, green: 0.74, blue: 0.45, alpha: 1)
        look.platinumMark = UIColor(red: 0.95, green: 0.8, blue: 0.58, alpha: 1)
        return look
    }()

    /// Ivory and black marble, a champagne line and a black lacquer frame.
    static let noir: SculptedLook = {
        var look = lit(SculptedLook())
        look.name = "Noir"
        look.squares = "sculpted-squares-noir"
        look.lacquer = UIColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)
        look.inlay = UIColor(red: 0.8, green: 0.72, blue: 0.56, alpha: 1)
        look.platinumMark = UIColor(red: 0.86, green: 0.79, blue: 0.64, alpha: 1)
        return look
    }()

    /// Cream and deep wine-red marble, a black frame and platinum; the marks in warm gold.
    static let bordeaux: SculptedLook = {
        var look = lit(SculptedLook())
        look.name = "Bordeaux"
        look.squares = "sculpted-squares-bordeaux"
        look.lacquer = UIColor(red: 0.05, green: 0.04, blue: 0.04, alpha: 1)
        look.accent = UIColor(red: 0.92, green: 0.7, blue: 0.34, alpha: 1)
        return look
    }()

    /// Cream and ink-blue stone, a black frame and platinum; the marks in warm gold.
    static let midnight: SculptedLook = {
        var look = lit(SculptedLook())
        look.name = "Midnight"
        look.squares = "sculpted-squares-midnight"
        look.lacquer = UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1)
        look.accent = UIColor(red: 0.95, green: 0.74, blue: 0.36, alpha: 1)
        return look
    }()
}
