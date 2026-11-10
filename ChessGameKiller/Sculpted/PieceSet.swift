import SwiftUI
import UIKit

/// What the pieces on the 3D board are made of, chosen in Settings > Pieces (Alex, 2026-11-09:
/// "very cool elegant beautiful piece options, specifically for the tilted view"). Stone is
/// the board's own set and the default; the others keep the same carved shapes and change only
/// their finish, so every piece is told apart exactly as before. The flat view keeps its
/// Floating Cut-outs in every set.
enum PieceSet: String, CaseIterable, Identifiable {
    case stone
    case blackPearl
    case jade
    case crystal
    case sovereign
    case porcelain

    static let storageKey = "pieceSet"

    var id: String { rawValue }

    /// The one chosen in Settings.
    static var current: PieceSet {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PieceSet.init(rawValue:)) ?? .stone
    }

    var title: String {
        switch self {
        case .stone: return "Stone"
        case .blackPearl: return "Black Pearl"
        case .jade: return "Imperial Jade"
        case .crystal: return "Crystal"
        case .sovereign: return "Sovereign"
        case .porcelain: return "Porcelain"
        }
    }

    /// The tile in Settings: the set itself on the gilded stone.
    var preview: Image { Image("PieceSets/\(rawValue)") }

    /// The look with this set's pieces on its board. Stone leaves the look as it is.
    func dress(_ look: SculptedLook) -> SculptedLook {
        guard self != .stone else { return look }
        var dressed = look
        // Its own name, so its finishes are cached apart and the board is made again in them.
        dressed.name = "\(look.name)·\(rawValue)"
        let gold = UIColor(red: 1, green: 0.84, blue: 0.58, alpha: 1)
        let goldGlow = UIColor(red: 0.42, green: 0.3, blue: 0.12, alpha: 1)
        func golden() {
            dressed.platinum = gold
            dressed.metalRoughness = 0.3
            dressed.metalGlow = goldGlow
            dressed.pearl = gold
            dressed.ivoryMetal = nil
            dressed.ivoryPearl = nil
        }
        switch self {
        case .stone:
            break
        case .blackPearl:
            // Mother-of-pearl and black pearl, shimmering toward their outlines, with platinum.
            dressed.pieces = "sculpted-pieces"
            dressed.ivory = UIColor(red: 0.93, green: 0.9, blue: 0.89, alpha: 1)
            dressed.ivoryPolish = .init(roughness: 0.2, coat: 1, coatRoughness: 0.03)
            dressed.ebony = UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)
            dressed.ebonyMetalness = 0.3
            dressed.ebonyPolish = .init(roughness: 0.15, coat: 1, coatRoughness: 0.02)
            dressed.nacre = 0.7
            dressed.platinum = UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
            dressed.metalRoughness = 0.16
            dressed.metalGlow = UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1)
            dressed.pearl = dressed.platinum
            dressed.ivoryMetal = UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
            dressed.ivoryPearl = dressed.ivoryMetal
            dressed.ivoryShade = UIColor(red: 0.3, green: 0.28, blue: 0.27, alpha: 1)
            dressed.sapphire = UIColor(red: 0.12, green: 0.26, blue: 0.8, alpha: 1)
            dressed.gemGlow = nil
        case .jade:
            // Pale jade, lit a little from inside, against polished onyx; gold and ruby eyes.
            dressed.pieces = "gilded-pieces"
            golden()
            dressed.ivory = UIColor(red: 0.63, green: 0.8, blue: 0.68, alpha: 1)
            dressed.ivoryPolish = .init(roughness: 0.18, coat: 1, coatRoughness: 0.04)
            dressed.ivoryGlow = UIColor(red: 0.05, green: 0.09, blue: 0.06, alpha: 1)
            dressed.ivoryShade = UIColor(red: 0.12, green: 0.2, blue: 0.14, alpha: 1)
            dressed.ebony = UIColor(red: 0.06, green: 0.06, blue: 0.066, alpha: 1)
            dressed.ebonyPolish = .init(roughness: 0.22, coat: 1, coatRoughness: 0.04)
            dressed.sapphire = UIColor(red: 0.75, green: 0.06, blue: 0.08, alpha: 1)
            dressed.gemGlow = UIColor(red: 0.6, green: 0.02, blue: 0.03, alpha: 1)
        case .crystal:
            // Clear crystal and smoked crystal, with gold. The stone shows through the middle of
            // each body, and the body turns solid toward its outline as glass does; the clear side
            // darkens there too, so it keeps its shape on the cream squares.
            dressed.pieces = "gilded-pieces"
            golden()
            dressed.ivory = UIColor(red: 0.84, green: 0.9, blue: 0.96, alpha: 1)
            dressed.ivoryPolish = .init(roughness: 0.04, coat: 1, coatRoughness: 0.01)
            dressed.ivoryEdge = 0.5
            dressed.ebony = UIColor(red: 0.1, green: 0.075, blue: 0.06, alpha: 1)
            dressed.ebonyPolish = .init(roughness: 0.04, coat: 1, coatRoughness: 0.01)
            dressed.clarity = 0.62
            dressed.ivoryShade = UIColor(red: 0.5, green: 0.5, blue: 0.52, alpha: 1)
            dressed.sapphire = UIColor(red: 1, green: 0.62, blue: 0.22, alpha: 1)
            dressed.gemGlow = UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
        case .sovereign:
            // Polished gold with platinum bands against blackened silver with gold bands.
            dressed.pieces = "gilded-pieces"
            golden()
            dressed.ivory = UIColor(red: 1, green: 0.82, blue: 0.55, alpha: 1)
            dressed.ivoryMetalness = 1
            dressed.ivoryPolish = .init(roughness: 0.2, coat: 0.3, coatRoughness: 0.05)
            dressed.ivoryGlow = UIColor(red: 0.36, green: 0.26, blue: 0.1, alpha: 1)
            dressed.ivoryEdge = 0.2
            dressed.ivoryMetal = UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)
            dressed.ivoryShade = UIColor(red: 0.2, green: 0.14, blue: 0.07, alpha: 1)
            dressed.ebony = UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1)
            dressed.ebonyMetalness = 1
            dressed.ebonyPolish = .init(roughness: 0.3, coat: 0.3, coatRoughness: 0.05)
            dressed.ebonyGlow = UIColor(red: 0.1, green: 0.1, blue: 0.11, alpha: 1)
            dressed.sapphire = UIColor(red: 0.75, green: 0.06, blue: 0.08, alpha: 1)
            dressed.gemGlow = UIColor(red: 0.6, green: 0.02, blue: 0.03, alpha: 1)
        case .porcelain:
            // Glazed white porcelain painted in cobalt against cobalt glaze painted in gold.
            dressed.pieces = "sculpted-pieces"
            golden()
            dressed.ivory = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
            dressed.ivoryPolish = .init(roughness: 0.1, coat: 1, coatRoughness: 0.02)
            dressed.ivoryMetal = UIColor(red: 0.1, green: 0.22, blue: 0.65, alpha: 1)
            dressed.ivoryPearl = dressed.ivoryMetal
            dressed.ivoryMarkMetalness = 0
            dressed.ivoryShade = UIColor(red: 0.25, green: 0.26, blue: 0.32, alpha: 1)
            dressed.ebony = UIColor(red: 0.06, green: 0.14, blue: 0.48, alpha: 1)
            dressed.ebonyPolish = .init(roughness: 0.1, coat: 1, coatRoughness: 0.02)
            dressed.sapphire = UIColor(red: 0.12, green: 0.26, blue: 0.8, alpha: 1)
            dressed.gemGlow = nil
        }
        return dressed
    }
}
