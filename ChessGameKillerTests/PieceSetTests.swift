import ChessKit
import SceneKit
import UIKit
import XCTest
@testable import ChessGameKiller

/// The piece sets chosen in Settings > Pieces: each dresses any 3D look in its own finish.
@MainActor
final class PieceSetTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PieceSet.storageKey)
        super.tearDown()
    }

    /// Stone is the board's own set: the look comes back as it went in, so nothing changes for
    /// anyone who never opens the picker.
    func testStoneLeavesEveryLookAlone() {
        for look in SculptedLook.all {
            let dressed = PieceSet.stone.dress(look)
            XCTAssertEqual(dressed.name, look.name)
            XCTAssertEqual(dressed.pieces, look.pieces)
            XCTAssertEqual(dressed.ivory, look.ivory)
            XCTAssertEqual(dressed.ebony, look.ebony)
        }
        XCTAssertEqual(PieceSet.current, .stone)
    }

    /// Every other set gets its own name on every board (the key its finishes are cached under and
    /// the id that makes the board again), keeps the board's stone, and loads all six pieces.
    func testEachSetDressesEveryLook() {
        let assets = SculptedAssets.shared
        var names: Set<String> = []
        for look in SculptedLook.all {
            for set in PieceSet.allCases where set != .stone {
                let dressed = set.dress(look)
                XCTAssertTrue(names.insert(dressed.name).inserted, "\(dressed.name) is used twice")
                XCTAssertNotEqual(dressed.name, look.name)
                XCTAssertEqual(dressed.squares, look.squares, "\(set.title) changed the \(look.name) stone")
                XCTAssertEqual(dressed.studio, look.studio)
                XCTAssertEqual(assets.parts(for: dressed).count, 6)
                for kind in Piece.Kind.allCases {
                    for color in [Piece.Color.white, .black] {
                        XCTAssertFalse(assets.makePiece(kind, color: color, look: dressed).childNodes.isEmpty)
                    }
                }
            }
        }
    }

    /// The two sides stay easy to tell apart in every set: their bodies differ clearly in brightness.
    func testTheSidesStayApart() {
        func brightness(_ color: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        for set in PieceSet.allCases {
            let look = set.dress(.gilded)
            XCTAssertGreaterThan(brightness(look.ivory) - brightness(look.ebony), 0.3, set.title)
        }
    }

    /// Each set draws its bodies in its own material: crystal lets the board through, the metal
    /// sets are metal, and none of it leaks into the Stone set's finishes.
    func testFinishesAreTheSetsOwn() {
        let assets = SculptedAssets.shared
        let stone = assets.material(.body, for: .white, look: .gilded)
        XCTAssertEqual(stone.transparency, 1)
        let crystal = assets.material(.body, for: .white, look: PieceSet.crystal.dress(.gilded))
        XCTAssertLessThan(crystal.transparency, 1)
        XCTAssertNotNil(crystal.shaderModifiers?[.fragment])
        XCTAssertNil(stone.shaderModifiers?[.fragment])
        XCTAssertFalse(crystal === stone)
        let gold = assets.material(.body, for: .white, look: PieceSet.sovereign.dress(.gilded))
        XCTAssertEqual((gold.metalness.contents as? NSNumber)?.doubleValue, 1)
        XCTAssertEqual((stone.metalness.contents as? NSNumber)?.doubleValue, 0)
    }

    /// The choice is remembered, and every set has a tile picture and a name.
    func testTheChoiceIsRememberedAndEverySetHasATile() {
        UserDefaults.standard.set(PieceSet.jade.rawValue, forKey: PieceSet.storageKey)
        XCTAssertEqual(PieceSet.current, .jade)
        UserDefaults.standard.set("no such set", forKey: PieceSet.storageKey)
        XCTAssertEqual(PieceSet.current, .stone)
        for set in PieceSet.allCases {
            XCTAssertNotNil(UIImage(named: "PieceSets/\(set.rawValue)"), "\(set.title) has no tile")
            XCTAssertFalse(set.title.isEmpty)
        }
        XCTAssertEqual(Set(PieceSet.allCases.map(\.title)).count, PieceSet.allCases.count)
    }
}
